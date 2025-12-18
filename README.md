# Harcama Takip Uygulaması

Flutter mobil uygulama + Supabase Edge Functions backend ile Google Drive entegrasyonu.

## 📱 APK

**Konum:** `app/build/app/outputs/flutter-apk/app-release.apk` (24 MB)

**Yükleme:** Telefona kopyalayıp yükleyin (Bilinmeyen kaynaklardan yükleme izni gerekli)

## 🚀 Hızlı Başlangıç

### Backend (Supabase Edge Functions)

1. **Supabase secrets ekle (Dashboard'dan):**
   - Supabase Dashboard > Project Settings > Edge Functions > Secrets
   - Şu secrets'ları ekleyin:
     - `GOOGLE_CLIENT_ID`: (Google Cloud Console'dan alınacak)
     - `GOOGLE_CLIENT_SECRET`: (Google Cloud Console'dan alınacak)
     - `GOOGLE_REFRESH_TOKEN`: (OAuth flow ile alınacak - aşağıya bakın)
     - `GOOGLE_DRIVE_FOLDER_ID`: `1yAvPlU5LqcDX5HJk55usmkFd1OrNrhe1` (Maliyet belgeleri klasörü)
       - **ÖNEMLİ:** Tüm yüklenen dosyalar (PDF, JPEG, PNG vb.) bu klasöre kaydedilir
       - Klasör linki: https://drive.google.com/drive/folders/1yAvPlU5LqcDX5HJk55usmkFd1OrNrhe1

2. **Edge Function'ı Deploy Edin:**
   
   **Yöntem 1: Supabase Dashboard (Önerilen)**
   - Supabase Dashboard > Edge Functions
   - "Create a new function" veya "Deploy function" butonuna tıklayın
   - Function adı: `upload`
   - `backend/supabase/functions/upload/index.ts` dosyasının içeriğini kopyalayıp yapıştırın
   - Deploy butonuna tıklayın
   
   **Yöntem 2: Supabase CLI (Eğer yüklüyse)**
   ```bash
   cd backend
   supabase functions deploy upload --project-ref nemwuunbowzuuyvhmehi
   ```

3. **Refresh Token almak için:**
   
   **ÖNEMLİ:** Function deploy edildikten sonra, authorization header ile `/auth` endpoint'ini çağırın:
   
   PowerShell ile:
   ```powershell
   $anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5lbXd1dW5ib3d6dXV5dmhtZWhpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwMTQ3OTUsImV4cCI6MjA4MDU5MDc5NX0.xHM791yFkBMSCi_EdF7OhdOq9iscD0-dT6sHuNr1JYM"
   $response = Invoke-RestMethod -Uri "https://nemwuunbowzuuyvhmehi.supabase.co/functions/v1/upload/auth" -Method GET -Headers @{"apikey"=$anonKey; "Authorization"="Bearer $anonKey"}
   $response.authUrl
   ```
   
   Dönen `authUrl` değerini tarayıcıda açın ve Google hesabınızla giriş yapın
   - Redirect sonrası `/auth/callback` endpoint'i refresh token'ı döndürecek
   - Bu token'ı Supabase secrets'a ekleyin

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
- ✅ Firebase Firestore
- ✅ İstatistikler

## 🔧 Google Cloud Console

**OAuth 2.0 Client ID Ayarları:**

1. **Authorized redirect URIs** bölümüne şu URI'leri ekleyin (path ile birlikte):
   - `http://localhost:4000/auth/callback`
   - `https://nemwuunbowzuuyvhmehi.supabase.co/functions/v1/upload/auth/callback`

2. **Authorized JavaScript origins** bölümüne şu origin'i ekleyin (sadece domain, path YOK):
   - `https://nemwuunbowzuuyvhmehi.supabase.co`
   
   ⚠️ **ÖNEMLİ:** JavaScript origins'de sadece domain olmalı, `/functions/v1/upload` gibi path eklemeyin!

## 📝 Notlar

- Backend URL: Supabase Edge Function URL'i otomatik kullanılır
- Refresh Token: OAuth flow ile bir kez alınır, Supabase secrets'a eklenir
- APK: Herhangi bir Android telefona yüklenebilir, backend URL otomatik
- Siyah Ekran Sorunu: Dialog kapatma ve exception handling iyileştirildi
- **Google Drive Klasörü:** Tüm maliyet belgeleri (PDF, JPEG, PNG vb.) belirtilen klasöre kaydedilir
  - Klasör ID: `1yAvPlU5LqcDX5HJk55usmkFd1OrNrhe1`
  - Klasör linki: https://drive.google.com/drive/folders/1yAvPlU5LqcDX5HJk55usmkFd1OrNrhe1
  - Bu klasör ID'si Supabase secrets'a `GOOGLE_DRIVE_FOLDER_ID` olarak eklenmelidir
- **ÖNEMLİ:** Supabase anon key'i `app/lib/services/upload_service.dart` dosyasında güncellenmelidir
  - Supabase Dashboard > Settings > API > anon public key'i kopyalayın
  - `upload_service.dart` dosyasındaki `supabaseAnonKey` değişkenini güncelleyin
