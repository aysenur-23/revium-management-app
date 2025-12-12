/**
 * Dosya referans modeli
 * Google Drive'da saklanan dosyalar için metadata
 */

import 'package:cloud_firestore/cloud_firestore.dart';

class AppFileReference {
  final String id; // Firestore doc id
  final String driveFileId; // Google Drive fileId
  final String name; // Original file name
  final String mimeType; // e.g. application/pdf, image/jpeg, application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
  final int? sizeBytes;
  final DateTime createdAt;
  final String uploadedByUserId;
  final String? description;

  const AppFileReference({
    required this.id,
    required this.driveFileId,
    required this.name,
    required this.mimeType,
    this.sizeBytes,
    required this.createdAt,
    required this.uploadedByUserId,
    this.description,
  });

  /// Firestore'dan oluştur
  factory AppFileReference.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AppFileReference(
      id: doc.id,
      driveFileId: data['driveFileId'] as String? ?? data['fileId'] as String? ?? '',
      name: data['name'] as String? ?? data['fileName'] as String? ?? '',
      mimeType: data['mimeType'] as String? ?? data['fileType'] as String? ?? 'application/octet-stream',
      sizeBytes: data['sizeBytes'] as int? ?? data['fileSize'] as int?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      uploadedByUserId: data['uploadedByUserId'] as String? ?? data['ownerId'] as String? ?? '',
      description: data['description'] as String?,
    );
  }

  /// Firestore'a kaydet
  Map<String, dynamic> toFirestore() {
    return {
      'driveFileId': driveFileId,
      'name': name,
      'mimeType': mimeType,
      if (sizeBytes != null) 'sizeBytes': sizeBytes,
      'createdAt': Timestamp.fromDate(createdAt),
      'uploadedByUserId': uploadedByUserId,
      if (description != null) 'description': description,
    };
  }

  /// ExpenseEntry'den oluştur (mevcut yapı için)
  factory AppFileReference.fromExpenseEntry({
    required String entryId,
    required String driveFileId,
    required String fileUrl,
    required String fileType,
    required String ownerId,
    String? mimeType,
    String? fileName,
  }) {
    // Öncelik sırası: 1) Parametre olarak gelen mimeType/fileName, 2) fileType'dan çıkar, 3) URL'den çıkar
    String finalMimeType = mimeType ?? 'application/octet-stream';
    String finalName = fileName ?? 'dosya';
    
    // Eğer mimeType verilmemişse, fileType'dan çıkar
    if (mimeType == null || mimeType.isEmpty) {
      if (fileType == 'pdf') {
        finalMimeType = 'application/pdf';
        if (fileName == null) finalName = 'dosya.pdf';
      } else if (fileType == 'image') {
        finalMimeType = 'image/jpeg';
        if (fileName == null) finalName = 'dosya.jpg';
      } else if (fileType == 'excel' || fileType == 'xlsx') {
        finalMimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
        if (fileName == null) finalName = 'dosya.xlsx';
      } else if (fileType == 'csv') {
        finalMimeType = 'text/csv';
        if (fileName == null) finalName = 'dosya.csv';
      }
    }
    
    // Eğer fileName verilmemişse, URL'den çıkar (eğer varsa)
    if (fileName == null && fileUrl.isNotEmpty) {
      final uri = Uri.tryParse(fileUrl);
      if (uri != null) {
        final segments = uri.pathSegments;
        if (segments.isNotEmpty) {
          final lastSegment = segments.last;
          if (lastSegment.isNotEmpty && lastSegment.contains('.')) {
            finalName = lastSegment;
          }
        }
      }
    }

    return AppFileReference(
      id: entryId,
      driveFileId: driveFileId,
      name: finalName,
      mimeType: finalMimeType,
      createdAt: DateTime.now(),
      uploadedByUserId: ownerId,
    );
  }

  /// Dosya tipini belirle (pdf, image, excel, other)
  String get fileTypeCategory {
    if (mimeType.contains('pdf')) return 'pdf';
    if (mimeType.startsWith('image/')) return 'image';
    if (mimeType.contains('spreadsheet') || mimeType.contains('excel') || mimeType.contains('csv')) return 'excel';
    return 'other';
  }

  /// Dosya uzantısını belirle
  String get fileExtension {
    if (name.contains('.')) {
      return name.split('.').last.toLowerCase();
    }
    
    // MIME type'dan çıkar
    if (mimeType.contains('pdf')) return 'pdf';
    if (mimeType.contains('jpeg') || mimeType.contains('jpg')) return 'jpg';
    if (mimeType.contains('png')) return 'png';
    if (mimeType.contains('spreadsheet') || mimeType.contains('excel')) return 'xlsx';
    if (mimeType.contains('csv')) return 'csv';
    
    return 'bin';
  }
}

