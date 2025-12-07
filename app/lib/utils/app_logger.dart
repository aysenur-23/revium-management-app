/**
 * Production-safe logging utility
 * Her zaman konsola yazdırır (debug ve release mode'da)
 */

import 'package:flutter/foundation.dart';

class AppLogger {
  /// Info log (her zaman konsola yazdır)
  static void info(String message) {
    debugPrint('ℹ️ [INFO] $message');
  }

  /// Success log (her zaman konsola yazdır)
  static void success(String message) {
    debugPrint('✅ [SUCCESS] $message');
  }

  /// Warning log (her zaman konsola yazdır)
  static void warning(String message) {
    debugPrint('⚠️ [WARNING] $message');
  }

  /// Error log (her zaman konsola yazdır)
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    debugPrint('❌ [ERROR] $message');
    if (error != null) {
      debugPrint('   Error: $error');
    }
    if (stackTrace != null) {
      debugPrint('   StackTrace: $stackTrace');
    }
  }

  /// Debug log (her zaman konsola yazdır)
  static void debug(String message) {
    debugPrint('🔍 [DEBUG] $message');
  }
}

