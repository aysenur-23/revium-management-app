/**
 * Dosya yükleme servisi
 * Backend'e dosya yükler ve Google Drive URL'lerini alır
 */

import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../utils/app_logger.dart';

/// Backend URL anahtarı (SharedPreferences)
const String _backendUrlKey = 'backend_base_url';

/// Backend URL'i - Platform bazlı otomatik ayarlanır veya kaydedilmiş değer kullanılır
Future<String> getBackendBaseUrl() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString(_backendUrlKey);
    
    if (savedUrl != null && savedUrl.isNotEmpty) {
      return savedUrl;
    }
  } catch (e) {
    // Hata durumunda varsayılan değere dön
  }

  // Production Backend URL - Supabase Edge Functions
  // Supabase project: nemwuunbowzuuyvhmehi
  const String productionBackendUrl = AppConfig.productionBackendUrl;
  
  // Eğer Railway deploy edilmediyse, boş bırakın ve kullanıcı Settings'ten ayarlayabilir
  
  // Eğer production URL ayarlanmışsa onu kullan (en yüksek öncelik)
  if (productionBackendUrl.isNotEmpty) {
    return productionBackendUrl;
  }
  
  // Kullanıcının ayarladığı URL varsa onu kullan (ikinci öncelik)
  try {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString(_backendUrlKey);
    if (savedUrl != null && savedUrl.isNotEmpty) {
      return savedUrl;
    }
  } catch (e) {
    // Hata durumunda varsayılan değere dön
  }
  
  // Varsayılan platform bazlı URL'ler (son çare)
  if (kIsWeb) {
    return 'http://localhost:4000';
  } else if (Platform.isAndroid) {
    // Android için varsayılan: Production backend URL'i eklenmemişse
    // kullanıcı Settings'ten ayarlayabilir, ama varsayılan olarak
    // emülatör URL'i kullanılır (gerçek cihazda çalışmaz)
    return 'http://10.0.2.2:4000';
  } else if (Platform.isIOS) {
    return 'http://localhost:4000';
  } else {
    return 'http://localhost:4000';
  }
}

/// Backend base URL - kullanım için (async)
Future<String> get backendBaseUrl => getBackendBaseUrl();

/// Upload sonucu modeli
class UploadResult {
  final String fileId;
  final String fileUrl;
  final String? webViewLink; // Google Drive webViewLink (varsa)

  UploadResult({
    required this.fileId,
    required this.fileUrl,
    this.webViewLink,
  });

  factory UploadResult.fromJson(Map<String, dynamic> json) {
    return UploadResult(
      fileId: json['fileId'] as String,
      fileUrl: json['fileUrl'] as String,
      webViewLink: json['webViewLink'] as String?,
    );
  }
}

