/**
 * Lokal Excel/CSV Servisi
 * Backend'e bağımlı olmadan lokal CSV oluşturur ve açar
 */

import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import 'package:intl/intl.dart';
import '../models/expense_entry.dart';
import '../models/fixed_expense.dart';
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
      
      // Geçici dosyaya kaydet (UTF-8 BOM ile Türkçe karakter desteği için)
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$fileName');
      // UTF-8 BOM ekle (Excel'in Türkçe karakterleri doğru okuması için)
      final utf8Bom = '\uFEFF';
      await file.writeAsString('$utf8Bom$csvContent', encoding: utf8);
      
      AppLogger.info('CSV dosyası oluşturuldu: ${file.path}');
      
      // Dosya varlığını kontrol et
      if (!await file.exists()) {
        AppLogger.error('❌ Dosya oluşturulamadı: ${file.path}');
        throw Exception('Dosya oluşturulamadı: ${file.path}');
      }
      
      AppLogger.info('Dosya boyutu: ${await file.length()} bytes');
      
      // Dosyayı aç (önizleme ile)
      try {
        final result = await OpenFile.open(file.path, type: 'text/csv');
        if (result.type == ResultType.done) {
          AppLogger.success('✅ CSV başarıyla açıldı');
        } else {
          AppLogger.warning('CSV açılamadı: ${result.message}');
          // Fallback 1: type belirtmeden dene
          try {
            final result2 = await OpenFile.open(file.path);
            if (result2.type == ResultType.done) {
              AppLogger.success('✅ CSV type olmadan açıldı');
            } else {
              AppLogger.warning('CSV hala açılamadı: ${result2.message}');
              // Fallback 2: share_plus ile paylaş
              await Share.shareXFiles([XFile(file.path)], text: 'Harcama Takibi CSV');
              AppLogger.info('CSV paylaşım menüsü açıldı');
            }
          } catch (e2) {
            AppLogger.error('CSV açma fallback hatası', e2);
            // Son çare: share_plus ile paylaş
            try {
              await Share.shareXFiles([XFile(file.path)], text: 'Harcama Takibi CSV');
              AppLogger.info('CSV paylaşım menüsü açıldı (son çare)');
            } catch (e3) {
              AppLogger.error('CSV paylaşım hatası', e3);
              throw Exception('Dosya açılamadı ve paylaşılamadı: ${e3.toString()}');
            }
          }
        }
      } catch (openError) {
        AppLogger.error('OpenFile.open hatası', openError);
        // Son çare: share_plus ile paylaş
        try {
          await Share.shareXFiles([XFile(file.path)], text: 'Harcama Takibi CSV');
          AppLogger.info('CSV paylaşım menüsü açıldı (hata sonrası)');
        } catch (shareError) {
          AppLogger.error('CSV paylaşım hatası', shareError);
          throw Exception('Dosya açılamadı: ${openError.toString()}');
        }
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
      
      // Geçici dosyaya kaydet (UTF-8 BOM ile Türkçe karakter desteği için)
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$fileName');
      // UTF-8 BOM ekle (Excel'in Türkçe karakterleri doğru okuması için)
      final utf8Bom = '\uFEFF';
      await file.writeAsString('$utf8Bom$csvContent', encoding: utf8);
      
      AppLogger.info('CSV dosyası oluşturuldu: ${file.path}');
      
      // Dosya varlığını kontrol et
      if (!await file.exists()) {
        AppLogger.error('❌ Dosya oluşturulamadı: ${file.path}');
        throw Exception('Dosya oluşturulamadı: ${file.path}');
      }
      
      AppLogger.info('Dosya boyutu: ${await file.length()} bytes');
      
      // Dosyayı aç (önizleme ile)
      try {
        final result = await OpenFile.open(file.path, type: 'text/csv');
        if (result.type == ResultType.done) {
          AppLogger.success('✅ CSV başarıyla açıldı');
        } else {
          AppLogger.warning('CSV açılamadı: ${result.message}');
          // Fallback 1: type belirtmeden dene
          try {
            final result2 = await OpenFile.open(file.path);
            if (result2.type == ResultType.done) {
              AppLogger.success('✅ CSV type olmadan açıldı');
            } else {
              AppLogger.warning('CSV hala açılamadı: ${result2.message}');
              // Fallback 2: share_plus ile paylaş
              await Share.shareXFiles([XFile(file.path)], text: 'Harcama Takibi CSV');
              AppLogger.info('CSV paylaşım menüsü açıldı');
            }
          } catch (e2) {
            AppLogger.error('CSV açma fallback hatası', e2);
            // Son çare: share_plus ile paylaş
            try {
              await Share.shareXFiles([XFile(file.path)], text: 'Harcama Takibi CSV');
              AppLogger.info('CSV paylaşım menüsü açıldı (son çare)');
            } catch (e3) {
              AppLogger.error('CSV paylaşım hatası', e3);
              throw Exception('Dosya açılamadı ve paylaşılamadı: ${e3.toString()}');
            }
          }
        }
      } catch (openError) {
        AppLogger.error('OpenFile.open hatası', openError);
        // Son çare: share_plus ile paylaş
        try {
          await Share.shareXFiles([XFile(file.path)], text: 'Harcama Takibi CSV');
          AppLogger.info('CSV paylaşım menüsü açıldı (hata sonrası)');
        } catch (shareError) {
          AppLogger.error('CSV paylaşım hatası', shareError);
          throw Exception('Dosya açılamadı: ${openError.toString()}');
        }
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
  
  /// FixedExpense listesinden CSV oluştur ve aç
  static Future<void> createAndShareCSVFromFixedExpenses({
    required List<FixedExpense> expenses,
    required String fileName,
  }) async {
    try {
      AppLogger.info('📊 Sabit Giderler CSV oluşturuluyor: $fileName');
      
      if (expenses.isEmpty) {
        AppLogger.warning('Sabit gider listesi boş!');
        return;
      }
      
      // CSV içeriği oluştur
      final csvContent = _generateCSVFromFixedExpenses(expenses);
      
      // Geçici dosyaya kaydet (UTF-8 BOM ile Türkçe karakter desteği için)
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$fileName');
      // UTF-8 BOM ekle (Excel'in Türkçe karakterleri doğru okuması için)
      final utf8Bom = '\uFEFF';
      await file.writeAsString('$utf8Bom$csvContent', encoding: utf8);
      
      AppLogger.info('CSV dosyası oluşturuldu: ${file.path}');
      
      // Dosya varlığını kontrol et
      if (!await file.exists()) {
        AppLogger.error('❌ Dosya oluşturulamadı: ${file.path}');
        throw Exception('Dosya oluşturulamadı: ${file.path}');
      }
      
      AppLogger.info('Dosya boyutu: ${await file.length()} bytes');
      
      // Dosyayı aç (önizleme ile)
      try {
        final result = await OpenFile.open(file.path, type: 'text/csv');
        if (result.type == ResultType.done) {
          AppLogger.success('✅ CSV başarıyla açıldı');
        } else {
          AppLogger.warning('CSV açılamadı: ${result.message}');
          // Fallback 1: type belirtmeden dene
          try {
            final result2 = await OpenFile.open(file.path);
            if (result2.type == ResultType.done) {
              AppLogger.success('✅ CSV type olmadan açıldı');
            } else {
              AppLogger.warning('CSV hala açılamadı: ${result2.message}');
              // Fallback 2: share_plus ile paylaş
              await Share.shareXFiles([XFile(file.path)], text: 'Sabit Giderler CSV');
              AppLogger.info('CSV paylaşım menüsü açıldı');
            }
          } catch (e2) {
            AppLogger.error('CSV açma fallback hatası', e2);
            // Son çare: share_plus ile paylaş
            try {
              await Share.shareXFiles([XFile(file.path)], text: 'Sabit Giderler CSV');
              AppLogger.info('CSV paylaşım menüsü açıldı (son çare)');
            } catch (e3) {
              AppLogger.error('CSV paylaşım hatası', e3);
              throw Exception('Dosya açılamadı ve paylaşılamadı: ${e3.toString()}');
            }
          }
        }
      } catch (openError) {
        AppLogger.error('OpenFile.open hatası', openError);
        // Son çare: share_plus ile paylaş
        try {
          await Share.shareXFiles([XFile(file.path)], text: 'Sabit Giderler CSV');
          AppLogger.info('CSV paylaşım menüsü açıldı (hata sonrası)');
        } catch (shareError) {
          AppLogger.error('CSV paylaşım hatası', shareError);
          throw Exception('Dosya açılamadı: ${openError.toString()}');
        }
      }
    } catch (e) {
      AppLogger.error('❌ CSV oluşturma hatası', e);
      rethrow;
    }
  }

  /// FixedExpense listesinden CSV string oluştur
  static String _generateCSVFromFixedExpenses(List<FixedExpense> expenses) {
    final buffer = StringBuffer();
    
    // Header
    buffer.writeln('Açıklama,Tutar (₺),Kategori,Kaynak,Tekrarlama,Durum,Notlar');
    
    // Data rows
    for (final expense in expenses) {
      final description = _escapeCSV(expense.description);
      final amount = expense.amount.toStringAsFixed(2);
      final category = _escapeCSV(expense.category ?? '');
      final ownerName = _escapeCSV(expense.ownerName);
      final recurrence = expense.recurrence == 'monthly' ? 'Aylık' 
          : expense.recurrence == 'yearly' ? 'Yıllık'
          : expense.recurrence == 'one-time' ? 'Tek Seferlik'
          : expense.recurrence ?? '';
      final status = expense.isActive ? 'Aktif' : 'Pasif';
      final notes = _escapeCSV(expense.notes ?? '');
      
      buffer.writeln('$description,$amount,$category,$ownerName,$recurrence,$status,$notes');
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

