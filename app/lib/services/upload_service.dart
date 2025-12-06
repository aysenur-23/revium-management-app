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

  // Production Backend URL - Railway.app
  // Railway'e deploy ettikten sonra domain'inizi buraya yazın
  // Örnek: https://expense-tracker-production.up.railway.app
  // NOT: Railway deploy sonrası domain'i buraya ekleyin
  // VEYA Settings ekranından kullanıcılar kendi backend URL'lerini girebilir
  const String productionBackendUrl = ''; // Railway domain'inizi buraya ekleyin
  
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

  UploadResult({
    required this.fileId,
    required this.fileUrl,
  });

  factory UploadResult.fromJson(Map<String, dynamic> json) {
    return UploadResult(
      fileId: json['fileId'] as String,
      fileUrl: json['fileUrl'] as String,
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
  }) async {
    try {
      if (!kIsWeb && file == null) {
        throw Exception('Mobil platformda dosya (File) gerekli.');
      }
      if (kIsWeb && (fileBytes == null || fileName == null)) {
        throw Exception('Web platformunda dosya baytları ve dosya adı gerekli.');
      }

      final baseUrl = await getBackendBaseUrl();
      final uri = Uri.parse('$baseUrl/upload');
      final request = http.MultipartRequest('POST', uri);

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

      // ownerId'yi ekle
      request.fields['ownerId'] = ownerId;

      // İsteği gönder (timeout ile)
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Dosya yükleme zaman aşımı. İnternet bağlantınızı kontrol edin.');
        },
      );
      final response = await http.Response.fromStream(streamedResponse).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Yanıt alma zaman aşımı. Lütfen tekrar deneyin.');
        },
      );

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body) as Map<String, dynamic>;
        return UploadResult.fromJson(jsonResponse);
      } else {
        final errorBody = response.body;
        throw Exception(
            'Upload başarısız: ${response.statusCode} - $errorBody');
      }
    } catch (e) {
      throw Exception('Dosya yükleme hatası: ${e.toString()}');
    }
  }

  /// Backend'in çalışıp çalışmadığını kontrol eder
  static Future<bool> checkBackendHealth() async {
    try {
      final baseUrl = await getBackendBaseUrl();
      final uri = Uri.parse('$baseUrl/health');
      final response = await http.get(uri).timeout(
        const Duration(seconds: 5),
      );

      return response.statusCode == 200;
    } catch (e) {
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
}

