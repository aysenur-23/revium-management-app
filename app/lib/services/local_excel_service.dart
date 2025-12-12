/**
 * Lokal Excel/CSV Servisi
 * Backend'e bağımlı olmadan lokal CSV oluşturur ve açar
 */

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:intl/intl.dart';
import '../models/expense_entry.dart';
import '../utils/app_logger.dart';

class LocalExcelService {
  /// Entry listesinden CSV oluştur ve aç
  static Future<void> createAndShareCSV({
    required List<ExpenseEntry> entries,
    required String fileName,
  }) async {
    try {
      AppLogger.info('📊 Lokal CSV oluşturuluyor: $fileName');
      
      if (entries.isEmpty) {
        AppLogger.warning('Entry listesi boş!');
        return;
      }
      
      // CSV içeriği oluştur
      final csvContent = _generateCSV(entries);
      
      // Geçici dosyaya kaydet
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsString(csvContent);
      
      AppLogger.info('CSV dosyası oluşturuldu: ${file.path}');
      
      // Dosyayı aç (önizleme ile)
      final result = await OpenFile.open(file.path, type: 'text/csv');
      if (result.type == ResultType.done) {
        AppLogger.success('✅ CSV başarıyla açıldı');
      } else {
        AppLogger.warning('CSV açılamadı: ${result.message}');
        // Fallback: type belirtmeden dene
        await OpenFile.open(file.path);
      }
    } catch (e) {
      AppLogger.error('❌ CSV oluşturma hatası', e);
      rethrow;
    }
  }
  
  /// Map listesinden CSV oluştur ve aç
  static Future<void> createAndShareCSVFromMap({
    required List<Map<String, dynamic>> entries,
    required String fileName,
  }) async {
    try {
      AppLogger.info('📊 Lokal CSV oluşturuluyor (Map): $fileName');
      
      if (entries.isEmpty) {
        AppLogger.warning('Entry listesi boş!');
        return;
      }
      
      // CSV içeriği oluştur
      final csvContent = _generateCSVFromMap(entries);
      
      // Geçici dosyaya kaydet
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsString(csvContent);
      
      AppLogger.info('CSV dosyası oluşturuldu: ${file.path}');
      
      // Dosyayı aç (önizleme ile)
      final result = await OpenFile.open(file.path, type: 'text/csv');
      if (result.type == ResultType.done) {
        AppLogger.success('✅ CSV başarıyla açıldı');
      } else {
        AppLogger.warning('CSV açılamadı: ${result.message}');
        await OpenFile.open(file.path);
      }
    } catch (e) {
      AppLogger.error('❌ CSV oluşturma hatası', e);
      rethrow;
    }
  }
  
  /// ExpenseEntry listesinden CSV string oluştur
  static String _generateCSV(List<ExpenseEntry> entries) {
    final buffer = StringBuffer();
    final dateFormat = DateFormat('dd.MM.yyyy HH:mm');
    
    // Header
    buffer.writeln('Tarih,Açıklama,Tutar (₺),Kişi,Dosya Tipi,Notlar');
    
    // Data rows
    for (final entry in entries) {
      final date = entry.createdAt != null 
          ? dateFormat.format(entry.createdAt!) 
          : '';
      final description = _escapeCSV(entry.description);
      final amount = entry.amount.toStringAsFixed(2);
      final ownerName = _escapeCSV(entry.ownerName);
      final fileType = entry.fileType;
      final notes = _escapeCSV(entry.notes ?? '');
      
      buffer.writeln('$date,$description,$amount,$ownerName,$fileType,$notes');
    }
    
    return buffer.toString();
  }
  
  /// Map listesinden CSV string oluştur
  static String _generateCSVFromMap(List<Map<String, dynamic>> entries) {
    final buffer = StringBuffer();
    final dateFormat = DateFormat('dd.MM.yyyy HH:mm');
    
    // Header
    buffer.writeln('Tarih,Açıklama,Tutar (₺),Kişi,Notlar,Dosya Linki');
    
    // Data rows
    for (final entry in entries) {
      String date = '';
      if (entry['createdAt'] != null) {
        try {
          final dateTime = DateTime.parse(entry['createdAt'].toString());
          date = dateFormat.format(dateTime);
        } catch (_) {
          date = entry['createdAt'].toString();
        }
      }
      
      final description = _escapeCSV(entry['description']?.toString() ?? '');
      final amount = (entry['amount'] as num?)?.toStringAsFixed(2) ?? '0.00';
      final ownerName = _escapeCSV(entry['ownerName']?.toString() ?? '');
      final notes = _escapeCSV(entry['notes']?.toString() ?? '');
      final fileUrl = entry['fileUrl']?.toString() ?? '';
      
      buffer.writeln('$date,$description,$amount,$ownerName,$notes,$fileUrl');
    }
    
    return buffer.toString();
  }
  
  /// CSV için özel karakterleri escape et
  static String _escapeCSV(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}

