/// Production-safe logging utility
/// Her zaman konsola yazdırır (debug ve release mode'da)
/// print() kullanır - release mode'da da görünür
class AppLogger {
  /// Info log (her zaman konsola yazdır)
  // ignore: avoid_print
  static void info(String message) {
    print('ℹ️ [INFO] $message');
  }

  /// Success log (her zaman konsola yazdır)
  // ignore: avoid_print
  static void success(String message) {
    print('✅ [SUCCESS] $message');
  }

  /// Warning log (her zaman konsola yazdır)
  // ignore: avoid_print
  static void warning(String message) {
    print('⚠️ [WARNING] $message');
  }

  /// Error log (her zaman konsola yazdır)
  // ignore: avoid_print
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    print('❌ [ERROR] $message');
    if (error != null) {
      // ignore: avoid_print
      print('   Error: $error');
    }
    if (stackTrace != null) {
      // ignore: avoid_print
      print('   StackTrace: $stackTrace');
    }
  }

  /// Debug log (her zaman konsola yazdır)
  // ignore: avoid_print
  static void debug(String message) {
    print('🔍 [DEBUG] $message');
  }
}

