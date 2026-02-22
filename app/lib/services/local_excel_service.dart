/// Lokal Excel/CSV Servisi
/// Backend'e bağımlı olmadan lokal CSV oluşturur ve açar
/// Web platformunda CSV indirme linki oluşturur
library;

import 'package:intl/intl.dart';
import '../models/expense_entry.dart';
import '../models/fixed_expense.dart';
import '../utils/app_logger.dart';

// Platform-specific imports
import 'local_excel_service_io.dart' if (dart.library.html) 'local_excel_service_web.dart' as platform_impl;

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
      
      // Platform-specific implementation
      await platform_impl.saveAndOpenCSV(csvContent, fileName);
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
      
      // Platform-specific implementation
      await platform_impl.saveAndOpenCSV(csvContent, fileName);
    } catch (e) {
      AppLogger.error('❌ CSV oluşturma hatası', e);
      rethrow;
    }
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
      
      // Platform-specific implementation
      await platform_impl.saveAndOpenCSV(csvContent, fileName);
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
