# Harcama Takip Uygulaması

Flutter mobil uygulama + Firebase Cloud Functions backend ile Google Drive entegrasyonu.

## 📱 APK

**Konum:** `app/build/app/outputs/flutter-apk/app-release.apk` (24 MB)

**Yükleme:** Telefona kopyalayıp yükleyin (Bilinmeyen kaynaklardan yükleme izni gerekli)

## 🚀 Hızlı Başlangıç

### Backend (Firebase Cloud Functions)

1. **Firebase CLI Kurulumu:**
   ```bash
   npm install -g firebase-tools
   firebase login
   ```

2. **Firebase Functions Environment Variables Ayarları:**
   
   Firebase Functions v7+ için environment variables kullanıyoruz. Google Service Account bilgilerini ayarlayın:
   
   **Secrets (Gizli Bilgiler) - Önerilen:**
   ```bash
   # Service Account bilgileri (gizli)
   echo "your-service-account@project.iam.gserviceaccount.com" | firebase functions:secrets:set GOOGLE_SERVICE_ACCOUNT_EMAIL
   echo "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n" | firebase functions:secrets:set GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY
   ```
   
   **Environment Variables (Genel Bilgiler):**
   ```bash
   # API Key ve Folder ID'ler (genel)
   firebase functions:config:set GOOGLE_API_KEY="your-google-api-key"
   firebase functions:config:set GOOGLE_DRIVE_FOLDER_ID="1yAvPlU5LqcDX5HJk55usmkFd1OrNrhe1"
   firebase functions:config:set GOOGLE_SHEETS_FOLDER_ID="1yO4roZMvMLxHDW4oHnQ592hX6opIRthG"
   firebase functions:config:set GOOGLE_SHEETS_FIXED_EXPENSES_ID="1Ta2VG93hhih4kRxj_qAUJ5_NrNWCWxKLdRYZNvag-O4"
   ```
   
   **Alternatif: `.env` Dosyası (Local Development):**
   
   `backend/functions/.env` dosyası oluşturun:
   ```env
   GOOGLE_SERVICE_ACCOUNT_EMAIL=your-service-account@project.iam.gserviceaccount.com
   GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
   GOOGLE_API_KEY=your-google-api-key
   GOOGLE_DRIVE_FOLDER_ID=1yAvPlU5LqcDX5HJk55usmkFd1OrNrhe1
   GOOGLE_SHEETS_FOLDER_ID=1yO4roZMvMLxHDW4oHnQ592hX6opIRthG
   GOOGLE_SHEETS_FIXED_EXPENSES_ID=1Ta2VG93hhih4kRxj_qAUJ5_NrNWCWxKLdRYZNvag-O4
   ```
   
   **ÖNEMLİ:** 
   - `service_account_email`: Google Cloud Console > IAM & Admin > Service Accounts'dan alınır
   - `service_account_private_key`: Service Account key JSON dosyasından alınır (tüm key'i kopyalayın, `\n` karakterlerini koruyun)
   - `api_key`: Google Cloud Console > APIs & Services > Credentials'dan alınır
   - `drive_folder_id`: Google Drive klasör ID'si (Maliyet belgeleri klasörü)
   - `sheets_folder_id`: Google Drive klasör ID'si (Excel/Sheets dosyaları klasörü)
   - `sheets_fixed_expenses_id`: Google Sheets dosya ID'si (Sabit giderler için)

3. **Functions'ı Deploy Edin:**
   ```bash
   cd backend/functions
   npm install
   cd ../..
   firebase deploy --only functions
   ```

4. **Backend URL'ini Alın:**
   
   Deploy sonrası Firebase Console'dan Functions URL'ini alın:
   - Format: `https://[region]-[project-id].cloudfunctions.net/api`
   - Örnek: `https://us-central1-expense-tracker-12345.cloudfunctions.net/api`
   
   Bu URL'yi `app/lib/config/app_config.dart` dosyasındaki `productionBackendUrl` değişkenine ekleyin.

### Flutter Uygulaması

```bash
cd app
flutter pub get
flutter run
```

## 📋 Özellikler

- ✅ Kullanıcı girişi (ad soyad)
- ✅ Harcama kaydı ekleme
- ✅ Dosya yükleme (PNG, JPEG, PDF)
- ✅ Google Drive entegrasyonu
- ✅ Google Sheets entegrasyonu (Sabit giderler dinamik okuma)
- ✅ Firebase Firestore
- ✅ İstatistikler

## 🔧 Google Cloud Console

**Service Account Kurulumu:**

1. **Google Cloud Console'a gidin:** https://console.cloud.google.com
2. **APIs & Services > Library** > **Google Drive API** > Enable
3. **IAM & Admin > Service Accounts** > **Create Service Account**
4. Service Account'a **Editor** rolü verin
5. Service Account'u seçin > **Keys** > **Add Key** > **Create new key** > **JSON**
6. İndirilen JSON dosyasından `client_email` ve `private_key` değerlerini alın
7. Bu değerleri Firebase Functions environment variables'a ekleyin (yukarıdaki adım 2'ye bakın)

## 📝 Notlar

- **Backend URL:** Firebase Cloud Functions URL'i `app/lib/config/app_config.dart` dosyasındaki `productionBackendUrl` değişkenine eklenmelidir
- **APK:** Herhangi bir Android telefona yüklenebilir, backend URL otomatik
- **Siyah Ekran Sorunu:** Dialog kapatma ve exception handling iyileştirildi
- **Google Drive Klasörü:** Tüm maliyet belgeleri (PDF, JPEG, PNG vb.) belirtilen klasöre kaydedilir
  - Klasör ID: `1yAvPlU5LqcDX5HJk55usmkFd1OrNrhe1`
  - Klasör linki: https://drive.google.com/drive/folders/1yAvPlU5LqcDX5HJk55usmkFd1OrNrhe1
  - Bu klasör ID'si Firebase Functions config'e `google.drive_folder_id` olarak eklenmelidir
- **Google Sheets Sabit Giderler:** Sabit giderler Google Sheets'ten dinamik olarak okunur
  - Sheets ID: `1Ta2VG93hhih4kRxj_qAUJ5_NrNWCWxKLdRYZNvag-O4`
  - Sheets linki: https://docs.google.com/spreadsheets/d/1Ta2VG93hhih4kRxj_qAUJ5_NrNWCWxKLdRYZNvag-O4/edit
  - Yeni eklenen satırlar otomatik olarak uygulamada görünecektir
  - Sheets formatı: Açıklama, Tutar, Kişi, Kategori, Tekrarlama, Notlar, Aktif/Pasif
  - Bu Sheets ID'si Firebase Functions config'e `google.sheets_fixed_expenses_id` olarak eklenmelidir
