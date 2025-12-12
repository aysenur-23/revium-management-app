/**
 * Google Drive URL builder
 * Dosya tipine göre indirme URL'lerini oluşturur
 */

import 'dart:typed_data';
import '../upload_service.dart';
import '../../models/app_file_reference.dart';
import '../../utils/app_logger.dart';

class DriveUrlBuilder {
  /// Dosya tipine göre indirme URL'lerini oluştur (öncelik sırasına göre)
  static List<String> buildCandidateUrls(AppFileReference fileRef) {
    final fileId = fileRef.driveFileId;
    final category = fileRef.fileTypeCategory;
    
    final List<String> urls = [];
    
    switch (category) {
      case 'pdf':
        // PDF için 4 URL formatı
        urls.addAll([
          'https://drive.google.com/uc?export=download&id=$fileId&confirm=t',
          'https://drive.google.com/uc?export=download&id=$fileId',
          'https://drive.google.com/uc?export=view&id=$fileId',
          'https://drive.google.com/file/d/$fileId/view?usp=sharing',
        ]);
        break;
        
      case 'image':
        // Resim için 6 URL formatı
        urls.addAll([
          'https://drive.google.com/uc?export=download&id=$fileId&confirm=t',
          'https://drive.google.com/uc?export=download&id=$fileId',
          'https://drive.google.com/uc?export=view&id=$fileId',
          'https://drive.google.com/thumbnail?id=$fileId&sz=w4096',
          'https://drive.google.com/thumbnail?id=$fileId&sz=w1920',
          'https://drive.google.com/thumbnail?id=$fileId&sz=w800',
        ]);
        break;
        
      case 'excel':
        // Excel için 4 URL formatı
        urls.addAll([
          'https://drive.google.com/uc?export=download&id=$fileId&confirm=t',
          'https://drive.google.com/uc?export=download&id=$fileId',
          'https://drive.google.com/uc?export=download&id=$fileId&format=xlsx',
          'https://drive.google.com/file/d/$fileId/view?usp=sharing',
        ]);
        break;
        
      default:
        // Diğer dosya tipleri için 3 URL formatı
        urls.addAll([
          'https://drive.google.com/uc?export=download&id=$fileId&confirm=t',
          'https://drive.google.com/uc?export=download&id=$fileId',
          'https://drive.google.com/file/d/$fileId/view?usp=sharing',
        ]);
    }
    
    AppLogger.debug('${urls.length} adet URL formatı oluşturuldu (tip: $category)');
    return urls;
  }

  /// Web viewer URL'ini oluştur
  static String buildWebViewerUrl(String fileId) {
    return 'https://drive.google.com/file/d/$fileId/view?usp=drivesdk';
  }

  /// Alternatif viewer URL'lerini oluştur
  static List<String> buildViewerUrls(String fileId) {
    return [
      'https://drive.google.com/file/d/$fileId/view',
      'https://drive.google.com/file/d/$fileId/preview',
      'https://drive.google.com/open?id=$fileId',
      'https://drive.google.com/file/d/$fileId/view?usp=sharing',
      'https://drive.google.com/file/d/$fileId/view?usp=drivesdk',
    ];
  }
}

