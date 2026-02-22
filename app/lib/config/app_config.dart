/// Uygulama yapılandırma dosyası
/// Production ve development için farklı ayarlar
library;

class AppConfig {
  // Backend Configuration
  // Firebase Cloud Functions URL formatı: https://[region]-[project-id].cloudfunctions.net/api
  // NOT: Production'da bu değer Firebase project ID'den otomatik oluşturulmalı
  // Örnek: https://us-central1-expense-tracker-12345.cloudfunctions.net/api
  // 🔥 BURAYA DİKKAT: Firebase deploy işleminden sonra size verilen URL'i aşağıya yapıştırın:
  static const String productionBackendUrl = 'https://us-central1-manage-d9a18.cloudfunctions.net/api'; 
  
  // Google Sheets Configuration
  static const String googleSheetsFixedExpensesId = '1ZjeJIJ3h0MaHEbmDIM5N-mRKI2YxKuOM';
  /// Ortak gelirleri tablosu (ortak-gelirler) - gelir kayıtları bu Excel'e yazılır
  static const String googleSheetsOrtakGelirlerId = '1KqFnCDW03ZTXnK1WcYW1_v39GE24ugLp-GiC21ijut8';
  /// Vergiden düşülecekler tablosu - vergiden düşülecek kayıtlar bu Excel'e yazılır; eklenen dosyalar VergiBelgeleri klasörüne yüklenir
  static const String googleSheetsVergidenDusuleceklerId = '1Q5WBm1SNt-Qu_VIWDazvfX4_jjzTOOjl_B2s8sFZnt8';

  /// Google Sign-In Web Client ID (Drive OAuth - Web'de "Google Drive Bağla" için).
  /// Cloud Console > Kimlik Bilgileri > OAuth 2.0 İstemci Kimlikleri > "Web istemcisi 2" > Müşteri Kimliği (tam değer).
  /// Örnek format: 968047362592-xxxxxxxxxx.apps.googleusercontent.com
  static const String googleSignInWebClientId = '7040117025-homqf7u32j2i2o1nprai73uvtptl00ae.apps.googleusercontent.com';

  // Network Configuration (mobil ağda kesinti olmaması için yeterli süre)
  static const int uploadTimeoutSeconds = 90;
  static const int responseTimeoutSeconds = 45;
  static const int healthCheckTimeoutSeconds = 10;
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
