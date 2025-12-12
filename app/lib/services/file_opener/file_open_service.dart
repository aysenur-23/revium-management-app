/**
 * Dosya açma servisi
 * Doğrudan Google Drive web viewer ile açar (backend'e bağımlı değil)
 */

import 'package:url_launcher/url_launcher.dart';
import '../../models/app_file_reference.dart';
import '../../utils/app_logger.dart';

/// Dosya açma servisi
class FileOpenService {
  /// Dosyayı Google Drive'da aç (doğrudan, backend'siz)
  static Future<void> openOrDownloadAndOpen(AppFileReference fileRef) async {
    AppLogger.info('📂 Dosya açılıyor: ${fileRef.name}');
    AppLogger.info('📂 Drive File ID: ${fileRef.driveFileId}');
    
    // File ID'yi temizle (baştaki ve sondaki slash'ları kaldır)
    final cleanFileId = fileRef.driveFileId.replaceAll(RegExp(r'^/+|/+$'), '').trim();
    
    if (cleanFileId.isEmpty) {
      AppLogger.error('❌ Drive File ID boş!');
      return;
    }
    
    // Doğrudan Google Drive web viewer linkini aç
    final viewUrl = 'https://drive.google.com/file/d/$cleanFileId/view';
    AppLogger.info('🌐 Google Drive linki açılıyor: $viewUrl');
    
    try {
      final uri = Uri.parse(viewUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        AppLogger.success('✅ Dosya Google Drive\'da açıldı');
      } else {
        AppLogger.error('❌ URL açılamıyor');
        // Alternatif link dene
        final altUrl = 'https://drive.google.com/open?id=${fileRef.driveFileId}';
        final altUri = Uri.parse(altUrl);
        if (await canLaunchUrl(altUri)) {
          await launchUrl(altUri, mode: LaunchMode.externalApplication);
          AppLogger.success('✅ Dosya alternatif link ile açıldı');
        }
      }
    } catch (e) {
      AppLogger.error('❌ Dosya açma hatası', e);
    }
  }
  
  /// Dosya URL'sinden doğrudan aç (fileRef olmadan)
  static Future<void> openDriveFile(String fileId) async {
    if (fileId.isEmpty) {
      AppLogger.error('❌ File ID boş!');
      return;
    }
    
    final viewUrl = 'https://drive.google.com/file/d/$fileId/view';
    AppLogger.info('🌐 Google Drive linki açılıyor: $viewUrl');
    
    try {
      final uri = Uri.parse(viewUrl);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      AppLogger.success('✅ Dosya açıldı');
    } catch (e) {
      AppLogger.error('❌ Dosya açma hatası', e);
    }
  }
  
  /// URL'den doğrudan aç
  static Future<void> openUrl(String url) async {
    if (url.isEmpty) {
      AppLogger.error('❌ URL boş!');
      return;
    }
    
    AppLogger.info('🌐 URL açılıyor: $url');
    
    try {
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      AppLogger.success('✅ URL açıldı');
    } catch (e) {
      AppLogger.error('❌ URL açma hatası', e);
    }
  }
}
