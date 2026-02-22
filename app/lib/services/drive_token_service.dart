/// Google Drive OAuth: Kullanıcının Drive'ında Excel oluşturmak için access token.
/// Token varsa backend bu token ile dosyayı kullanıcının Drive'ında açar (kullanıcının kotası kullanılır).
library;

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../config/app_config.dart';
import '../utils/app_logger.dart';

class DriveTokenService {
  static GoogleSignIn? _googleSignIn;
  static GoogleSignInAccount? _cachedAccount;
  static bool _isExplicitlyConnected = false;

  static const _driveScopes = [
    'https://www.googleapis.com/auth/drive.file',
    'https://www.googleapis.com/auth/drive',
    'https://www.googleapis.com/auth/spreadsheets',
  ];

  static GoogleSignIn _getGoogleSignIn() {
    _googleSignIn ??= GoogleSignIn(
      scopes: _driveScopes,
      clientId: kIsWeb && AppConfig.googleSignInWebClientId.isNotEmpty
          ? AppConfig.googleSignInWebClientId
          : null,
    );
    return _googleSignIn!;
  }

  /// Kullanıcıyı Google ile giriş yaptırır (sadece Drive erişimi). E-posta girişi ayrı kalır.
  static Future<String?> connectDrive() async {
    try {
      final googleSignIn = _getGoogleSignIn();
      final account = await googleSignIn.signIn();
      if (account == null) {
        AppLogger.info('Drive bağlantısı iptal edildi');
        return null;
      }
      _cachedAccount = account;
      _isExplicitlyConnected = true;
      final auth = await account.authentication;
      final token = auth.accessToken;
      if (token != null) {
        AppLogger.success('Drive bağlantısı başarılı');
        return token;
      }
      AppLogger.warning('Drive access token alınamadı');
      return null;
    } catch (e) {
      AppLogger.error('Drive bağlantı hatası', e);
      return null;
    }
  }

  /// Mevcut Drive access token'ı döndürür (sessiz giriş). Yoksa null.
  /// Web'de signInSilently FedCM popup'ı tetikler ve başarısız olur,
  /// bu yüzden sadece kullanıcı açıkça connectDrive() yaptıysa token döner.
  static Future<String?> getDriveAccessToken() async {
    try {
      // Kullanıcı Drive'ı açıkça bağlamadıysa token'a gerek yok (backend SA kullanır)
      if (!_isExplicitlyConnected) return null;

      // Önce cached account üzerinden deneyelim
      if (_cachedAccount != null) {
        final auth = await _cachedAccount!.authentication;
        return auth.accessToken;
      }

      // Web'de signInSilently FedCM popup hatası verir, atla
      if (kIsWeb) return null;

      final googleSignIn = _getGoogleSignIn();
      final account = await googleSignIn.signInSilently();
      if (account == null) return null;
      _cachedAccount = account;
      final auth = await account.authentication;
      return auth.accessToken;
    } catch (_) {
      return null;
    }
  }

  /// Drive bağlantısını kaldırır.
  static Future<void> disconnectDrive() async {
    try {
      await _getGoogleSignIn().signOut();
      _cachedAccount = null;
      _isExplicitlyConnected = false;
      AppLogger.info('Drive bağlantısı kaldırıldı');
    } catch (e) {
      AppLogger.warning('Drive disconnect hatası: $e');
    }
  }

  /// Kullanıcı Drive'a bağlı mı?
  static Future<bool> get isDriveConnected async {
    if (!_isExplicitlyConnected) return false;
    final token = await getDriveAccessToken();
    return token != null && token.isNotEmpty;
  }
}

