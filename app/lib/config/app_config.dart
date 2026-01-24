/// Uygulama yapılandırma dosyası
/// Production ve development için farklı ayarlar

class AppConfig {
  // Backend Configuration
  // Firebase Cloud Functions URL formatı: https://[region]-[project-id].cloudfunctions.net/api
  // NOT: Production'da bu değer Firebase project ID'den otomatik oluşturulmalı
  // Örnek: https://us-central1-expense-tracker-12345.cloudfunctions.net/api
  static const String productionBackendUrl = 'https://us-central1-management-app0.cloudfunctions.net/api'; // Firebase Functions URL
  
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
