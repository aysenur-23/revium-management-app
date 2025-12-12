/**
 * Sabit gider modeli
 * Firestore fixed_expenses koleksiyonunda saklanan sabit gider kayıtlarını temsil eder
 */

import 'package:cloud_firestore/cloud_firestore.dart';

class FixedExpense {
  final String? id; // Firestore document ID
  final String ownerId;
  final String ownerName;
  final String description;
  final String? notes; // Opsiyonel açıklama
  final double amount;
  final String? category; // Kategori (opsiyonel)
  final DateTime? startDate; // Başlangıç tarihi
  final String? recurrence; // Tekrarlama: "monthly", "yearly", "one-time" (opsiyonel)
  final bool isActive; // Aktif/Pasif durumu
  final DateTime? createdAt;

  FixedExpense({
    this.id,
    required this.ownerId,
    required this.ownerName,
    required this.description,
    this.notes,
    required this.amount,
    this.category,
    this.startDate,
    this.recurrence,
    this.isActive = true,
    this.createdAt,
  });

  /// Firestore'dan gelen Map'i FixedExpense'ye dönüştürür
  factory FixedExpense.fromJson(Map<String, dynamic> json, String docId) {
    DateTime? parseDate(dynamic date) {
      if (date == null) return null;
      try {
        // Timestamp objesi ise
        if (date is Timestamp) {
          return date.toDate();
        }
        // Map ise (Firestore'dan gelen format)
        if (date is Map) {
          final seconds = date['_seconds'] as int?;
          if (seconds != null) {
            return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
          }
        }
        // String ise
        if (date is String) {
          return DateTime.tryParse(date);
        }
        // DateTime ise
        if (date is DateTime) {
          return date;
        }
        return null;
      } catch (e) {
        return null;
      }
    }

    return FixedExpense(
      id: docId,
      ownerId: json['ownerId'] as String? ?? '',
      ownerName: json['ownerName'] as String? ?? '',
      description: json['description'] as String? ?? '',
      notes: json['notes'] as String? ?? null,
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      category: json['category'] as String? ?? null,
      startDate: parseDate(json['startDate']),
      recurrence: json['recurrence'] as String? ?? null,
      isActive: json['isActive'] as bool? ?? true,
      createdAt: parseDate(json['createdAt']),
    );
  }

  /// FixedExpense'yi Firestore'a kaydetmek için Map'e dönüştürür
  Map<String, dynamic> toJson() {
    final map = {
      'ownerId': ownerId,
      'ownerName': ownerName,
      'description': description,
      'amount': amount,
      'isActive': isActive,
      // createdAt Firestore'da serverTimestamp olarak ayarlanacak
    };
    if (notes != null && notes!.isNotEmpty) {
      map['notes'] = notes!;
    }
    if (category != null && category!.isNotEmpty) {
      map['category'] = category!;
    }
    if (startDate != null) {
      map['startDate'] = Timestamp.fromDate(startDate!);
    }
    if (recurrence != null && recurrence!.isNotEmpty) {
      map['recurrence'] = recurrence!;
    }
    return map;
  }

  /// FixedExpense'nin kopyasını oluşturur
  FixedExpense copyWith({
    String? id,
    String? ownerId,
    String? ownerName,
    String? description,
    String? notes,
    double? amount,
    String? category,
    DateTime? startDate,
    String? recurrence,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return FixedExpense(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      ownerName: ownerName ?? this.ownerName,
      description: description ?? this.description,
      notes: notes ?? this.notes,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      startDate: startDate ?? this.startDate,
      recurrence: recurrence ?? this.recurrence,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

