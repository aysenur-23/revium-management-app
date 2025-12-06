/**
 * Express backend servisi
 * Google Drive'a dosya yükleme işlemlerini yönetir
 */

const express = require('express');
const multer = require('multer');
const { google } = require('googleapis');
const cors = require('cors');
require('dotenv').config();

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
let isOAuth2Client = false; // OAuth2 client kullanılıp kullanılmadığını takip et
let oauth2Client = null; // OAuth2 client referansı

async function initializeDriveClient() {
  try {
    let auth;
    const fs = require('fs');

    // Öncelik 1: Service Account JSON dosyası (en kolay yöntem)
    if (fs.existsSync('./service-account-key.json')) {
      auth = new google.auth.GoogleAuth({
        keyFile: './service-account-key.json',
        scopes: ['https://www.googleapis.com/auth/drive.file'],
      });
      console.log('✅ Google Drive Service Account (JSON dosyası) ile başlatıldı');
    }
    // Öncelik 2: Service Account (environment variables)
    else if (process.env.GOOGLE_SERVICE_ACCOUNT_EMAIL && process.env.GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY) {
      auth = new google.auth.JWT({
        email: process.env.GOOGLE_SERVICE_ACCOUNT_EMAIL,
        key: process.env.GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY?.replace(/\\n/g, '\n'),
        scopes: ['https://www.googleapis.com/auth/drive.file'],
      });
      console.log('✅ Google Drive Service Account (env variables) ile başlatıldı');
    }
    // Öncelik 3: OAuth Client Secret (client_secret.json dosyası)
    else if (fs.existsSync('./client_secret.json')) {
      try {
        const credentials = require('./client_secret.json');
        const clientId = credentials.installed?.client_id || credentials.web?.client_id;
        const clientSecret = credentials.installed?.client_secret || credentials.web?.client_secret;
        
        if (!clientId || !clientSecret) {
          throw new Error('client_secret.json dosyasında client_id veya client_secret bulunamadı.');
        }
        
        // OAuth2 client oluştur
        oauth2Client = new google.auth.OAuth2(
          clientId,
          clientSecret,
          'http://localhost:4000/auth/callback'
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
        console.error('❌ client_secret.json okuma hatası:', error.message);
        throw new Error('client_secret.json dosyası geçersiz. Service Account JSON key dosyası kullanın.');
      }
    }
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

    if (auth) {
      driveClient = google.drive({ version: 'v3', auth });
      console.log('✅ Google Drive client başarıyla başlatıldı');
    } else {
      driveClient = null;
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
      message: 'client_secret.json dosyası bulunamadı veya geçersiz.'
    });
  }

  const scopes = ['https://www.googleapis.com/auth/drive.file'];
  const authUrl = oauth2Client.generateAuthUrl({
    access_type: 'offline', // Refresh token almak için
    scope: scopes,
    prompt: 'consent', // Her zaman refresh token almak için
    redirect_uri: 'http://localhost:4000/auth/callback'
  });

  res.json({
    authUrl: authUrl,
    message: 'Bu URL\'yi tarayıcıda açın ve yetkilendirme yapın. Sonra /auth/callback?code=... endpoint\'ine yönlendirileceksiniz.'
  });
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
      message: 'client_secret.json dosyası bulunamadı veya geçersiz.'
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

    console.log(`Dosya yükleme başlatıldı: ${file.originalname}, Owner: ${ownerId}`);

    // Dosya metadata'sı
    const fileMetadata = {
      name: file.originalname,
      parents: process.env.GOOGLE_DRIVE_FOLDER_ID ? [process.env.GOOGLE_DRIVE_FOLDER_ID] : [],
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

// Root endpoint
app.get('/', (req, res) => {
  res.json({ 
    service: 'Expense Tracker Backend',
    status: 'running',
    version: '1.0.0',
    endpoints: {
      health: '/health',
      upload: '/upload (POST)'
    }
  });
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
app.listen(PORT, () => {
  console.log(`Backend sunucusu ${PORT} portunda çalışıyor`);
  console.log(`Health check: http://localhost:${PORT}/health`);
});

