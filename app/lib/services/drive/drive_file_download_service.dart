/// Google Drive dosya indirme servisi
/// 3 katmanlı garantili indirme mekanizması
library;

import 'dart:typed_data';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:cross_file/cross_file.dart';
import 'drive_helper_io.dart' if (dart.library.html) 'drive_helper_web.dart' as platform_impl;
import '../../models/app_file_reference.dart';
import '../../utils/app_logger.dart';
import '../upload_service.dart';
import 'drive_url_builder.dart';

/// İndirme sonucu
class FileDownloadResult {
  final bool success;
  final XFile? localFile;
  final String? webViewerUrl;
  final String? errorMessage;

  const FileDownloadResult({
    required this.success,
    this.localFile,
    this.webViewerUrl,
    this.errorMessage,
  });

  factory FileDownloadResult.success(XFile file) {
    return FileDownloadResult(success: true, localFile: file);
  }

  factory FileDownloadResult.webViewer(String url) {
    return FileDownloadResult(success: false, webViewerUrl: url);
  }

  factory FileDownloadResult.failure(String? error) {
    return FileDownloadResult(success: false, errorMessage: error);
  }
}

/// Google Drive dosya indirme servisi
class DriveFileDownloadService {
  /// Dosyayı indir (3 katmanlı garantili sistem)
  static Future<FileDownloadResult> downloadFile(AppFileReference fileRef) async {
    AppLogger.info('📥 Dosya indirme başlatıldı: ${fileRef.name} (${fileRef.mimeType})');
    AppLogger.info('📥 Drive File ID: ${fileRef.driveFileId}');
    AppLogger.info('📥 File Type Category: ${fileRef.fileTypeCategory}');
    
    // File ID doğrulama
    if (fileRef.driveFileId.isEmpty) {
      AppLogger.error('Drive File ID boş! Dosya indirilemez.');
      final viewerUrl = DriveUrlBuilder.buildWebViewerUrl(fileRef.driveFileId);
      return FileDownloadResult.webViewer(viewerUrl);
    }
    
    // KATMAN 1: Backend üzerinden indirme (3 deneme)
    AppLogger.info('🔹 KATMAN 1: Backend indirme deneniyor...');
    final backendResult = await _tryBackendDownload(fileRef);
    if (backendResult.success && backendResult.localFile != null) {
      AppLogger.success('✅ Backend üzerinden dosya başarıyla indirildi (${backendResult.localFile!.path})');
      return backendResult;
    }
    
    AppLogger.warning('❌ Backend indirme başarısız, direkt URL\'lere geçiliyor...');
    
    // KATMAN 2: Direkt Google Drive URL'leri (her URL için 3 deneme)
    AppLogger.info('🔹 KATMAN 2: Direkt Google Drive URL\'leri deneniyor...');
    final directResult = await _tryDirectDownload(fileRef);
    if (directResult.success && directResult.localFile != null) {
      AppLogger.success('✅ Direkt URL ile dosya başarıyla indirildi (${directResult.localFile!.path})');
      return directResult;
    }
    
    AppLogger.warning('❌ Tüm indirme yöntemleri başarısız, web viewer kullanılacak');
    
    // KATMAN 3: Web viewer (son çare)
    final viewerUrl = DriveUrlBuilder.buildWebViewerUrl(fileRef.driveFileId);
    AppLogger.info('🔹 KATMAN 3: Web viewer URL oluşturuldu: $viewerUrl');
    return FileDownloadResult.webViewer(viewerUrl);
  }

