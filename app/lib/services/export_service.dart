/**
 * Export servisi
 * CSV formatında veri dışa aktarma
 */

import '../models/expense_entry.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';

class ExportService {
  /// Kayıtları CSV formatına dönüştürür
  static String exportToCSV(List<ExpenseEntry> entries) {
    final buffer = StringBuffer();
    // Web'de locale data yüklenmemiş olabilir, güvenli formatlama
    DateFormat dateFormat;
    try {
      dateFormat = DateFormat('dd.MM.yyyy HH:mm', kIsWeb ? null : 'tr_TR');
    } catch (e) {
      dateFormat = DateFormat('dd.MM.yyyy HH:mm');
    }

    // CSV başlıkları
    buffer.writeln('Tarih,Açıklama,Miktar (₺),Kişi,Dosya Tipi,Dosya URL');

    // Veriler
    for (var entry in entries) {
      final date = entry.createdAt != null
          ? dateFormat.format(entry.createdAt!)
          : 'Tarih yok';
      final description = _escapeCSV(entry.description);
      final amount = entry.amount.toStringAsFixed(2);
      final ownerName = _escapeCSV(entry.ownerName);
      final fileType = entry.fileType;
      final fileUrl = _escapeCSV(entry.fileUrl);

      buffer.writeln('$date,$description,$amount,$ownerName,$fileType,$fileUrl');
    }

    return buffer.toString();
  }

  /// CSV için özel karakterleri escape eder
  static String _escapeCSV(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  /// CSV dosyası adı oluşturur
  static String generateFileName(String prefix) {
    // Web'de locale data yüklenmemiş olabilir, güvenli formatlama
    DateFormat dateFormat;
    try {
      dateFormat = DateFormat('yyyy-MM-dd_HH-mm', kIsWeb ? null : 'tr_TR');
    } catch (e) {
      dateFormat = DateFormat('yyyy-MM-dd_HH-mm');
    }
    return '${prefix}_${dateFormat.format(DateTime.now())}.csv';
  }
}

