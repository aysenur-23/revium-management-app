/**
 * Harcama kaydı modeli
 * Firestore entries koleksiyonunda saklanan harcama kayıtlarını temsil eder
 */

import 'package:cloud_firestore/cloud_firestore.dart';

class ExpenseEntry {
  final String? id; // Firestore document ID
  final String ownerId;
  final String ownerName;
  final String description;
  final String? notes; // Opsiyonel açıklama
  final double amount;
  final String fileUrl;
  final String fileType; // "image" veya "pdf" (legacy - geriye dönük uyumluluk için)
  final String driveFileId;
  final String? mimeType; // Gerçek MIME type (application/pdf, image/jpeg, vb.)
  final String? fileName; // Gerçek dosya adı (dosya.pdf, resim.jpg, vb.)
  final String? fixedExpenseId; // Bağlı sabit gider ID'si (opsiyonel)
  final DateTime? createdAt;

  ExpenseEntry({
    this.id,
    required this.ownerId,
    required this.ownerName,
    required this.description,
    this.notes,
    required this.amount,
    required this.fileUrl,
    required this.fileType,
    required this.driveFileId,
    this.mimeType,
    this.fileName,
    this.fixedExpenseId,
    this.createdAt,
  });

  /// Firestore'dan gelen Map'i ExpenseEntry'ye dönüştürür
  factory ExpenseEntry.fromJson(Map<String, dynamic> json, String docId) {
    DateTime? parseCreatedAt(dynamic createdAt) {
      if (createdAt == null) return null;
      try {
        // Timestamp objesi ise
        if (createdAt is Timestamp) {
          return createdAt.toDate();
        }
        // Map ise (Firestore'dan gelen format)
        if (createdAt is Map) {
          final seconds = createdAt['_seconds'] as int?;
          if (seconds != null) {
            return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
          }
        }
        // String ise
        if (createdAt is String) {
          return DateTime.tryParse(createdAt);
        }
        // DateTime ise
        if (createdAt is DateTime) {
          return createdAt;
        }
        return null;
      } catch (e) {
        return null;
      }
    }

    return ExpenseEntry(
      id: docId,
      ownerId: json['ownerId'] as String? ?? '',
      ownerName: json['ownerName'] as String? ?? '',
      description: json['description'] as String? ?? '',
            notes: json['notes'] as String? ?? null,
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      fileUrl: json['fileUrl'] as String? ?? '',
      fileType: json['fileType'] as String? ?? 'image',
      driveFileId: json['driveFileId'] as String? ?? '',
      mimeType: json['mimeType'] as String?,
      fileName: json['fileName'] as String?,
      fixedExpenseId: json['fixedExpenseId'] as String?,
      createdAt: parseCreatedAt(json['createdAt']),
    );
  }

  /// ExpenseEntry'yi Firestore'a kaydetmek için Map'e dönüştürür
  Map<String, dynamic> toJson() {
    final map = {
      'ownerId': ownerId,
      'ownerName': ownerName,
      'description': description,
      'amount': amount,
      'fileUrl': fileUrl,
      'fileType': fileType,
      'driveFileId': driveFileId,
      // createdAt Firestore'da serverTimestamp olarak ayarlanacak
    };
    if (notes != null && notes!.isNotEmpty) {
      map['notes'] = notes!;
    }
    if (mimeType != null && mimeType!.isNotEmpty) {
      map['mimeType'] = mimeType!;
    }
    if (fileName != null && fileName!.isNotEmpty) {
      map['fileName'] = fileName!;
    }
    if (fixedExpenseId != null && fixedExpenseId!.isNotEmpty) {
      map['fixedExpenseId'] = fixedExpenseId!;
    }
    return map;
  }

  /// ExpenseEntry'nin kopyasını oluşturur (id ile)
  ExpenseEntry copyWith({
    String? id,
    String? ownerId,
    String? ownerName,
    String? description,
    String? notes,
    double? amount,
    String? fileUrl,
    String? fileType,
    String? driveFileId,
    String? mimeType,
    String? fileName,
    String? fixedExpenseId,
    DateTime? createdAt,
  }) {
    return ExpenseEntry(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      ownerName: ownerName ?? this.ownerName,
      description: description ?? this.description,
      notes: notes ?? this.notes,
      amount: amount ?? this.amount,
      fileUrl: fileUrl ?? this.fileUrl,
      fileType: fileType ?? this.fileType,
      driveFileId: driveFileId ?? this.driveFileId,
      mimeType: mimeType ?? this.mimeType,
      fileName: fileName ?? this.fileName,
      fixedExpenseId: fixedExpenseId ?? this.fixedExpenseId,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

