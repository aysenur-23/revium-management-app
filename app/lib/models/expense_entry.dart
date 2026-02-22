/// Harcama kaydı modeli
/// Firestore entries koleksiyonunda saklanan harcama kayıtlarını temsil eder
library;

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
  final String entryType; // "expense", "income", veya "tax_deductible" (varsayılan: "expense")
  final String status; // "active" veya "deleted"
  final DateTime? createdAt;
  final DateTime? deletedAt;

  ExpenseEntry({
    this.id,
    required this.ownerId,
    required this.ownerName,
    required this.description,
    this.notes,
    required this.amount,
    this.fileUrl = '', // Income için boş olabilir
    this.fileType = 'none', // Income için 'none' olabilir
    this.driveFileId = '', // Income için boş olabilir
    this.mimeType,
    this.fileName,
    this.fixedExpenseId,
    this.entryType = 'expense', // Varsayılan olarak harcama
    this.status = 'active',
    this.createdAt,
    this.deletedAt,
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
            notes: json['notes'] as String?,
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      fileUrl: json['fileUrl'] as String? ?? '',
      fileType: json['fileType'] as String? ?? 'image',
      driveFileId: json['driveFileId'] as String? ?? '',
      mimeType: json['mimeType'] as String?,
      fileName: json['fileName'] as String?,
      fixedExpenseId: json['fixedExpenseId'] as String?,
      entryType: json['entryType'] as String? ?? 'expense', // Varsayılan: expense
      status: json['status'] as String? ?? 'active',
      createdAt: parseCreatedAt(json['createdAt']),
      deletedAt: parseCreatedAt(json['deletedAt']),
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
      'status': status,
      // createdAt Firestore'da serverTimestamp olarak ayarlanacak
    };
    if (deletedAt != null) {
      map['deletedAt'] = deletedAt!;
    }
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
    if (entryType != 'expense') {
      map['entryType'] = entryType; // income veya tax_deductible ise ekle (geriye dönük uyumluluk için)
    }
    return map;
  }

  /// Map representation (UploadService veya başka yerler için)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ownerId': ownerId,
      'ownerName': ownerName,
      'description': description,
      'notes': notes,
      'amount': amount,
      'fileUrl': fileUrl,
      'fileType': fileType,
      'driveFileId': driveFileId,
      'mimeType': mimeType,
      'fileName': fileName,
      'fixedExpenseId': fixedExpenseId,
      'entryType': entryType,
      'status': status,
      'createdAt': createdAt?.toIso8601String(),
      'deletedAt': deletedAt?.toIso8601String(),
    };
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
    String? entryType,
    String? status,
    DateTime? createdAt,
    DateTime? deletedAt,
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
      entryType: entryType ?? this.entryType,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}

