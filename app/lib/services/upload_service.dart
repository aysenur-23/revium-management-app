/// Dosya yükleme servisi
/// Backend'e dosya yükler ve Google Drive URL'lerini alır
library;

import 'package:cross_file/cross_file.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../utils/app_logger.dart';
import 'drive_token_service.dart';

/// Backend URL anahtarı (SharedPreferences)
const String _backendUrlKey = 'backend_base_url';

/// Backend URL'i - Platform bazlı otomatik ayarlanır veya kaydedilmiş değer kullanılır
Future<String> getBackendBaseUrl() async {
  // Production Backend URL - Firebase Cloud Functions (veya localhost development için)
  const String productionBackendUrl = AppConfig.productionBackendUrl;
  
  // Eğer production URL ayarlanmışsa onu kullan (en yüksek öncelik - development dahil)
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
  } else if (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) {
    // Mobil cihazlar için localhost (10.0.2.2 emülatörler için genelde kullanılır)
    // Ancak productionBackendUrl ayarlı olduğu sürece buraya girmeyecektir.
    return 'http://10.0.2.2:4000';
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
  /// Multipart encoding sorunlarını azaltmak için dosya adındaki Türkçe karakterleri ASCII'ye çevirir.
  static String _sanitizeFileNameForUpload(String name) {
    if (name.isEmpty) return 'file';
    return name
        .replaceAll('ı', 'i').replaceAll('İ', 'I')
        .replaceAll('ğ', 'g').replaceAll('Ğ', 'G')
        .replaceAll('ü', 'u').replaceAll('Ü', 'U')
        .replaceAll('ş', 's').replaceAll('Ş', 'S')
        .replaceAll('ö', 'o').replaceAll('Ö', 'O')
        .replaceAll('ç', 'c').replaceAll('Ç', 'C');
  }

  /// Dosyayı backend'e yükler ve UploadResult döndürür
  static Future<UploadResult> uploadFile({
    XFile? file,
    Uint8List? fileBytes,
    String? fileName,
    required String ownerId,
    required String ownerName,
    required double amount,
    required String description,
    String? notes,
    String entryType = 'expense', // 'expense' veya 'income'
  }) async {
    try {
      final useBytes = fileBytes != null && fileName != null && fileBytes.isNotEmpty;
      final useFile = file != null;
      if (kIsWeb) {
        if (!useBytes) {
          AppLogger.error('❌ Web platformunda dosya baytları ve dosya adı gerekli.');
          throw Exception('Web platformunda dosya baytları ve dosya adı gerekli.');
        }
      } else {
        if (!useBytes && !useFile) {
          AppLogger.error('❌ Mobil: Dosya için fileBytes+fileName veya XFile gerekli.');
          throw Exception('Dosya gerekli: fileBytes+fileName veya XFile verin.');
        }
      }

      final int fileLength;
      final String nameForLog;
      if (useBytes) {
        fileLength = fileBytes!.length; // ignore: unnecessary_non_null_assertion
        nameForLog = fileName ?? ''; // ignore: dead_null_aware_expression
      } else {
        final f = file!;
        fileLength = await f.length();
        nameForLog = f.name;
      }

      AppLogger.info('📤 Dosya yükleme başlatılıyor...');
      AppLogger.info('   → Platform: ${kIsWeb ? "Web" : "Mobil"}');
      AppLogger.info('   → Dosya adı: $nameForLog');
      AppLogger.info('   → Dosya boyutu: $fileLength bytes');
      AppLogger.info('   → Owner: $ownerName ($ownerId)');
      AppLogger.info('   → Amount: $amount');
      AppLogger.info('   → Description: $description');

      final baseUrl = await getBackendBaseUrl();
      // Firebase Cloud Functions için: baseUrl'e /upload ekle
      final uploadUrl = baseUrl.endsWith('/') ? '${baseUrl}upload' : '$baseUrl/upload';
      final uri = Uri.parse(uploadUrl);
      final request = http.MultipartRequest('POST', uri);

      // Multipart encoding sorunlarını azaltmak için dosya adını ASCII'ye çevir (Türkçe karakterler)
      final safeFileName = _sanitizeFileNameForUpload(fileName ?? nameForLog);

      if (useBytes) {
        request.files.add(http.MultipartFile.fromBytes(
          'file',
          fileBytes!, // ignore: unnecessary_non_null_assertion
          filename: safeFileName,
        ));
      } else {
        final f = file!;
        request.files.add(http.MultipartFile(
          'file',
          f.openRead(),
          fileLength,
          filename: safeFileName,
        ));
      }

      // ownerId, ownerName, amount, description, notes ve entryType'ı ekle (dosya isimlendirme ve Sheets için)
      request.fields['ownerId'] = ownerId;
      request.fields['ownerName'] = ownerName;
      request.fields['amount'] = amount.toString();
      request.fields['description'] = description;
      request.fields['entryType'] = entryType;
      if (notes != null && notes.isNotEmpty) {
        request.fields['notes'] = notes;
      }

      // İsteği gönder (timeout ile, retry mekanizması ile)
      // Her retry'da yeni request oluşturulmalı (bir request sadece bir kez finalize edilebilir)
      http.StreamedResponse? streamedResponse;
      http.Response? response;
      
      for (int attempt = 0; attempt <= AppConfig.maxRetries; attempt++) {
        try {
          if (attempt > 0) {
            AppLogger.warning('Upload retry attempt $attempt/${AppConfig.maxRetries}');
            await Future.delayed(AppConfig.retryDelay);
            
            // Her retry'da yeni request oluştur
            final retryRequest = http.MultipartRequest('POST', uri);
            
            if (useBytes) {
              retryRequest.files.add(http.MultipartFile.fromBytes(
                'file',
                fileBytes!, // ignore: unnecessary_non_null_assertion
                filename: safeFileName,
              ));
            } else {
              final f = file!;
              retryRequest.files.add(http.MultipartFile(
                'file',
                f.openRead(),
                fileLength,
                filename: safeFileName,
              ));
            }
            
            // Form alanlarını tekrar ekle
            retryRequest.fields['ownerId'] = ownerId;
            retryRequest.fields['ownerName'] = ownerName;
            retryRequest.fields['amount'] = amount.toString();
            retryRequest.fields['description'] = description;
            retryRequest.fields['entryType'] = entryType;
            if (notes != null && notes.isNotEmpty) {
              retryRequest.fields['notes'] = notes;
            }
            
            streamedResponse = await retryRequest.send().timeout(
              const Duration(seconds: AppConfig.uploadTimeoutSeconds),
              onTimeout: () {
                throw Exception('Dosya yükleme zaman aşımı. İnternet bağlantınızı kontrol edin.');
              },
            );
          } else {
            // İlk deneme - orijinal request'i kullan
            streamedResponse = await request.send().timeout(
              const Duration(seconds: AppConfig.uploadTimeoutSeconds),
              onTimeout: () {
                throw Exception('Dosya yükleme zaman aşımı. İnternet bağlantınızı kontrol edin.');
              },
            );
          }
          
          response = await http.Response.fromStream(streamedResponse).timeout(
            const Duration(seconds: AppConfig.responseTimeoutSeconds),
            onTimeout: () {
              throw Exception('Yanıt alma zaman aşımı. Lütfen tekrar deneyin.');
            },
          );

          if (response.statusCode == 200) {
            final body = response.body;
            if (body.isEmpty) {
              if (attempt < AppConfig.maxRetries) {
                AppLogger.warning('Boş yanıt alındı, yeniden denenecek ($attempt/${AppConfig.maxRetries})');
                await Future.delayed(AppConfig.retryDelay);
                continue;
              }
              AppLogger.error('Backend yanıtı boş', null);
              throw Exception('Sunucu yanıtı boş. Bağlantı koptu olabilir, tekrar deneyin.');
            }
            try {
              final jsonResponse = json.decode(body) as Map<String, dynamic>;
              return UploadResult.fromJson(jsonResponse);
            } on FormatException catch (e, stackTrace) {
              if (attempt < AppConfig.maxRetries) {
                AppLogger.warning('Yanıt eksik/bozuk, yeniden denenecek ($attempt/${AppConfig.maxRetries})');
                await Future.delayed(AppConfig.retryDelay);
                continue;
              }
              AppLogger.error('Backend yanıtı parse hatası (eksik/bozuk yanıt)', e, stackTrace);
              throw Exception('Sunucu yanıtı eksik veya bozuk. İnternet bağlantınızı kontrol edip tekrar deneyin.');
            } catch (e, stackTrace) {
              AppLogger.error('Backend yanıtı geçersiz', e, stackTrace);
              throw Exception('Backend yanıtı geçersiz: ${e.toString()}');
            }
          }
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

      if (response.statusCode != 200) {
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
          // JSON parse edilemezse (örn. HTML 500) body'yi kullan
          AppLogger.error('Error body parse hatası', e);
          if (errorBody.length < 500) {
            errorMessage += ' - $errorBody';
          } else {
            errorMessage += ' - ${errorBody.substring(0, 500)}...';
          }
        }
        AppLogger.error('Backend error response: Status=${response.statusCode}, Body=$errorBody');

        // Backend JSON'dan anlamlı mesaj alındıysa onu kullan; yoksa genel mesajlar
        final parsedMessage = errorMessage != 'Upload başarısız: ${response.statusCode}' &&
            !errorMessage.startsWith('Upload başarısız: ${response.statusCode} - ');
        if (!parsedMessage) {
          if (response.statusCode == 401 || response.statusCode == 403) {
            errorMessage = 'Google Drive erişim hatası. Lütfen yetkilendirmeyi kontrol edin.';
          } else if (response.statusCode == 404) {
            errorMessage = 'Backend servisi bulunamadı. Lütfen bağlantınızı kontrol edin.';
          } else if (response.statusCode == 500 || response.statusCode == 502 || response.statusCode == 503) {
            errorMessage = 'Sunucu hatası. Lütfen daha sonra tekrar deneyin.';
          } else if (response.statusCode == 408 || response.statusCode == 504) {
            errorMessage = 'İstek zaman aşımına uğradı. Lütfen tekrar deneyin.';
          }
        }
        
        throw Exception(errorMessage);
      }
      throw StateError('Beklenmeyen yanıt durumu');
    } catch (e, stackTrace) {
      AppLogger.error('Dosya yükleme hatası', e, stackTrace);
      if (e is Exception) rethrow;
      final msg = e.toString().toLowerCase();
      if (msg.contains('unexpected end') || msg.contains('end of stream') || msg.contains('connection closed')) {
        throw Exception('Bağlantı beklenmedik şekilde kesildi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      }
      throw Exception('Dosya yükleme hatası: ${e.toString()}');
    }
  }

  /// Backend'in çalışıp çalışmadığını kontrol eder
  static Future<bool> checkBackendHealth() async {
    try {
      final baseUrl = await getBackendBaseUrl();
      // Health check için baseUrl'e /health ekle
      final healthUrl = baseUrl.endsWith('/') ? '${baseUrl}health' : '$baseUrl/health';
      final uri = Uri.parse(healthUrl);
      
      final request = http.Request('GET', uri);
      
      final response = await request.send().timeout(
        const Duration(seconds: AppConfig.healthCheckTimeoutSeconds),
      );
      
      final responseBody = await http.Response.fromStream(response).timeout(
        const Duration(seconds: AppConfig.healthCheckTimeoutSeconds),
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
      // Backend URL'ini al
      final baseUrl = await getBackendBaseUrl();
      
      // URL'i doğrudan oluştur (Firebase Functions formatı: baseUrl?fileId=...)
      final uri = Uri.parse('$baseUrl?fileId=$fileId');
      
      AppLogger.info('🔹 Backend download URL: $uri');
      AppLogger.info('🔹 File ID: $fileId');
      
      final request = http.Request('GET', uri);
      
      AppLogger.info('🔹 Backend isteği gönderiliyor...');
      final stopwatch = Stopwatch()..start();
      
      final response = await request.send().timeout(
        const Duration(seconds: AppConfig.uploadTimeoutSeconds),
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
            const Duration(seconds: AppConfig.uploadTimeoutSeconds * 2),
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

  /// Google Sheets linkini alır
  static Future<String?> getGoogleSheetsUrl() async {
    try {
      final baseUrl = await getBackendBaseUrl();
      // Firebase Cloud Functions için: baseUrl'e /sheets ekle
      final sheetsUrl = baseUrl.endsWith('/') ? '${baseUrl}sheets' : '$baseUrl/sheets';
      final uri = Uri.parse(sheetsUrl);

      final request = http.Request('GET', uri);

      final response = await request.send().timeout(
        const Duration(seconds: AppConfig.uploadTimeoutSeconds),
        onTimeout: () {
          throw Exception('Backend zaman aşımı. İnternet bağlantınızı kontrol edin.');
        },
      );

      final responseBody = await http.Response.fromStream(response).timeout(
        const Duration(seconds: AppConfig.uploadTimeoutSeconds),
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
    return createExcelFile(entries: entries, fileName: 'Tum Eklenenler.csv');
  }

  /// Excel'i kullanıcının kendi entry'leriyle oluşturur
  static Future<Map<String, dynamic>?> createMyEntriesExcel(
    List<Map<String, dynamic>> entries,
    String? ownerName,
  ) async {
    // Kullanıcı adını dosya adına ekle
    final fileName = ownerName != null && ownerName.isNotEmpty
        ? '$ownerName Eklediklerim.csv'
        : 'Eklediklerim.csv';
    return createExcelFile(entries: entries, fileName: fileName);
  }

  /// Excel'i ortak gelirleriyle oluşturur (sabit tablo)
  static Future<Map<String, dynamic>?> createIncomeEntriesExcel(
    List<Map<String, dynamic>> entries,
  ) async {
    return createExcelFile(entries: entries, fileName: 'Ortak Gelirleri.csv');
  }

  /// Excel'i vergiden düşülecek kayıtlarla oluşturur (sabit tablo)
  static Future<Map<String, dynamic>?> createTaxDeductibleEntriesExcel(
    List<Map<String, dynamic>> entries,
  ) async {
    return createExcelFile(entries: entries, fileName: 'Vergiden Düşülecekler.csv');
  }

  /// Excel'i tüm entry'lerle oluşturur
  static Future<Map<String, dynamic>?> createAllEntriesExcel(
    List<Map<String, dynamic>> entries,
  ) async {
    return createExcelFile(entries: entries, fileName: 'Tum Eklenenler.csv');
  }

  /// Excel'i sadece harcama (gider) kayıtlarıyla oluşturur
  static Future<Map<String, dynamic>?> createExpenseEntriesExcel(
    List<Map<String, dynamic>> entries,
  ) async {
    return createExcelFile(entries: entries, fileName: 'Harcamalar.csv');
  }

  /// Excel oluşturma yardımcı fonksiyonu — aktif kayıtları gönderir.
  static Future<Map<String, dynamic>?> createExcelFile({
    required List<Map<String, dynamic>> entries,
    required String fileName,
  }) async {
    try {
      // Backend URL'ini al
      final baseUrl = await getBackendBaseUrl();
      final uri = Uri.parse('$baseUrl?endpoint=init-sheets');

      // Log ekle
      AppLogger.info('📊 Excel isteği: $fileName, Aktif: ${entries.length}');

      final request = http.Request('POST', uri);
      request.headers['Content-Type'] = 'application/json';

      // Entry'leri formatla yardımcı fonksiyon
      List<Map<String, dynamic>> format(List<Map<String, dynamic>> list) {
        return list.map((entry) {
          return {
            'dateTime': entry['createdAt']?.toString() ?? DateTime.now().toIso8601String(),
            'notes': entry['notes'] ?? '',
            'ownerName': entry['ownerName'] ?? '',
            'amount': entry['amount']?.toDouble() ?? 0.0,
            'description': entry['description'] ?? '',
            'fileUrl': entry['fileUrl'] ?? '',
            'entryType': entry['entryType'] ?? 'expense',
            'category': entry['category'] ?? '',
          };
        }).toList();
      }

      final formattedEntries = format(entries);

      // sheetName: sabit dosya adı
      final sheetName = fileName.replaceAll('.csv', '').replaceAll(RegExp(r'_\d{4}-\d{2}-\d{2}'), '');
      final body = <String, dynamic>{
        'entries': formattedEntries,
        'sheetName': sheetName,
      };
      final driveToken = await DriveTokenService.getDriveAccessToken();
      if (driveToken != null) body['driveAccessToken'] = driveToken;
      request.body = jsonEncode(body);

      AppLogger.info('Excel oluşturma isteği: $uri');

      final response = await request.send().timeout(
        const Duration(seconds: AppConfig.uploadTimeoutSeconds * 2),
        onTimeout: () {
          throw Exception('Backend zaman aşımı');
        },
      );

      final responseBody = await http.Response.fromStream(response);
      final bodyStr = responseBody.body;

      if (response.statusCode == 200) {
        if (bodyStr.isEmpty) {
          throw Exception('Sunucu yanıtı boş. Bağlantıyı kontrol edip tekrar deneyin.');
        }
        try {
          final json = jsonDecode(bodyStr) as Map<String, dynamic>;
          final count = json['rowCount'] ?? 0;
          AppLogger.info('Excel oluşturuldu: ${json['url']} - $count kayıt yazıldı');
          return json;
        } on FormatException catch (e) {
          AppLogger.error('Excel yanıtı parse hatası', e);
          throw Exception('Sunucu yanıtı eksik veya bozuk. İnternet bağlantınızı kontrol edip tekrar deneyin.');
        }
      } else {
        AppLogger.error('Excel hata: ${response.statusCode} - $bodyStr');
        String errorMessage = 'Excel oluşturulamadı: ${response.statusCode}';
        if (bodyStr.isNotEmpty) {
          try {
            final errorJson = jsonDecode(bodyStr) as Map<String, dynamic>;
            if (errorJson['message'] != null) {
              errorMessage = errorJson['message'] as String;
            } else if (errorJson['error'] != null) {
              errorMessage = errorJson['error'] as String;
            }
            // 403: Erişim yok - requiredEmail varsa mesaja ekle
            if (response.statusCode == 403 && errorJson['requiredEmail'] != null) {
              final email = errorJson['requiredEmail'] as String;
              if (email.isNotEmpty && !errorMessage.contains(email)) {
                errorMessage = 'Tabloya erişim yok. Google Sheet\'te Paylaş → "$email" adresini düzenleyici ekleyin.';
              }
            }
          } catch (_) {
            // JSON parse edilemezse varsayılan mesaj kalır
          }
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      AppLogger.error('Excel oluşturma hatası', e);
      rethrow;
    }
  }

  /// Excel'i tüm entry'ler ve sabit giderlerle oluşturur (Ayarlar sayfası için)
  static Future<Map<String, dynamic>?> initializeGoogleSheetsWithAllData({
    required List<Map<String, dynamic>> entries,
    required List<Map<String, dynamic>> fixedExpenses,
    String sheetName = 'Tum Veriler',
  }) async {
    try {
      // Backend URL'ini al
      final baseUrl = await getBackendBaseUrl();
      final uri = Uri.parse('$baseUrl?endpoint=init-sheets');

      final request = http.Request('POST', uri);
      request.headers['Content-Type'] = 'application/json';

      // Entry'leri formatla yardımcı fonksiyon
      List<Map<String, dynamic>> formatEntries(List<Map<String, dynamic>> list) {
        return list.map((entry) {
          return {
            'dateTime': entry['createdAt']?.toString() ?? DateTime.now().toIso8601String(),
            'notes': entry['notes'] ?? '',
            'ownerName': entry['ownerName'] ?? '',
            'amount': entry['amount']?.toDouble() ?? 0.0,
            'description': entry['description'] ?? '',
            'fileUrl': entry['fileUrl'] ?? '',
            'entryType': entry['entryType'] ?? 'expense',
            'category': entry['category'] ?? '',
          };
        }).toList();
      }

      final formattedEntries = formatEntries(entries);

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

      final body = <String, dynamic>{
        'entries': formattedEntries,
        'fixedExpenses': formattedFixedExpenses,
        'sheetName': sheetName,
      };
      final driveToken = await DriveTokenService.getDriveAccessToken();
      if (driveToken != null) body['driveAccessToken'] = driveToken;
      request.body = jsonEncode(body);

      AppLogger.info('Excel (All Data) oluşturma isteği: $uri');

      final response = await request.send().timeout(
        const Duration(seconds: AppConfig.uploadTimeoutSeconds * 2),
        onTimeout: () {
          throw Exception('Backend zaman aşımı');
        },
      );

      final responseBody = await http.Response.fromStream(response);
      final bodyStr = responseBody.body;

      if (response.statusCode == 200) {
        if (bodyStr.isEmpty) {
          throw Exception('Sunucu yanıtı boş. Bağlantıyı kontrol edip tekrar deneyin.');
        }
        try {
          final json = jsonDecode(bodyStr) as Map<String, dynamic>;
          AppLogger.info('Excel (All Data) oluşturuldu: ${json['url']}');
          return json;
        } on FormatException catch (e) {
          AppLogger.error('Excel (All Data) yanıt parse hatası', e);
          throw Exception('Sunucu yanıtı eksik veya bozuk. İnternet bağlantınızı kontrol edip tekrar deneyin.');
        }
      } else {
        AppLogger.error('Excel hata: ${response.statusCode} - $bodyStr');
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
      // Backend URL'ini al
      final baseUrl = await getBackendBaseUrl();
      final uri = Uri.parse('$baseUrl?endpoint=init-sheets');

      final request = http.Request('POST', uri);
      request.headers['Content-Type'] = 'application/json';

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

      final body = <String, dynamic>{
        'fixedExpenses': formattedFixedExpenses,
        'sheetName': 'Sabit Giderler',
      };
      final driveToken = await DriveTokenService.getDriveAccessToken();
      if (driveToken != null) body['driveAccessToken'] = driveToken;
      request.body = jsonEncode(body);

      AppLogger.info('Excel (Fixed Expenses) oluşturma isteği: $uri');

      final response = await request.send().timeout(
        const Duration(seconds: AppConfig.uploadTimeoutSeconds * 2),
        onTimeout: () {
          throw Exception('Backend zaman aşımı');
        },
      );

      final responseBody = await http.Response.fromStream(response);
      final bodyStr = responseBody.body;

      if (response.statusCode == 200) {
        if (bodyStr.isEmpty) {
          throw Exception('Sunucu yanıtı boş. Bağlantıyı kontrol edip tekrar deneyin.');
        }
        try {
          final json = jsonDecode(bodyStr) as Map<String, dynamic>;
          AppLogger.info('Excel (Fixed Expenses) oluşturuldu: ${json['url']}');
          return json;
        } on FormatException catch (e) {
          AppLogger.error('Excel (Fixed Expenses) yanıt parse hatası', e);
          throw Exception('Sunucu yanıtı eksik veya bozuk. İnternet bağlantınızı kontrol edip tekrar deneyin.');
        }
      } else {
        AppLogger.error('Excel hata: ${response.statusCode} - $bodyStr');
        throw Exception('Excel oluşturulamadı: ${response.statusCode}');
      }
    } catch (e) {
      AppLogger.error('Excel oluşturma hatası', e);
      rethrow;
    }
  }

  /// Tüm Google Sheets dosyalarını arka planda önceden hazırlar (performans için)
  static Future<void> prewarmSheets(String ownerName) async {
    try {
      final baseUrl = await getBackendBaseUrl();
      // Eğer base URL boş ise (örn. hata varsa) çık
      if (baseUrl.isEmpty) return;
      
      final uri = Uri.parse('$baseUrl?endpoint=prewarm-sheets');
      
      AppLogger.info('🚀 Sheets ön hazırlık (Prewarm) başlatılıyor... Kişi: $ownerName');
      
      // Fire-and-forget yapmamız gerekebilir ama backend yanıtı hızlı olacağı için bekleyebiliriz
      // ya da timeout'u kısa tutabiliriz.
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'ownerName': ownerName}),
      ).timeout(const Duration(seconds: 10)); // 10 saniye bekle, olmazsa arka planda devam etsin

      if (response.statusCode == 200) {
        AppLogger.success('✅ Sheets ön hazırlık tamamlandı');
      } else {
        AppLogger.warning('⚠️ Sheets ön hazırlık uyarısı: ${response.statusCode}');
      }
    } catch (e) {
      // Prewarm hatası kullanıcıyı bloklamamalı, sadece logla
      AppLogger.info('ℹ️ Sheets ön hazırlık sessiz hata (önemsiz): $e');
    }
  }
}

