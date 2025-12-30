/// Uygulama yapılandırma dosyası
/// Production ve development için farklı ayarlar

class AppConfig {
  // Supabase Configuration
  // NOT: Production'da bu değerler environment variables veya secure storage'dan alınmalı
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5lbXd1dW5ib3d6dXV5dmhtZWhpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwMTQ3OTUsImV4cCI6MjA4MDU5MDc5NX0.xHM791yFkBMSCi_EdF7OhdOq9iscD0-dT6sHuNr1JYM';

  // Backend Configuration
  static const String productionBackendUrl = 'https://nemwuunbowzuuyvhmehi.supabase.co/functions/v1/upload';
  
  // Google Sheets Configuration
  static const String googleSheetsFixedExpensesId = '1Ta2VG93hhih4kRxj_qAUJ5_NrNWCWxKLdRYZNvag-O4';

  // Network Configuration
  static const int uploadTimeoutSeconds = 30;
  static const int responseTimeoutSeconds = 10;
  static const int healthCheckTimeoutSeconds = 5;
  static const int maxRetries = 2;
  static const Duration retryDelay = Duration(seconds: 2);

  // File Configuration
  static const int maxFileSizeMB = 50;
  static const int maxFileSizeBytes = maxFileSizeMB * 1024 * 1024;
  static const List<String> allowedFileExtensions = ['jpg', 'jpeg', 'png', 'pdf'];

  // Performance Configuration
  static const int listViewCacheExtent = 250; // Optimize edildi - daha az bellek kullanımı
  static const int imageCacheWidth = 140; // 2x for retina
  static const int imageCacheHeight = 140;
  static const int maxImageCacheSize = 100; // MB
  static const int searchDebounceMs = 300; // Arama debounce süresi

  // Firestore Configuration
  static const int firestoreTimeoutSeconds = 10;
  static const int streamLimit = 100;

  // UI Configuration
  static const int animationDurationMs = 300;
  static const int snackBarDurationSeconds = 3;
}