class UploadService {
  /// Dosyayı backend'e yükler ve UploadResult döndürür
  static Future<UploadResult> uploadFile({
    File? file,
    Uint8List? fileBytes,
    String? fileName,
    required String ownerId,
    required String ownerName,
    required double amount,
    required String description,
    String? notes,
  }) async {
    try {
      if (!kIsWeb && file == null) {
        AppLogger.error('❌ Mobil platformda dosya (File) gerekli ama null');
        throw Exception('Mobil platformda dosya (File) gerekli.');
      }
      if (kIsWeb && (fileBytes == null || fileName == null)) {
        AppLogger.error('❌ Web platformunda dosya baytları veya dosya adı eksik');
        throw Exception('Web platformunda dosya baytları ve dosya adı gerekli.');
      }
      
      AppLogger.info('📤 Dosya yükleme başlatılıyor...');
      AppLogger.info('   → Platform: ${kIsWeb ? "Web" : "Mobil"}');
      AppLogger.info('   → Dosya adı: $fileName');
      AppLogger.info('   → Dosya boyutu: ${kIsWeb ? fileBytes!.length : await file!.length()} bytes');
      AppLogger.info('   → Owner: $ownerName ($ownerId)');
      AppLogger.info('   → Amount: $amount');
      AppLogger.info('   → Description: $description');

      final baseUrl = await getBackendBaseUrl();
      // Supabase Edge Function için: baseUrl zaten /functions/v1/upload şeklinde
      // Direkt baseUrl'i kullan, tekrar /upload ekleme
      final uri = Uri.parse(baseUrl);
      final request = http.MultipartRequest('POST', uri);
      
      // Supabase Edge Function için authorization header ekle
      if (baseUrl.contains('supabase.co')) {
        // Supabase Edge Functions için gerekli header'lar
        request.headers['apikey'] = AppConfig.supabaseAnonKey;
        request.headers['Authorization'] = 'Bearer ${AppConfig.supabaseAnonKey}';
      }

      if (kIsWeb) {
        request.files.add(http.MultipartFile.fromBytes(
          'file',
          fileBytes!,
          filename: fileName,
        ));
      } else {
        final fileStream = file!.openRead();
        final fileLength = await file.length();
        final multipartFile = http.MultipartFile(
          'file',
          fileStream,
          fileLength,
          filename: file.path.split('/').last,
        );
        request.files.add(multipartFile);
      }

      // ownerId, ownerName, amount, description ve notes'u ekle (dosya isimlendirme ve Sheets için)
      request.fields['ownerId'] = ownerId;
      request.fields['ownerName'] = ownerName;
      request.fields['amount'] = amount.toString();
      request.fields['description'] = description;
      if (notes != null && notes.isNotEmpty) {
        request.fields['notes'] = notes;
      }

      // İsteği gönder (timeout ile, retry mekanizması ile)
      http.StreamedResponse? streamedResponse;
      http.Response? response;
      
      for (int attempt = 0; attempt <= AppConfig.maxRetries; attempt++) {
        try {
          if (attempt > 0) {
            AppLogger.warning('Upload retry attempt $attempt/${AppConfig.maxRetries}');
            await Future.delayed(AppConfig.retryDelay);
          }
          
          streamedResponse = await request.send().timeout(
            Duration(seconds: AppConfig.uploadTimeoutSeconds),
            onTimeout: () {
              throw Exception('Dosya yükleme zaman aşımı. İnternet bağlantınızı kontrol edin.');
            },
          );
          
          response = await http.Response.fromStream(streamedResponse).timeout(
            Duration(seconds: AppConfig.responseTimeoutSeconds),
            onTimeout: () {
              throw Exception('Yanıt alma zaman aşımı. Lütfen tekrar deneyin.');
            },
          );
          
          // Başarılı ise retry döngüsünden çık
          break;
        } catch (e) {
          if (attempt == AppConfig.maxRetries) {
            rethrow;
          }
          AppLogger.warning('Upload attempt $attempt failed: $e');
        }
      }
      
      if (response == null) {
        throw Exception('Upload başarısız: Yanıt alınamadı');
      }

      if (response.statusCode == 200) {
        try {
          final jsonResponse = json.decode(response.body) as Map<String, dynamic>;
          return UploadResult.fromJson(jsonResponse);
        } catch (e, stackTrace) {
          AppLogger.error('Backend yanıtı geçersiz', e, stackTrace);
          throw Exception('Backend yanıtı geçersiz: ${e.toString()}');
        }
      } else {
        final errorBody = response.body;
        String errorMessage = 'Upload başarısız: ${response.statusCode}';
        try {
          final errorJson = json.decode(errorBody) as Map<String, dynamic>?;
          if (errorJson != null) {
            // Önce message'ı kontrol et (daha detaylı)
            if (errorJson['message'] != null) {
              errorMessage = errorJson['message'] as String;
            } else if (errorJson['error'] != null) {
              errorMessage = errorJson['error'] as String;
            }
            // Debug bilgisi varsa ekle
            if (errorJson['debug'] != null) {
              final debug = errorJson['debug'] as Map<String, dynamic>?;
              if (debug != null) {
                errorMessage += '\nDebug: ${debug.toString()}';
              }
            }
          }
        } catch (e) {
          // JSON parse edilemezse body'yi kullan
          AppLogger.error('Error body parse hatası', e);
          if (errorBody.length < 500) {
            errorMessage += ' - $errorBody';
          } else {
            errorMessage += ' - ${errorBody.substring(0, 500)}...';
          }
        }
        AppLogger.error('Backend error response: Status=${response.statusCode}, Body=$errorBody');
        
        // Kullanıcı dostu hata mesajları
        if (response.statusCode == 401 || response.statusCode == 403) {
          errorMessage = 'Google Drive erişim hatası. Lütfen yetkilendirmeyi kontrol edin.';
        } else if (response.statusCode == 404) {
          errorMessage = 'Backend servisi bulunamadı. Lütfen bağlantınızı kontrol edin.';
        } else if (response.statusCode == 500 || response.statusCode == 502 || response.statusCode == 503) {
          errorMessage = 'Sunucu hatası. Lütfen daha sonra tekrar deneyin.';
        } else if (response.statusCode == 408 || response.statusCode == 504) {
          errorMessage = 'İstek zaman aşımına uğradı. Lütfen tekrar deneyin.';
        }
        
        throw Exception(errorMessage);
      }
    } catch (e, stackTrace) {
      AppLogger.error('Dosya yükleme hatası', e, stackTrace);
      // Zaten Exception ise direkt fırlat
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Dosya yükleme hatası: ${e.toString()}');
    }
  }

