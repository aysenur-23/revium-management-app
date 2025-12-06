/**
 * Harcama kaydı modeli
 * Firestore entries koleksiyonunda saklanan harcama kayıtlarını temsil eder
 */

class ExpenseEntry {
  final String? id; // Firestore document ID
  final String ownerId;
  final String ownerName;
  final String description;
  final double amount;
  final String fileUrl;
  final String fileType; // "image" veya "pdf"
  final String driveFileId;
  final DateTime? createdAt;

  ExpenseEntry({
    this.id,
    required this.ownerId,
    required this.ownerName,
    required this.description,
    required this.amount,
    required this.fileUrl,
    required this.fileType,
    required this.driveFileId,
    this.createdAt,
  });

  /// Firestore'dan gelen Map'i ExpenseEntry'ye dönüştürür
  factory ExpenseEntry.fromJson(Map<String, dynamic> json, String docId) {
    return ExpenseEntry(
      id: docId,
      ownerId: json['ownerId'] as String? ?? '',
      ownerName: json['ownerName'] as String? ?? '',
      description: json['description'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      fileUrl: json['fileUrl'] as String? ?? '',
      fileType: json['fileType'] as String? ?? 'image',
      driveFileId: json['driveFileId'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? (json['createdAt'] as dynamic).toDate()
          : null,
    );
  }

  /// ExpenseEntry'yi Firestore'a kaydetmek için Map'e dönüştürür
  Map<String, dynamic> toJson() {
    return {
      'ownerId': ownerId,
      'ownerName': ownerName,
      'description': description,
      'amount': amount,
      'fileUrl': fileUrl,
      'fileType': fileType,
      'driveFileId': driveFileId,
      // createdAt Firestore'da serverTimestamp olarak ayarlanacak
    };
  }

  /// ExpenseEntry'nin kopyasını oluşturur (id ile)
  ExpenseEntry copyWith({
    String? id,
    String? ownerId,
    String? ownerName,
    String? description,
    double? amount,
    String? fileUrl,
    String? fileType,
    String? driveFileId,
    DateTime? createdAt,
  }) {
    return ExpenseEntry(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      ownerName: ownerName ?? this.ownerName,
      description: description ?? this.description,
      amount: amount ?? this.amount,
      fileUrl: fileUrl ?? this.fileUrl,
      fileType: fileType ?? this.fileType,
      driveFileId: driveFileId ?? this.driveFileId,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

