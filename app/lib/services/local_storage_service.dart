/**
 * Lokal depolama servisi
 * SharedPreferences kullanarak kullanıcı bilgilerini saklar
 */

import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';

class LocalStorageService {
  static const String _keyUserId = 'userId';
  static const String _keyFullName = 'fullName';

  /// Kullanıcı bilgilerini kaydeder
  static Future<void> saveUser(String userId, String fullName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserId, userId);
    await prefs.setString(_keyFullName, fullName);
  }

  /// Kaydedilmiş kullanıcı bilgilerini getirir
  static Future<UserProfile?> getSavedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(_keyUserId);
    final fullName = prefs.getString(_keyFullName);

    if (userId != null && fullName != null) {
      return UserProfile(userId: userId, fullName: fullName);
    }
    return null;
  }

  /// Kullanıcı bilgilerini siler (çıkış yapma için)
  static Future<void> clearUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUserId);
    await prefs.remove(_keyFullName);
  }

  /// Ad soyadı normalize ederek userId oluşturur
  /// Örnek: "Ayşe Nur Aslan" -> "ayse_nur_aslan"
  static String normalizeUserId(String fullName) {
    return fullName
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^a-z0-9_]'), '');
  }
}

