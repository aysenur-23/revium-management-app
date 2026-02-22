/**
 * Express backend servisi
 * Google Drive'a dosya yükleme işlemlerini yönetir
 */

const express = require('express');
const multer = require('multer');
const { google } = require('googleapis');
const cors = require('cors');
const fs = require('fs');
const path = require('path');
require('dotenv').config();

// Environment variable'ları kontrol et ve log'la
console.log('🔍 Environment Variables Kontrolü:');
console.log('  GOOGLE_SHEETS_FIXED_EXPENSES_ID:', process.env.GOOGLE_SHEETS_FIXED_EXPENSES_ID || '❌ AYARLANMAMIŞ');
console.log('  GOOGLE_SHEETS_FOLDER_ID:', process.env.GOOGLE_SHEETS_FOLDER_ID || '❌ AYARLANMAMIŞ');
console.log('  GOOGLE_API_KEY:', process.env.GOOGLE_API_KEY ? '✅ AYARLI' : '❌ AYARLANMAMIŞ');

// Google API Key (Google Sheets okuma için)
const GOOGLE_API_KEY = process.env.GOOGLE_API_KEY;
if (!GOOGLE_API_KEY) {
  console.error('❌ CRITICAL: GOOGLE_API_KEY environment variable is not set!');
}
const GOOGLE_SHEETS_API = 'https://sheets.googleapis.com/v4/spreadsheets';
const GOOGLE_DRIVE_API_V3 = 'https://www.googleapis.com/drive/v3';

const app = express();
const PORT = process.env.PORT || 4000;

// CORS ayarları - tüm originlere izin ver (geliştirme için)
app.use(cors());

// CSP header'ları - geliştirme için esnek ayarlar
app.use((req, res, next) => {
  res.setHeader(
    'Content-Security-Policy',
    "default-src 'self' http://localhost:* https:; connect-src 'self' http://localhost:* https:; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline';"
  );
  next();
});

app.use(express.json());

// Multer yapılandırması - memory storage kullan
const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 50 * 1024 * 1024, // 50MB limit
  },
});

// Google Drive Auth yapılandırması
let driveClient = null;
let sheetsClient = null; // Reusable sheets client
let driveAuth = null; // Auth referansı (Sheets için kullanılacak)
let isOAuth2Client = false; // OAuth2 client kullanılıp kullanılmadığını takip et
let oauth2Client = null; // OAuth2 client referansı

// Spreadsheet ID önbelleği - her seferinde files.list yapmamak için
const spreadsheetCache = {};

