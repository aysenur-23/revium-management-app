/**
 * Network connectivity servisi
 * İnternet bağlantısını kontrol eder
 */

import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  static final Connectivity _connectivity = Connectivity();

  /// İnternet bağlantısı var mı kontrol eder
  static Future<bool> hasInternetConnection() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return result != ConnectivityResult.none;
    } catch (e) {
      return false;
    }
  }

  /// İnternet bağlantı durumunu stream olarak döndürür
  static Stream<bool> streamInternetConnection() {
    return _connectivity.onConnectivityChanged.map((result) {
      return result != ConnectivityResult.none;
    });
  }

  /// WiFi bağlantısı var mı kontrol eder
  static Future<bool> isWifiConnected() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return result == ConnectivityResult.wifi;
    } catch (e) {
      return false;
    }
  }

  /// Mobil veri bağlantısı var mı kontrol eder
  static Future<bool> isMobileConnected() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return result == ConnectivityResult.mobile;
    } catch (e) {
      return false;
    }
  }
}