  /// Backend üzerinden indirme (KATMAN 1)
  static Future<FileDownloadResult> _tryBackendDownload(AppFileReference fileRef) async {
    AppLogger.info('🔹 KATMAN 1: Backend indirme başlatılıyor...');
    AppLogger.info('   → File ID: ${fileRef.driveFileId}');
    AppLogger.info('   → File Type: ${fileRef.fileTypeCategory}');
    AppLogger.info('   → MIME Type: ${fileRef.mimeType}');
    
    // Backend URL kontrolü
    try {
      // getBackendBaseUrl top-level fonksiyon, upload_service.dart'tan import edilmeli
      // Şimdilik direkt downloadFileFromDrive çağrısı yapıyoruz, o zaten backend URL'i kontrol ediyor
      AppLogger.info('   → Backend URL kontrolü downloadFileFromDrive içinde yapılacak');
    } catch (e) {
      AppLogger.warning('   ❌ Backend URL kontrolü hatası: $e');
      return FileDownloadResult.failure('Backend URL kontrolü hatası: $e');
    }
    
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        AppLogger.info('   → Deneme $attempt/3 başlatılıyor...');
        
        final fileBytes = await UploadService.downloadFileFromDrive(fileRef.driveFileId).timeout(
          const Duration(seconds: 20), // 20 saniye timeout (daha hızlı)
          onTimeout: () {
            AppLogger.warning('   ❌ Backend indirme zaman aşımı (deneme $attempt/3, 20 saniye)');
            throw TimeoutException('Backend indirme zaman aşımı (deneme $attempt)');
          },
        );
        
        if (fileBytes.isNotEmpty) {
          AppLogger.info('   → Backend yanıt alındı: ${fileBytes.length} bytes');
          
          // Dosyayı kaydet
          final file = await _saveFile(fileBytes, fileRef);
          if (file != null) {
            AppLogger.success('   ✅ Backend üzerinden dosya indirildi ve kaydedildi (${fileBytes.length} bytes)');
            AppLogger.info('   → Dosya yolu: ${file.path}');
            return FileDownloadResult.success(file);
          } else {
            AppLogger.warning('   ❌ Dosya kaydedilemedi (null döndü)');
          }
        } else {
          AppLogger.warning('   ❌ Backend boş yanıt döndü (null veya empty)');
        }
      } catch (e, stackTrace) {
        AppLogger.warning('   ❌ Backend indirme hatası (deneme $attempt/3): $e');
        AppLogger.warning('   ❌ Stack trace: $stackTrace');
        if (attempt < 3) {
          final delayMs = 1000 * attempt;
          AppLogger.info('   → ${delayMs}ms bekleniyor, sonra tekrar deneniyor...');
          await Future.delayed(Duration(milliseconds: delayMs));
          continue;
        } else {
          AppLogger.error('   ❌ Tüm backend denemeleri başarısız');
        }
      }
    }
    
    return FileDownloadResult.failure('Backend indirme başarısız (3 deneme)');
  }

  /// Direkt Google Drive URL'leri ile indirme (KATMAN 2)
  static Future<FileDownloadResult> _tryDirectDownload(AppFileReference fileRef) async {
    final urls = DriveUrlBuilder.buildCandidateUrls(fileRef);
    AppLogger.info('🔹 Toplam ${urls.length} direkt URL deneniyor...');
    
    for (int urlIndex = 0; urlIndex < urls.length; urlIndex++) {
      final url = urls[urlIndex];
      AppLogger.info('🔹 URL ${urlIndex + 1}/${urls.length}: $url');
      
      for (int attempt = 1; attempt <= 3; attempt++) {
        try {
          AppLogger.info('   → Deneme $attempt/3 başlatılıyor...');
          
          final response = await http.get(
            Uri.parse(url),
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
              'Accept': '*/*',
              'Accept-Language': 'en-US,en;q=0.9',
            },
          ).timeout(
            Duration(seconds: 30 + (attempt * 5)), // 30, 35, 40 saniye (daha hızlı)
            onTimeout: () {
              AppLogger.warning('   ❌ Zaman aşımı (deneme $attempt/3)');
              throw TimeoutException('İndirme zaman aşımı (deneme $attempt)');
            },
          );
          
          AppLogger.info('   → Yanıt alındı: status=${response.statusCode}, size=${response.bodyBytes.length} bytes');
          
          // Güvenlik kontrolleri
          if (!_isValidFileResponse(response, fileRef)) {
            AppLogger.warning('   ❌ Geçersiz yanıt (status: ${response.statusCode}, size: ${response.bodyBytes.length})');
            if (attempt < 3) {
              await Future.delayed(Duration(milliseconds: 1000 * attempt));
              continue;
            }
            continue; // Sonraki URL'e geç
          }
          
          // Dosyayı kaydet
          final file = await _saveFile(response.bodyBytes, fileRef);
          if (file != null) {
            AppLogger.success('Direkt URL ile dosya indirildi ve kaydedildi (${response.bodyBytes.length} bytes)');
            return FileDownloadResult.success(file);
          }
        } catch (e) {
          AppLogger.warning('Direkt URL indirme hatası (deneme $attempt/3): $e');
          if (attempt < 3) {
            await Future.delayed(Duration(milliseconds: 1000 * attempt));
            continue;
          }
        }
      }
    }
    
    return FileDownloadResult.failure('Tüm direkt URL\'ler başarısız');
  }

  /// HTTP yanıtının geçerli dosya olup olmadığını kontrol et
  static bool _isValidFileResponse(http.Response response, AppFileReference fileRef) {
    // Status code kontrolü
    if (response.statusCode != 200) {
      return false;
    }
    
    // Boş kontrolü
    if (response.bodyBytes.isEmpty) {
      return false;
    }
    
    final contentType = response.headers['content-type'] ?? '';
    
    // HTML kontrolü
    final isHtml = contentType.contains('text/html') || 
                  (response.bodyBytes.length < 1000 &&
                  String.fromCharCodes(response.bodyBytes.take(500)).toLowerCase().contains('<html'));
    
    if (isHtml) {
      AppLogger.warning('Yanıt HTML içeriyor (content-type: $contentType)');
      return false;
    }
    
    // Dosya boyutu kontrolü
    final minFileSize = fileRef.fileTypeCategory == 'image' ? 100 : 500;
    if (response.bodyBytes.length < minFileSize) {
      AppLogger.warning('Dosya çok küçük (${response.bodyBytes.length} bytes, minimum: $minFileSize)');
      return false;
    }
    
    // Content-type kontrolü (opsiyonel - bazı durumlarda Google Drive doğru type döndürmeyebilir)
    final expectedTypes = _getExpectedMimeTypes(fileRef);
    if (contentType.isNotEmpty && expectedTypes.isNotEmpty) {
      final matches = expectedTypes.any((type) => contentType.contains(type));
      if (!matches) {
        AppLogger.warning('Content-type uyuşmuyor (beklenen: $expectedTypes, gelen: $contentType)');
        // Yine de devam et - bazı durumlarda Google Drive yanlış type döndürebilir
      }
    }
    
    return true;
  }

  /// Beklenen MIME type'ları döndür
  static List<String> _getExpectedMimeTypes(AppFileReference fileRef) {
    switch (fileRef.fileTypeCategory) {
      case 'pdf':
        return ['application/pdf'];
      case 'image':
        return ['image/jpeg', 'image/jpg', 'image/png', 'image/gif', 'image/webp'];
      case 'excel':
        return [
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          'application/vnd.ms-excel',
          'text/csv',
        ];
      default:
        return [];
    }
  }

  /// Dosyayı geçici dizine kaydet
  /// Dosyayı platforma uygun şekilde kaydet
  static Future<XFile?> _saveFile(Uint8List bytes, AppFileReference fileRef) async {
    final sanitizedName = _sanitizeFileName(fileRef.name);
    final fileName = sanitizedName.isNotEmpty 
        ? sanitizedName 
        : 'file_${fileRef.driveFileId}.${fileRef.fileExtension}';
    
    return platform_impl.saveFileToTemp(bytes, fileName);
  }

  /// Dosya adını temizle (geçersiz karakterleri kaldır)
  static String _sanitizeFileName(String fileName) {
    // Windows/Android için geçersiz karakterler
    final invalidChars = RegExp(r'[<>:"/\\|?*\x00-\x1f]');
    return fileName.replaceAll(invalidChars, '_').trim();
  }
}