async function initializeDriveClient() {
  try {
    let auth;
    const fs = require('fs');

    // Öncelik 1: Service Account JSON dosyası (en kolay yöntem)
    if (fs.existsSync('./service-account-key.json')) {
      auth = new google.auth.GoogleAuth({
        keyFile: './service-account-key.json',
        scopes: [
          'https://www.googleapis.com/auth/drive.file',
          'https://www.googleapis.com/auth/spreadsheets',
        ],
      });
      console.log('✅ Google Drive Service Account (JSON dosyası) ile başlatıldı');
    }
    // Öncelik 2: Service Account (environment variables)
    else if (process.env.GOOGLE_SERVICE_ACCOUNT_EMAIL && process.env.GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY) {
      auth = new google.auth.JWT({
        email: process.env.GOOGLE_SERVICE_ACCOUNT_EMAIL,
        key: process.env.GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY?.replace(/\\n/g, '\n'),
        scopes: [
          'https://www.googleapis.com/auth/drive.file',
          'https://www.googleapis.com/auth/spreadsheets',
        ],
      });
      console.log('✅ Google Drive Service Account (env variables) ile başlatıldı');
    }
    // Öncelik 3: OAuth Client Secret (env veya client_secret*.json dosyası - ortamdan bağımsız)
    else {
      let clientId = process.env.GOOGLE_CLIENT_ID;
      let clientSecret = process.env.GOOGLE_CLIENT_SECRET;
      let credentialsPath = null;

      if (!clientId || !clientSecret) {
        const path1 = path.join(__dirname, 'client_secret.json');
        const path2 = path.join(__dirname, 'client_secret_google.json');
        const path3 = path.join(__dirname, 'client_secret_web.json');
        if (fs.existsSync(path1)) credentialsPath = path1;
        else if (fs.existsSync(path2)) credentialsPath = path2;
        else if (fs.existsSync(path3)) credentialsPath = path3;
      }

      if (credentialsPath) {
        try {
          const credentials = JSON.parse(fs.readFileSync(credentialsPath, 'utf8'));
          clientId = clientId || credentials.installed?.client_id || credentials.web?.client_id;
          clientSecret = clientSecret || credentials.installed?.client_secret || credentials.web?.client_secret;
        } catch (e) {
          console.error('❌ OAuth credentials dosyası okunamadı:', e.message);
        }
      }

      if (clientId && clientSecret) {
        try {
          const redirectUri = process.env.GOOGLE_OAUTH_REDIRECT_URI || 'http://localhost:4000/auth/callback';

          // OAuth2 client oluştur
          oauth2Client = new google.auth.OAuth2(
            clientId,
            clientSecret,
            redirectUri
          );

          // Refresh token kontrolü (.env veya token.json dosyasından)
          const refreshToken = process.env.GOOGLE_REFRESH_TOKEN ||
            (fs.existsSync('./token.json') ? require('./token.json').refresh_token : null);

          if (refreshToken) {
            // Refresh token varsa, access token'ı otomatik al
            oauth2Client.setCredentials({
              refresh_token: refreshToken
            });

            // Access token'ı yenile
            try {
              const { credentials: tokenCredentials } = await oauth2Client.refreshAccessToken();
              oauth2Client.setCredentials(tokenCredentials);
              auth = oauth2Client;
              isOAuth2Client = false; // Token var, normal kullanım
              console.log('✅ OAuth Client Secret ile refresh token kullanılarak başlatıldı');
              console.log('✅ Kullanıcıdan bağımsız dosya yükleme aktif');
            } catch (refreshError) {
              console.warn('⚠️  Refresh token geçersiz veya süresi dolmuş:', refreshError.message);
              isOAuth2Client = true; // Token yok, OAuth flow gerekli
              auth = oauth2Client;
            }
          } else {
            isOAuth2Client = true; // Token yok, OAuth flow gerekli
            auth = oauth2Client;
          }

          if (isOAuth2Client) {
            console.log('⚠️  OAuth Client Secret ile başlatıldı (refresh token yok)');
            console.warn('⚠️  UYARI: Dosya yükleme için refresh token gereklidir!');
            console.warn('⚠️  Service Account kullanmanız önerilir.');
            console.warn('');
            console.warn('💡 Refresh token almak için:');
            console.warn('   1. Google Cloud Console > APIs & Services > OAuth consent screen');
            console.warn('   2. "Test users" bölümüne test kullanıcı email\'lerini ekleyin');
            console.warn('   3. OAuth flow yapıp refresh token alın ve .env dosyasına GOOGLE_REFRESH_TOKEN olarak ekleyin');
          }
        } catch (error) {
          if (error.message.includes('OAuth token')) {
            throw error; // OAuth token hatasını yukarı fırlat
          }
          console.error('❌ OAuth credentials hatası:', error.message);
          throw new Error('OAuth client_id/client_secret geçersiz veya eksik. GOOGLE_CLIENT_ID/GOOGLE_CLIENT_SECRET env veya client_secret*.json kullanın.');
        }
      } // if (clientId && clientSecret)
      else {
        console.error('❌ Google Drive kimlik bilgileri bulunamadı!');
        console.error('');
        console.error('💡 ÇÖZÜM ADIMLARI:');
        console.error('   1. Google Cloud Console\'a gidin: https://console.cloud.google.com');
        console.error('   2. Projenizi seçin: central-diode-480320-v1');
        console.error('   3. "APIs & Services" > "Library" > "Google Drive API" > Enable');
        console.error('   4. "IAM & Admin" > "Service Accounts" > "Create Service Account"');
        console.error('   5. Service Account\'a "Editor" rolü verin');
        console.error('   6. Service Account\'u seçin > "Keys" > "Add Key" > "Create new key" > "JSON"');
        console.error('   7. İndirilen JSON dosyasını backend klasörüne "service-account-key.json" olarak kaydedin');
        console.error('');
        console.error('⚠️  NOT: API Key (AIzaSyACSOnrnYvO0gRDFmLol2b-GTDRMgmZN2A) dosya yükleme için yeterli değil!');
        console.error('   Google Drive API\'ye dosya yüklemek için Service Account key dosyası gereklidir.');
        console.error('');
        console.error('📝 TEST KULLANICILARI (OAuth için gerekli, Service Account için gerekmez):');
        console.error('   - Google Cloud Console > APIs & Services > OAuth consent screen');
        console.error('   - "Test users" bölümüne email adreslerini ekleyin');
        console.error('   - Service Account kullanıyorsanız test kullanıcı eklemenize gerek yok');
        throw new Error('Google Drive kimlik bilgileri bulunamadı. Lütfen service-account-key.json dosyasını ekleyin.');
      }
    } // Öncelik 3 else sonu

    if (auth) {
      driveAuth = auth; // Auth'u global değişkende sakla
      driveClient = google.drive({ version: 'v3', auth });
      sheetsClient = google.sheets({ version: 'v4', auth }); // Sheets client'ı bir kez oluştur
      console.log('✅ Google Drive ve Sheets clientları başarıyla başlatıldı');
    } else {
      driveClient = null;
      sheetsClient = null;
      driveAuth = null;
      console.log('⚠️  Google Drive client başlatılamadı (OAuth token gerekli)');
    }
  } catch (error) {
    console.error('❌ Google Drive client başlatma hatası:', error.message);
    driveClient = null; // driveClient'ı null yap ki hata mesajı dönsün
  }
}

