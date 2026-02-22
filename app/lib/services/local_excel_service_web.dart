/// Web platform implementation for LocalExcelService
/// Uses Blob and download link for CSV download
library;

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:convert';
import '../utils/app_logger.dart';

/// Save and open CSV on web platform
Future<void> saveAndOpenCSV(String csvContent, String fileName) async {
  try {
    AppLogger.info('📊 Web: CSV indiriliyor: $fileName');
    
    // UTF-8 BOM ekle
    const utf8Bom = '\uFEFF';
    final bytes = utf8.encode('$utf8Bom$csvContent');
    
    // Blob oluştur
    final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
    
    // Download link oluştur
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..style.display = 'none';
    
    // DOM'a ekle, tıkla ve kaldır
    html.document.body!.children.add(anchor);
    anchor.click();
    
    // Cleanup
    html.document.body!.children.remove(anchor);
    html.Url.revokeObjectUrl(url);
    
    AppLogger.success('✅ Web: CSV indirme başlatıldı: $fileName');
  } catch (e) {
    AppLogger.error('❌ Web: CSV indirme hatası', e);
    rethrow;
  }
}
