/**
 * Kullanıcı profil modeli
 * Firestore users koleksiyonunda saklanan kullanıcı bilgilerini temsil eder
 */

class UserProfile {
  final String userId;
  final String fullName;
  final DateTime? createdAt;

  UserProfile({
    required this.userId,
    required this.fullName,
    this.createdAt,
  });

  /// Firestore'dan gelen Map'i UserProfile'a dönüştürür
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      userId: json['userId'] as String? ?? '',
      fullName: json['fullName'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? (json['createdAt'] as dynamic).toDate()
          : null,
    );
  }

  /// UserProfile'ı Firestore'a kaydetmek için Map'e dönüştürür
  Map<String, dynamic> toJson() {
    return {
      'fullName': fullName,
      if (createdAt != null) 'createdAt': createdAt,
    };
  }

  /// SharedPreferences için basit Map (userId ve fullName)
  Map<String, String> toLocalJson() {
    return {
      'userId': userId,
      'fullName': fullName,
    };
  }

  /// SharedPreferences'tan UserProfile oluşturur
  factory UserProfile.fromLocalJson(Map<String, String> json) {
    return UserProfile(
      userId: json['userId'] ?? '',
      fullName: json['fullName'] ?? '',
    );
  }
}