// Uygulama başlatıldığında Drive client'ı initialize et
initializeDriveClient().catch(err => {
  console.error('Drive client başlatma hatası:', err);
});

/**
 * GET /auth
 * OAuth flow başlatır - refresh token almak için
 */
app.get('/auth', (req, res) => {
  if (!oauth2Client) {
    return res.status(500).json({
      error: 'OAuth2 client bulunamadı',
      message: 'OAuth client_id/client_secret bulunamadı (env veya client_secret*.json).'
    });
  }

  const scopes = ['https://www.googleapis.com/auth/drive.file'];
  const authUrl = oauth2Client.generateAuthUrl({
    access_type: 'offline', // Refresh token almak için
    scope: scopes,
    prompt: 'consent', // Her zaman refresh token almak için
    redirect_uri: 'http://localhost:4000/auth/callback'
  });

  res.redirect(authUrl);
});

app.get('/debug-quota', async (req, res) => {
  if (!driveClient) return res.status(500).send('Drive client not initialized');
  try {
    const about = await driveClient.about.get({ fields: 'storageQuota,user' });
    res.json(about.data);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

/**
 * GET /auth/callback
 * OAuth callback - refresh token'ı alır ve kaydeder
 */
app.get('/auth/callback', async (req, res) => {
  const code = req.query.code;

  if (!code) {
    return res.status(400).json({
      error: 'Authorization code bulunamadı',
      message: 'OAuth flow\'u tamamlamak için code parametresi gereklidir.'
    });
  }

  if (!oauth2Client) {
    return res.status(500).json({
      error: 'OAuth2 client bulunamadı',
      message: 'OAuth client_id/client_secret bulunamadı (env veya client_secret*.json).'
    });
  }

  try {
    const { tokens } = await oauth2Client.getToken(code);
    oauth2Client.setCredentials(tokens);

    // Refresh token'ı .env dosyasına ekle veya token.json'a kaydet
    const fs = require('fs');
    const refreshToken = tokens.refresh_token;

    if (refreshToken) {
      // .env dosyasına ekle
      const envContent = fs.existsSync('./.env') ? fs.readFileSync('./.env', 'utf8') : '';
      if (!envContent.includes('GOOGLE_REFRESH_TOKEN')) {
        fs.appendFileSync('./.env', `\nGOOGLE_REFRESH_TOKEN=${refreshToken}\n`);
      } else {
        // Mevcut refresh token'ı güncelle
        const updatedEnv = envContent.replace(
          /GOOGLE_REFRESH_TOKEN=.*/,
          `GOOGLE_REFRESH_TOKEN=${refreshToken}`
        );
        fs.writeFileSync('./.env', updatedEnv);
      }

      // token.json'a da kaydet (yedek)
      fs.writeFileSync('./token.json', JSON.stringify(tokens, null, 2));

      // Drive client'ı yeniden başlat
      await initializeDriveClient();

      res.json({
        success: true,
        message: 'Refresh token başarıyla kaydedildi! Artık kullanıcıdan bağımsız dosya yükleyebilirsiniz.',
        refreshToken: refreshToken.substring(0, 20) + '...' // İlk 20 karakteri göster
      });
    } else {
      res.status(400).json({
        error: 'Refresh token alınamadı',
        message: 'OAuth flow tamamlandı ancak refresh token alınamadı. Lütfen tekrar deneyin.'
      });
    }
  } catch (error) {
    console.error('OAuth callback hatası:', error);
    res.status(500).json({
      error: 'OAuth callback hatası',
      message: error.message
    });
  }
});

/**
 * POST /upload
 * Dosyayı Google Drive'a yükler ve paylaşım linkini döndürür
 */
app.post('/upload', upload.single('file'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'Dosya bulunamadı' });
    }

    if (!driveClient) {
      return res.status(500).json({
        error: 'Google Drive client başlatılamadı',
        message: 'Service Account JSON key dosyası bulunamadı. Lütfen backend klasörüne service-account-key.json dosyasını ekleyin.',
        solution: 'Google Cloud Console > IAM & Admin > Service Accounts > Keys > Create new key > JSON'
      });
    }

    // OAuth2 client kullanılıyorsa token kontrolü
    if (isOAuth2Client) {
      return res.status(401).json({
        error: 'OAuth token gerekli',
        message: 'OAuth Client Secret ile dosya yüklemek için OAuth token gereklidir. Service Account key dosyası kullanmanız önerilir.',
        solution: 'Google Cloud Console > IAM & Admin > Service Accounts > Keys > Create new key > JSON'
      });
    }

    const file = req.file;
    const ownerId = req.body.ownerId || 'unknown';
    const ownerName = req.body.ownerName || 'Unknown';
    const description = req.body.description || '';
    const amount = req.body.amount || '0';
    const entryType = req.body.entryType || 'expense'; // 'expense' veya 'income'

    // Dosya adı oluştur: OwnerName_YYYY-MM-DD_Description_Amount.ext
    const dateStr = new Date().toISOString().split('T')[0]; // YYYY-MM-DD format
    const originalExt = file.originalname.split('.').pop() || 'pdf';

    // Özel karakterleri temizle ve kısalt
    const cleanOwnerName = ownerName.replace(/[^a-zA-ZığüşöçİĞÜŞÖÇ0-9]/g, '').substring(0, 20);
    const cleanDescription = description.replace(/[^a-zA-ZığüşöçİĞÜŞÖÇ0-9\s]/g, '').replace(/\s+/g, '_').substring(0, 30);
    const cleanAmount = String(Math.round(parseFloat(amount) || 0));

    // Nihai dosya adı
    const customFileName = `${cleanOwnerName}_${dateStr}_${cleanDescription}_${cleanAmount}.${originalExt}`;

    console.log(`Dosya yükleme başlatıldı: ${file.originalname} -> ${customFileName}, Owner: ${ownerId}, Type: ${entryType}`);

    // Income (ortak gelirleri) için farklı klasör, expense için normal klasör
    let targetFolderId;
    if (entryType === 'income') {
      // Ortak gelirleri klasörü
      targetFolderId = process.env.GOOGLE_DRIVE_INCOME_FOLDER_ID || '1H9Wijuwv6ghsrt9DGgAIBiBeHhw5S3GK';
    } else if (entryType === 'tax_deductible') {
      // Vergi/Tax Deductible klasörü
      targetFolderId = process.env.GOOGLE_DRIVE_TAX_FOLDER_ID || '1t8aPwVtOsvtTsXoHEfZsXvXDhAFBxVN6';
    } else {
      // Normal giderler klasörü
      targetFolderId = process.env.GOOGLE_DRIVE_FOLDER_ID;
    }

    // Dosya metadata'sı - description dahil özel isim
    const fileMetadata = {
      name: customFileName,
      parents: targetFolderId ? [targetFolderId] : [],
    };

    // Media ayarları
    const media = {
      mimeType: file.mimetype,
      body: require('stream').Readable.from(file.buffer),
    };

    // Google Drive'a yükle
    const uploadedFile = await driveClient.files.create({
      requestBody: fileMetadata,
      media: media,
      fields: 'id, name',
    });

    const fileId = uploadedFile.data.id;
    console.log(`Dosya yüklendi. File ID: ${fileId}`);

    // Dosyayı "herkes link ile görüntüleyebilir" olarak ayarla
    await driveClient.permissions.create({
      fileId: fileId,
      requestBody: {
        role: 'reader',
        type: 'anyone',
      },
    });

    // Görüntüleme URL'i oluştur
    const fileUrl = `https://drive.google.com/uc?export=view&id=${fileId}`;

    res.json({
      fileId: fileId,
      fileUrl: fileUrl,
    });
  } catch (error) {
    console.error('Upload hatası:', error);

    // OAuth2 token hatası kontrolü
    if (isOAuth2Client && (error.message.includes('No key or keyFile set') || error.message.includes('invalid_grant') || error.message.includes('unauthorized'))) {
      return res.status(401).json({
        error: 'OAuth token gerekli',
        message: 'OAuth Client Secret ile dosya yüklemek için OAuth token gereklidir. Service Account key dosyası kullanmanız önerilir.',
        solution: 'Google Cloud Console > IAM & Admin > Service Accounts > Keys > Create new key > JSON'
      });
    }

    // Daha açıklayıcı hata mesajları
    let errorMessage = error.message;
    let solution = '';

    if (error.message.includes('No key or keyFile set')) {
      errorMessage = 'Google Drive kimlik bilgileri bulunamadı';
      solution = 'Backend klasörüne service-account-key.json dosyasını ekleyin. Google Cloud Console > Service Accounts > Keys > Create new key > JSON';
    } else if (error.message.includes('permission')) {
      errorMessage = 'Google Drive izin hatası';
      solution = 'Service Account\'a Google Drive API erişimi ve Editor rolü verildiğinden emin olun';
    } else if (error.message.includes('quota')) {
      errorMessage = 'Google Drive kotası aşıldı';
      solution = 'Google Drive depolama alanınızı kontrol edin';
    }

    res.status(500).json({
      error: 'Dosya yükleme başarısız',
      message: errorMessage,
      solution: solution || 'Backend loglarını kontrol edin',
    });
  }
});