  /// Backend'in çalışıp çalışmadığını kontrol eder
  static Future<bool> checkBackendHealth() async {
    try {
      final baseUrl = await getBackendBaseUrl();
      // Health check için baseUrl'e /health ekle
      // Supabase Edge Function'da pathname.endsWith('/health') kontrolü var
      final healthUrl = baseUrl.endsWith('/upload') 
          ? baseUrl.replaceAll('/upload', '/health')
          : '$baseUrl/health';
      final uri = Uri.parse(healthUrl);
      
      final request = http.Request('GET', uri);
      
      // Supabase Edge Function için authorization header ekle
      if (baseUrl.contains('supabase.co')) {
        request.headers['apikey'] = AppConfig.supabaseAnonKey;
        request.headers['Authorization'] = 'Bearer ${AppConfig.supabaseAnonKey}';
      }
      
      final response = await request.send().timeout(
        Duration(seconds: AppConfig.healthCheckTimeoutSeconds),
      );
      
      final responseBody = await http.Response.fromStream(response).timeout(
        Duration(seconds: AppConfig.healthCheckTimeoutSeconds),
      );

      return responseBody.statusCode == 200;
    } catch (e) {
      AppLogger.debug('Backend health check hatası: $e');
      return false;
    }
  }

  /// Backend URL'ini kaydeder (gerçek cihaz için)
  static Future<void> setBackendBaseUrl(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_backendUrlKey, url);
    } catch (e) {
      // Hata durumunda sessizce geç
    }
  }

  /// Kaydedilmiş backend URL'ini getirir
  static Future<String?> getSavedBackendUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_backendUrlKey);
    } catch (e) {
      return null;
    }
  }

  /// Google Drive'dan dosyayı backend üzerinden indirir
  /// Backend artık direkt dosya içeriği yerine download linki döndürüyor
  static Future<Uint8List> downloadFileFromDrive(String fileId) async {
    try {
      // Her zaman production URL kullan (SharedPreferences'taki yanlış değerleri atla)
      final baseUrl = AppConfig.productionBackendUrl;
      
      // URL'i doğrudan oluştur
      final uri = Uri.parse('$baseUrl?fileId=$fileId');
      
      AppLogger.info('🔹 Backend download URL: $uri');
      AppLogger.info('🔹 File ID: $fileId');
      
      final request = http.Request('GET', uri);
      request.headers['apikey'] = AppConfig.supabaseAnonKey;
      request.headers['Authorization'] = 'Bearer ${AppConfig.supabaseAnonKey}';
      
      AppLogger.info('🔹 Backend isteği gönderiliyor...');
      final stopwatch = Stopwatch()..start();
      
      final response = await request.send().timeout(
        Duration(seconds: AppConfig.uploadTimeoutSeconds),
        onTimeout: () {
          throw Exception('Backend zaman aşımı');
        },
      );
      
      AppLogger.info('🔹 Backend yanıt: status=${response.statusCode}, elapsed=${stopwatch.elapsedMilliseconds}ms');
      
      final responseBody = await http.Response.fromStream(response);
      stopwatch.stop();
      
      AppLogger.info('🔹 Body: ${responseBody.body.length > 200 ? responseBody.body.substring(0, 200) : responseBody.body}');
      
      if (response.statusCode == 200) {
        final json = jsonDecode(responseBody.body);
        final downloadLink = json['directDownloadLink'] as String? ?? json['webContentLink'] as String?;
        
        if (downloadLink != null) {
          AppLogger.info('✅ Download link: $downloadLink');
          
          final fileResponse = await http.get(Uri.parse(downloadLink)).timeout(
            Duration(seconds: AppConfig.uploadTimeoutSeconds * 2),
          );
          
          if (fileResponse.statusCode == 200 && fileResponse.bodyBytes.isNotEmpty) {
            AppLogger.success('✅ Dosya indirildi (${fileResponse.bodyBytes.length} bytes)');
            return fileResponse.bodyBytes;
          } else {
            throw Exception('Dosya indirme hatası: ${fileResponse.statusCode}');
          }
        } else {
          throw Exception('Download link bulunamadı');
        }
      } else {
        String errorMessage = 'Backend hatası: ${response.statusCode}';
        try {
          final errorJson = jsonDecode(responseBody.body);
          errorMessage = errorJson['message'] ?? errorJson['error'] ?? errorMessage;
        } catch (_) {}
        throw Exception(errorMessage);
      }
    } catch (e) {
      AppLogger.error('❌ Download hatası', e);
      rethrow;
    }
  }

  /// Google Drive'dan dosyayı siler
  static Future<void> deleteFile(String fileId) async {
    try {
      final baseUrl = await getBackendBaseUrl();
      // Delete endpoint için baseUrl'e /delete ekle
      final deleteUrl = baseUrl.endsWith('/upload') 
          ? baseUrl.replaceAll('/upload', '/delete')
          : '$baseUrl/delete';
      final uri = Uri.parse(deleteUrl);
      
      AppLogger.info('Dosya siliniyor: $fileId');
      
      final request = http.Request('POST', uri);
      request.headers['Content-Type'] = 'application/json';
      
      // Supabase Edge Function için authorization header ekle
      if (baseUrl.contains('supabase.co')) {
        request.headers['apikey'] = AppConfig.supabaseAnonKey;
        request.headers['Authorization'] = 'Bearer ${AppConfig.supabaseAnonKey}';
      }
      
      // Request body
      request.body = jsonEncode({
        'fileId': fileId,
      });
      
      final response = await request.send().timeout(
        Duration(seconds: AppConfig.uploadTimeoutSeconds),
      );
      
      final responseBody = await http.Response.fromStream(response).timeout(
        Duration(seconds: AppConfig.uploadTimeoutSeconds),
      );

      if (responseBody.statusCode == 200 || responseBody.statusCode == 201) {
        AppLogger.info('Dosya başarıyla silindi: $fileId');
        return;
      } else {
        String errorMessage = 'Dosya silinemedi';
        final errorBody = responseBody.body;
        
        try {
          final errorJson = jsonDecode(errorBody) as Map<String, dynamic>?;
          if (errorJson != null) {
            if (errorJson['message'] != null) {
              errorMessage = errorJson['message'] as String;
            } else if (errorJson['error'] != null) {
              errorMessage = errorJson['error'] as String;
            }
          }
        } catch (e) {
          AppLogger.error('Error body parse hatası', e);
          if (errorBody.length < 500) {
            errorMessage += ' - $errorBody';
          } else {
            errorMessage += ' - ${errorBody.substring(0, 500)}...';
          }
        }
        AppLogger.error('Backend delete error response: Status=${responseBody.statusCode}, Body=$errorBody');
        
        // Kullanıcı dostu hata mesajları
        if (responseBody.statusCode == 401 || responseBody.statusCode == 403) {
          errorMessage = 'Google Drive erişim hatası. Dosya silinemedi.';
        } else if (responseBody.statusCode == 404) {
          errorMessage = 'Dosya bulunamadı. Zaten silinmiş olabilir.';
        } else if (responseBody.statusCode == 500 || responseBody.statusCode == 502 || responseBody.statusCode == 503) {
          errorMessage = 'Sunucu hatası. Lütfen daha sonra tekrar deneyin.';
        }
        
        throw Exception(errorMessage);
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Dosya silme hatası: ${e.toString()}');
    }
  }

  /// Google Sheets linkini alır
  static Future<String?> getGoogleSheetsUrl() async {
    try {
      final baseUrl = await getBackendBaseUrl();
      // Supabase Edge Function için: baseUrl zaten /upload ile bitiyor, /sheets'e çevir
      String sheetsUrl;
      if (baseUrl.contains('supabase.co')) {
        if (baseUrl.endsWith('/upload')) {
          sheetsUrl = baseUrl.substring(0, baseUrl.length - 6) + 'sheets';
        } else {
          sheetsUrl = baseUrl.replaceAll('/upload', '/sheets');
        }
      } else {
        sheetsUrl = baseUrl.endsWith('/') ? '${baseUrl}sheets' : '$baseUrl/sheets';
      }
      final uri = Uri.parse(sheetsUrl);

      final request = http.Request('GET', uri);

      // Supabase Edge Function için authorization header ekle
      if (baseUrl.contains('supabase.co')) {
        request.headers['apikey'] = AppConfig.supabaseAnonKey;
        request.headers['Authorization'] = 'Bearer ${AppConfig.supabaseAnonKey}';
      }

      final response = await request.send().timeout(
        Duration(seconds: AppConfig.uploadTimeoutSeconds),
        onTimeout: () {
          throw Exception('Backend zaman aşımı. İnternet bağlantınızı kontrol edin.');
        },
      );

      final responseBody = await http.Response.fromStream(response).timeout(
        Duration(seconds: AppConfig.uploadTimeoutSeconds),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(responseBody.body) as Map<String, dynamic>;
        final url = json['url'] as String?;
        if (url != null) {
          AppLogger.info('Google Sheets URL alındı: $url');
          return url;
        }
      } else if (response.statusCode == 404) {
        // Sheets dosyası henüz oluşturulmamış
        AppLogger.warning('Google Sheets dosyası henüz oluşturulmamış');
        return null;
      } else {
        String errorMessage = 'Google Sheets linki alınamadı';
        try {
          final errorJson = jsonDecode(responseBody.body) as Map<String, dynamic>?;
          if (errorJson != null && errorJson['message'] != null) {
            errorMessage = errorJson['message'] as String;
          }
        } catch (e) {
          AppLogger.error('Error body parse hatası', e);
        }
        AppLogger.error('Backend sheets error response: Status=${response.statusCode}, Body=${responseBody.body}');
        throw Exception(errorMessage);
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Google Sheets linki alınamadı: ${e.toString()}');
    }
    return null;
  }

  /// Excel'i mevcut tüm entry'lerle oluşturur
  static Future<Map<String, dynamic>?> initializeGoogleSheetsWithEntries(
    List<Map<String, dynamic>> entries,
  ) async {
    return _createExcelFile(entries: entries, fileName: 'Tüm Eklenenler.csv');
  }

  /// Excel'i kullanıcının kendi entry'leriyle oluşturur
  static Future<Map<String, dynamic>?> createMyEntriesExcel(
    List<Map<String, dynamic>> entries,
  ) async {
    return _createExcelFile(entries: entries, fileName: 'Eklediklerim.csv');
  }

  /// Excel oluşturma yardımcı fonksiyonu
  static Future<Map<String, dynamic>?> _createExcelFile({
    required List<Map<String, dynamic>> entries,
    required String fileName,
  }) async {
    try {
      // Her zaman production URL kullan
      final baseUrl = AppConfig.productionBackendUrl;
      final uri = Uri.parse('$baseUrl?endpoint=init-sheets');

      final request = http.Request('POST', uri);
      request.headers['Content-Type'] = 'application/json';
      request.headers['apikey'] = AppConfig.supabaseAnonKey;
      request.headers['Authorization'] = 'Bearer ${AppConfig.supabaseAnonKey}';

      // Entry'leri formatla
      final formattedEntries = entries.map((entry) {
        return {
          'dateTime': entry['createdAt']?.toString() ?? DateTime.now().toIso8601String(),
          'notes': entry['notes'] ?? '',
          'ownerName': entry['ownerName'] ?? '',
          'amount': entry['amount']?.toDouble() ?? 0.0,
          'description': entry['description'] ?? '',
          'fileUrl': entry['fileUrl'] ?? '',
        };
      }).toList();

      // sheetName: sabit dosya adı (aynı isimde dosya varsa güncellenir)
      final sheetName = fileName.replaceAll('.csv', '').replaceAll(RegExp(r'_\d{4}-\d{2}-\d{2}'), '');
      request.body = jsonEncode({
        'entries': formattedEntries,
        'sheetName': sheetName,
      });

      AppLogger.info('Excel oluşturma isteği: $uri');

      final response = await request.send().timeout(
        Duration(seconds: AppConfig.uploadTimeoutSeconds * 2),
        onTimeout: () {
          throw Exception('Backend zaman aşımı');
        },
      );

      final responseBody = await http.Response.fromStream(response);

      if (response.statusCode == 200) {
        final json = jsonDecode(responseBody.body) as Map<String, dynamic>;
        AppLogger.info('Excel oluşturuldu: ${json['url']}');
        return json;
      } else {
        AppLogger.error('Excel hata: ${response.statusCode} - ${responseBody.body}');
        throw Exception('Excel oluşturulamadı: ${response.statusCode}');
      }
    } catch (e) {
      AppLogger.error('Excel oluşturma hatası', e);
      rethrow;
    }
  }

  /// Excel'i tüm entry'ler ve sabit giderlerle oluşturur (Ayarlar sayfası için)
  static Future<Map<String, dynamic>?> initializeGoogleSheetsWithAllData(
    List<Map<String, dynamic>> entries,
    List<Map<String, dynamic>> fixedExpenses,
  ) async {
    try {
      // Her zaman production URL kullan
      final baseUrl = AppConfig.productionBackendUrl;
      final uri = Uri.parse('$baseUrl?endpoint=init-sheets');

      final request = http.Request('POST', uri);
      request.headers['Content-Type'] = 'application/json';
      request.headers['apikey'] = AppConfig.supabaseAnonKey;
      request.headers['Authorization'] = 'Bearer ${AppConfig.supabaseAnonKey}';

      // Entry'leri formatla
      final formattedEntries = entries.map((entry) {
        return {
          'dateTime': entry['createdAt']?.toString() ?? DateTime.now().toIso8601String(),
          'notes': entry['notes'] ?? '',
          'ownerName': entry['ownerName'] ?? '',
          'amount': entry['amount']?.toDouble() ?? 0.0,
          'description': entry['description'] ?? '',
          'fileUrl': entry['fileUrl'] ?? '',
        };
      }).toList();

      // Sabit giderleri formatla
      final formattedFixedExpenses = fixedExpenses.map((expense) {
        return {
          'dateTime': expense['startDate']?.toString() ?? expense['createdAt']?.toString() ?? DateTime.now().toIso8601String(),
          'notes': expense['notes'] ?? '',
          'ownerName': expense['ownerName'] ?? '',
          'amount': expense['amount']?.toDouble() ?? 0.0,
          'description': expense['description'] ?? '',
          'category': expense['category'] ?? '',
          'recurrence': expense['recurrence'] ?? '',
          'isActive': expense['isActive'] ?? true,
        };
      }).toList();

      request.body = jsonEncode({
        'entries': formattedEntries,
        'fixedExpenses': formattedFixedExpenses,
        'sheetName': 'Tum_Harcamalar', // Sabit dosya adı
      });

      AppLogger.info('Excel (All Data) oluşturma isteği: $uri');

      final response = await request.send().timeout(
        Duration(seconds: AppConfig.uploadTimeoutSeconds * 2),
        onTimeout: () {
          throw Exception('Backend zaman aşımı');
        },
      );

      final responseBody = await http.Response.fromStream(response);

      if (response.statusCode == 200) {
        final json = jsonDecode(responseBody.body) as Map<String, dynamic>;
        AppLogger.info('Excel (All Data) oluşturuldu: ${json['url']}');
        return json;
      } else {
        AppLogger.error('Excel hata: ${response.statusCode} - ${responseBody.body}');
        throw Exception('Excel oluşturulamadı: ${response.statusCode}');
      }
    } catch (e) {
      AppLogger.error('Excel oluşturma hatası', e);
      rethrow;
    }
  }

  /// Google Sheets'i mevcut tüm sabit giderlerle oluşturur/günceller
  static Future<Map<String, dynamic>?> initializeGoogleSheetsWithFixedExpenses(
    List<Map<String, dynamic>> fixedExpenses,
  ) async {
    try {
      // Her zaman production URL kullan
      final baseUrl = AppConfig.productionBackendUrl;
      final uri = Uri.parse('$baseUrl?endpoint=init-sheets');

      final request = http.Request('POST', uri);
      request.headers['Content-Type'] = 'application/json';
      request.headers['apikey'] = AppConfig.supabaseAnonKey;
      request.headers['Authorization'] = 'Bearer ${AppConfig.supabaseAnonKey}';

      // Sabit giderleri formatla
      final formattedFixedExpenses = fixedExpenses.map((expense) {
        return {
          'dateTime': expense['startDate']?.toString() ?? expense['createdAt']?.toString() ?? DateTime.now().toIso8601String(),
          'notes': expense['notes'] ?? '',
          'ownerName': expense['ownerName'] ?? '',
          'amount': expense['amount']?.toDouble() ?? 0.0,
          'description': expense['description'] ?? '',
          'category': expense['category'] ?? '',
          'recurrence': expense['recurrence'] ?? '',
          'isActive': expense['isActive'] ?? true,
        };
      }).toList();

      request.body = jsonEncode({
        'fixedExpenses': formattedFixedExpenses,
        'sheetName': 'Sabit_Giderler', // Sabit dosya adı
      });

      AppLogger.info('Excel (Fixed Expenses) oluşturma isteği: $uri');

      final response = await request.send().timeout(
        Duration(seconds: AppConfig.uploadTimeoutSeconds * 2),
        onTimeout: () {
          throw Exception('Backend zaman aşımı');
        },
      );

      final responseBody = await http.Response.fromStream(response);

      if (response.statusCode == 200) {
        final json = jsonDecode(responseBody.body) as Map<String, dynamic>;
        AppLogger.info('Excel (Fixed Expenses) oluşturuldu: ${json['url']}');
        return json;
      } else {
        AppLogger.error('Excel hata: ${response.statusCode} - ${responseBody.body}');
        throw Exception('Excel oluşturulamadı: ${response.statusCode}');
      }
    } catch (e) {
      AppLogger.error('Excel oluşturma hatası', e);
      rethrow;
    }
  }
}

