/// IO platform implementation for LocalExcelService
/// Uses path_provider and open_file for mobile/desktop
library;

import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/app_logger.dart';

/// Save and open CSV on IO platforms (mobile/desktop)
Future<void> saveAndOpenCSV(String csvContent, String fileName) async {
  try {
    AppLogger.info('📊 IO: CSV oluşturuluyor: $fileName');
    
    // Geçici dosyaya kaydet (UTF-8 BOM ile Türkçe karakter desteği için)
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName');
    
    // UTF-8 BOM ekle (Excel'in Türkçe karakterleri doğru okuması için)
    const utf8Bom = '\uFEFF';
    await file.writeAsString('$utf8Bom$csvContent', encoding: utf8);
    
    AppLogger.info('CSV dosyası oluşturuldu: ${file.path}');
    
    // Dosya varlığını kontrol et
    if (!await file.exists()) {
      AppLogger.error('❌ Dosya oluşturulamadı: ${file.path}');
      throw Exception('Dosya oluşturulamadı: ${file.path}');
    }
    
    AppLogger.info('Dosya boyutu: ${await file.length()} bytes');
    
    // Dosyayı aç
    try {
      final result = await OpenFilex.open(file.path, type: 'text/csv');
      if (result.type == ResultType.done) {
        AppLogger.success('✅ CSV başarıyla açıldı');
      } else {
        AppLogger.warning('CSV açılamadı: ${result.message}');
        // Fallback: type belirtmeden dene
        final result2 = await OpenFilex.open(file.path);
        if (result2.type != ResultType.done) {
          // Fallback: share_plus ile paylaş
          await Share.shareXFiles([XFile(file.path)], text: 'Harcama Takibi CSV');
          AppLogger.info('CSV paylaşım menüsü açıldı');
        }
      }
    } catch (openError) {
      AppLogger.error('OpenFilex.open hatası', openError);
      // Fallback: share_plus ile paylaş
      await Share.shareXFiles([XFile(file.path)], text: 'Harcama Takibi CSV');
      AppLogger.info('CSV paylaşım menüsü açıldı (hata sonrası)');
    }
  } catch (e) {
    AppLogger.error('❌ CSV oluşturma hatası', e);
    rethrow;
  }
}