// POST endpoint - Google Sheets oluşturma/güncelleme
app.post('/', async (req, res) => {
  try {
    const endpoint = req.query.endpoint;

    // Google Sheets oluşturma/güncelleme endpoint'i
    if (endpoint === 'prewarm-sheets') {
      if (!driveClient || !sheetsClient) {
        console.warn('⚠️ Prewarm skipped: Google Drive/Sheets client not initialized');
        return res.json({ success: false, message: 'Backend credentials missing (Service Account)' });
      }
      const { ownerName } = req.body;
      const results = [];

      const sheetNames = [
        ownerName ? `${ownerName} Eklediklerim.csv` : 'Eklediklerim.csv',
        'Tum Eklenenler.csv',
        'Ortak Gelirleri.csv',
        'Sabit Giderler'
      ];

      for (const name of sheetNames) {
        // Her biri için init-sheets mantığını çağır (basitleştirilmiş)
        try {
          const cleanName = name.replace(/\.(xlsx|csv)$/i, '');
          if (spreadsheetCache[cleanName]) {
            results.push({ name: cleanName, status: 'cached', id: spreadsheetCache[cleanName] });
            continue;
          }

          const sheetsFolderId = process.env.GOOGLE_SHEETS_FOLDER_ID;
          if (sheetsFolderId) {
            const escapedSheetName = cleanName.replace(/'/g, "\\'");
            const existingFiles = await driveClient.files.list({
              q: `name='${escapedSheetName}' and '${sheetsFolderId}' in parents and trashed=false and mimeType='application/vnd.google-apps.spreadsheet'`,
              fields: 'files(id, name)',
            });

            if (existingFiles.data.files && existingFiles.data.files.length > 0) {
              const sid = existingFiles.data.files[0].id;
              spreadsheetCache[cleanName] = sid;
              results.push({ name: cleanName, status: 'found', id: sid });
              continue;
            }
          }

          // Bulunamadıysa oluştur
          const newFile = await driveClient.files.create({
            requestBody: {
              name: cleanName,
              mimeType: 'application/vnd.google-apps.spreadsheet',
              ...(sheetsFolderId ? { parents: [sheetsFolderId] } : {}),
            },
            fields: 'id',
          });
          const sid = newFile.data.id;
          spreadsheetCache[cleanName] = sid;

          // Sheet1 eklensin diye dummy update, headers ile
          const headers = ['Tarih', 'Açıklama', 'Tutar', 'Kişi', 'Notlar', 'Dosya Linki'];
          await sheetsClient.spreadsheets.values.update({
            spreadsheetId: sid,
            range: 'Sheet1!A1',
            valueInputOption: 'RAW',
            requestBody: { values: [headers] },
          });

          // Permission
          await driveClient.permissions.create({
            fileId: sid,
            requestBody: { role: 'reader', type: 'anyone' },
          });

          results.push({ name: cleanName, status: 'created', id: sid });

        } catch (e) {
          console.error(`Prewarm error for ${name}:`, e.message);
          results.push({ name: name, status: 'error', error: e.message });
        }
      }
      return res.json({ success: true, results });

    } else if (endpoint === 'init-sheets') {
      if (!driveClient || !sheetsClient) {
        return res.status(500).json({
          error: 'Google Drive client başlatılamadı',
          message: 'Service Account kimlik bilgileri bulunamadı.',
        });
      }

      // OAuth2 client kullanılıyorsa token kontrolü
      if (isOAuth2Client) {
        return res.status(401).json({
          error: 'OAuth token gerekli',
          message: 'OAuth Client Secret ile Excel oluşturmak için OAuth token gereklidir.',
        });
      }

      try {
        const { entries = [], deletedEntries = [], fixedExpenses = [], sheetName = 'Giderler' } = req.body;
        const allData = [...entries, ...fixedExpenses];

        console.log(`📥 init-sheets: "${sheetName}" | Aktif: ${allData.length}, Silinmiş: ${deletedEntries.length}`);

        // Google Sheets için veri hazırla yardımcı fonksiyon
        const prepareValues = (dataList, isDeleted = false) => {
          let headers = ['Tarih', 'Açıklama', 'Tutar', 'Kişi', 'Notlar', 'Dosya Linki'];
          let values = [];

          if (sheetName.includes('Sabit')) {
            headers = ['Başlangıç Tarihi', 'Kategori', 'Açıklama', 'Tutar', 'Kişi', 'Tekrarlama', 'Durum', 'Notlar'];
            values.push(headers);
            for (const e of dataList) {
              values.push([
                e.dateTime || '',
                e.category || '',
                e.description || '',
                e.amount || 0,
                e.ownerName || '',
                e.recurrence || '',
                (e.isActive === false) ? 'Pasif' : 'Aktif',
                e.notes || '',
              ]);
            }
          } else {
            headers = ['Tarih', 'Tür', 'Kategori', 'Açıklama', 'Tutar', 'Kişi', 'Notlar', 'Dosya Linki'];
            if (isDeleted) headers = ['Silinme Tarihi', ...headers];
            values.push(headers);
            for (const e of dataList) {
              let typeLabel = 'Gider';
              if (e.entryType === 'income') typeLabel = 'Gelir';
              if (e.entryType === 'tax_deductible') typeLabel = 'Vergi Düşülebilir';

              const row = [
                e.dateTime || '',
                typeLabel,
                e.category || '',
                e.description || '',
                e.amount || 0,
                e.ownerName || '',
                e.notes || '',
                e.fileUrl || '',
              ];
              if (isDeleted) row.unshift(new Date().toISOString()); // Silinme tarihi (yaklaşık)
              values.push(row);
            }
          }
          return values;
        };

        const activeValues = prepareValues(allData);
        const deletedValues = deletedEntries.length > 0 ? prepareValues(deletedEntries, true) : null;

        const sheetsFolderId = process.env.GOOGLE_SHEETS_FOLDER_ID;
        const cleanSheetName = sheetName.replace(/\.(xlsx|csv)$/i, '');

        // Önce mevcut dosyayı kontrol et (Önce önbelleğe bak)
        let spreadsheetId = spreadsheetCache[cleanSheetName];

        // Helper function for updating multiple sheets within a spreadsheet
        const updateSpreadsheet = async (sid) => {
          try {
            // Ana sayfa adını belirle
            let mainTabName = 'Giderler';
            if (sheetName.includes('Sabit')) mainTabName = 'Sabit Giderler';
            else if (sheetName.includes('Gelir')) mainTabName = 'Gelirler';

            // Spreadsheet metadatasını al (sayfaları kontrol et)
            const spreadsheet = await sheetsClient.spreadsheets.get({ spreadsheetId: sid });
            const existingSheets = spreadsheet.data.sheets || [];

            const requests = [];
            const dataToUpdate = [];

            // Ana sayfa yoksa ekle veya adını güncelle
            const mainSheet = existingSheets.find(s => s.properties.title === mainTabName);
            if (!mainSheet) {
              // İlk sayfayı ana sayfa olarak isimlendir (varsayılan Sheet1 ise)
              if (existingSheets.length > 0 && existingSheets[0].properties.sheetId === 0) {
                requests.push({
                  updateSheetProperties: {
                    properties: { sheetId: 0, title: mainTabName },
                    fields: 'title'
                  }
                });
              } else {
                requests.push({ addSheet: { properties: { title: mainTabName } } });
              }
            }

            // Silinenler sayfası lazımsa ve yoksa ekle
            if (deletedValues) {
              const trashTabName = 'Silinenler';
              const trashSheet = existingSheets.find(s => s.properties.title === trashTabName);
              if (!trashSheet) {
                requests.push({ addSheet: { properties: { title: trashTabName } } });
              }
              dataToUpdate.push({ range: `${trashTabName}!A1`, values: deletedValues });
            }

            // Batch update ile sayfa yapılarını güncelle
            if (requests.length > 0) {
              await sheetsClient.spreadsheets.batchUpdate({
                spreadsheetId: sid,
                requestBody: { requests }
              });
            }

            // Verileri yaz
            dataToUpdate.unshift({ range: `${mainTabName}!A1`, values: activeValues });

            await sheetsClient.spreadsheets.values.batchUpdate({
              spreadsheetId: sid,
              requestBody: {
                data: dataToUpdate,
                valueInputOption: 'RAW'
              }
            });

            console.log(`✅ Spreadsheet güncelleme tamamlandı: ${sid}`);
          } catch (err) {
            console.error(`❌ Spreadsheet güncelleme hatası (${sid}):`, err.message);
            throw err;
          }
        };

        if (spreadsheetId) {
          console.log(`🚀 Önbellekten kullanılıyor: ${spreadsheetId}`);
          await updateSpreadsheet(spreadsheetId);

          const previewUrl = `https://docs.google.com/spreadsheets/d/${spreadsheetId}/htmlview`;
          return res.json({
            success: true,
            url: previewUrl,
            fileId: spreadsheetId,
            rowCount: allData.length,
            message: 'Google Sheets güncellendi (Senkronize)',
          });
        }

        // Önbellekte yoksa ara
        try {
          console.log(`🔍 Drive'da aranıyor: ${cleanSheetName}`);
          const escapedSheetName = cleanSheetName.replace(/'/g, "\\'");

          // Eğer klasör ID'si varsa klasör içinde, yoksa tüm Drive'da ara
          const searchContext = sheetsFolderId ? `'${sheetsFolderId}' in parents and ` : "";
          const query = `name='${escapedSheetName}' and ${searchContext}trashed=false and mimeType='application/vnd.google-apps.spreadsheet'`;

          const existingFiles = await driveClient.files.list({
            q: query,
            fields: 'files(id, name)',
          });

          if (existingFiles.data.files && existingFiles.data.files.length > 0) {
            spreadsheetId = existingFiles.data.files[0].id;
            spreadsheetCache[cleanSheetName] = spreadsheetId;
            console.log(`✅ Mevcut dosya bulundu (Drive): ${spreadsheetId}`);

            // Senkronize güncelle ve dön
            await updateSpreadsheet(spreadsheetId);

            const previewUrl = `https://docs.google.com/spreadsheets/d/${spreadsheetId}/htmlview`;
            return res.json({
              success: true,
              url: previewUrl,
              fileId: spreadsheetId,
              rowCount: allData.length,
              message: 'Google Sheets bulundu ve güncellendi',
            });
          }
        } catch (error) {
          console.warn('Mevcut dosya kontrolü hatası:', error.message);
        }

        // Bulunamadıysa oluştur (Oluşturma durumunda beklemek zorundayız çünkü ID yeni)
        console.log(`🆕 Yeni dosya oluşturuluyor: ${cleanSheetName}`);
        const newFile = await driveClient.files.create({
          requestBody: {
            name: cleanSheetName,
            mimeType: 'application/vnd.google-apps.spreadsheet',
            ...(sheetsFolderId ? { parents: [sheetsFolderId] } : {}),
          },
          fields: 'id',
        });

        spreadsheetId = newFile.data.id;
        spreadsheetCache[cleanSheetName] = spreadsheetId;

        // Dosya yeni olduğu için ilk güncelleme bloklayan olmalı
        await updateSpreadsheet(spreadsheetId);

        // Herkes link ile görüntüleyebilir (bir kez yapılması yeterli ama yeni dosya için gerekli)
        await driveClient.permissions.create({
          fileId: spreadsheetId,
          requestBody: { role: 'reader', type: 'anyone' },
        });

        const previewUrl = `https://docs.google.com/spreadsheets/d/${spreadsheetId}/htmlview`;
        return res.json({
          success: true,
          url: previewUrl,
          fileId: spreadsheetId,
          rowCount: allData.length,
          message: 'Yeni Google Sheets oluşturuldu',
        });

      } catch (error) {
        console.error('Init sheets error:', error);
        return res.status(500).json({ error: 'Google Sheets işlemi başarısız', message: error.message });
      }
    } else {
      return res.status(400).json({
        error: 'Geçersiz endpoint',
        message: 'POST endpoint için sadece "init-sheets" desteklenir',
      });
    }
  } catch (error) {
    console.error('POST endpoint error:', error);
    res.status(500).json({
      error: 'Backend hatası',
      message: error.message,
    });
  }
});

// Varsayılan sabit giderler sheet ID (tek dosya)
const DEFAULT_FIXED_EXPENSES_SHEET_ID = '1ZjeJIJ3h0MaHEbmDIM5N-mRKI2YxKuOM';

// GET endpoint - Google Sheets'ten sabit giderleri oku (sadece tek dosyadan)
app.get('/', async (req, res) => {
  try {
    const endpoint = req.query.endpoint;
    console.log('📥 GET / request received');
    console.log('  Query params:', JSON.stringify(req.query));
    console.log('  Endpoint:', endpoint);

    // Sabit giderler — sadece GOOGLE_SHEETS_FIXED_EXPENSES_ID (veya varsayılan) tek dosyadan
    if (endpoint === 'fixed-expenses') {
      const sheetId = process.env.GOOGLE_SHEETS_FIXED_EXPENSES_ID || DEFAULT_FIXED_EXPENSES_SHEET_ID;
      if (!GOOGLE_API_KEY || !sheetId) {
        return res.status(500).json({
          error: 'Sabit giderler ayarı eksik',
          message: 'GOOGLE_API_KEY ve GOOGLE_SHEETS_FIXED_EXPENSES_ID gerekli.',
          expenses: [],
        });
      }
      try {
        let sheetName = 'Sheet1';
        const metaResp = await fetch(`${GOOGLE_SHEETS_API}/${sheetId}?key=${GOOGLE_API_KEY}`);
        if (metaResp.ok) {
          const meta = await metaResp.json();
          sheetName = meta.sheets?.[0]?.properties?.title || 'Sheet1';
        }
        const range = `'${sheetName.replace(/'/g, "''")}'!A1:Z1000`;
        const dataResp = await fetch(`${GOOGLE_SHEETS_API}/${sheetId}/values/${encodeURIComponent(range)}?key=${GOOGLE_API_KEY}`);
        if (!dataResp.ok) {
          console.warn('fixed-expenses sheet okunamadı:', dataResp.status);
          return res.json({ expenses: [] });
        }
        const data = await dataResp.json();
        const values = data.values || [];
        const allExpenses = [];
        let startRow = 0;
        if (values.length > 0) {
          const firstRowStr = values[0].map(v => String(v).toLowerCase()).join('|');
          if (firstRowStr.includes('tarih') || firstRowStr.includes('açıklama') || firstRowStr.includes('tutar') || firstRowStr.includes('gider kalemi')) {
            startRow = 1;
          }
        }
        for (let i = startRow; i < values.length; i++) {
          const row = values[i];
          if (!row || row.length < 2) continue;
          const category = row[1] ? String(row[1]).trim() : null;
          let description = '';
          let amountStr = '0';
          const col2Num = row.length > 2 ? String(row[2]).replace(/[^\d.,-]/g, '').replace(',', '.') : '';
          const col3Num = row.length > 3 ? String(row[3]).replace(/[^\d.,-]/g, '').replace(',', '.') : '';
          const hasAylikYillik = row.length >= 4 && !isNaN(parseFloat(col3Num));
          if (hasAylikYillik) {
            description = row[1] ? String(row[1]).trim() : '';
            amountStr = col3Num || '0';
          } else {
            description = row.length > 2 ? String(row[2]).trim() : String(row[1] || '').trim();
            if (row.length > 3 && !isNaN(parseFloat(col3Num))) amountStr = col3Num;
            else if (row[2] && !isNaN(parseFloat(col2Num))) amountStr = col2Num;
          }
          if (!description) continue;
          const amount = parseFloat(amountStr) || 0;

          let createdAt = new Date().toISOString();
          if (row[0]) {
            try {
              const dParts = String(row[0]).split('.');
              if (dParts.length === 3) {
                createdAt = new Date(dParts[2], dParts[1] - 1, dParts[0]).toISOString();
              } else {
                createdAt = new Date(row[0]).toISOString();
              }
            } catch (e) { }
          }
          allExpenses.push({
            id: `sheet_${sheetId.substring(0, 8)}_${i}`,
            ownerId: 'system',
            ownerName: row[4] ? String(row[4]).trim() : 'Sistem',
            description,
            amount,
            category,
            recurrence: row[5] ? String(row[5]).trim().toLowerCase() : 'monthly',
            isActive: row[6] ? String(row[6]).toLowerCase().includes('aktif') : true,
            notes: row[7] ? String(row[7]).trim() : null,
            createdAt,
          });
        }
        console.log(`✅ Sabit giderler (tek dosya): ${allExpenses.length} kalem`);
        return res.json({ expenses: allExpenses });
      } catch (e) {
        console.error('fixed-expenses hatası:', e.message);
        return res.status(500).json({ error: 'Sabit giderler okunamadı', message: e.message, expenses: [] });
      }
    }

    // Root endpoint (endpoint parametresi yoksa)
    res.json({
      version: '1.0.0',
      endpoints: {
        health: '/health',
        upload: '/upload (POST)',
        initSheets: '/?endpoint=init-sheets (POST)',
        fixedExpenses: '/?endpoint=fixed-expenses (GET)'
      }
    });
  } catch (error) {
    console.error('GET endpoint error:', error);
    res.status(500).json({
      error: 'Backend hatası',
      message: error.message,
    });
  }
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'ok', message: 'Backend çalışıyor' });
});

// Favicon endpoint (404 hatasını önlemek için)
app.get('/favicon.ico', (req, res) => {
  res.status(204).end(); // No Content - favicon yok, sessizce yok say
});

// Chrome DevTools .well-known endpoint (404 hatasını önlemek için)
app.get('/.well-known/*', (req, res) => {
  res.status(204).end(); // No Content
});

// 404 handler - tanımlanmamış tüm route'lar için
app.use((req, res) => {
  res.status(404).json({
    error: 'Not found',
    path: req.path,
    message: 'Endpoint bulunamadı'
  });
});

// Server'ı başlat
// Server'ı başlat
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Backend sunucusu ${PORT} portunda çalışıyor (0.0.0.0)`);
  console.log(`Health check: http://localhost:${PORT}/health`);
  console.log(`Mobile Access: http://192.168.1.161:${PORT}/health`);
});

