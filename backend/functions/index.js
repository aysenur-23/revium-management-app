/**
 * Firebase Cloud Functions
 * Express backend'i Firebase Functions olarak deploy eder
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const express = require('express');
const multer = require('multer');
const {google} = require('googleapis');
const cors = require('cors');

// Firebase Admin SDK'yı başlat
admin.initializeApp();

const app = express();

// CORS ayarları - tüm originlere izin ver
app.use(cors({origin: true}));

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
let isOAuth2Client = false;

async function initializeDriveClient() {
  try {
    let auth;

    // Environment variables'dan Service Account bilgilerini al
    const serviceAccountEmail = functions.config().google?.service_account_email;
    const serviceAccountPrivateKey = functions.config().google?.service_account_private_key;

    if (serviceAccountEmail && serviceAccountPrivateKey) {
      auth = new google.auth.JWT({
        email: serviceAccountEmail,
        key: serviceAccountPrivateKey.replace(/\\n/g, '\n'),
        scopes: ['https://www.googleapis.com/auth/drive.file'],
      });
      console.log('✅ Google Drive Service Account (env variables) ile başlatıldı');
    } else {
      console.error('❌ Google Drive kimlik bilgileri bulunamadı!');
      console.error('💡 Firebase Functions config ile ayarlayın:');
      console.error('   firebase functions:config:set google.service_account_email="..."');
      console.error('   firebase functions:config:set google.service_account_private_key="..."');
      driveClient = null;
      return;
    }

    if (auth) {
      driveClient = google.drive({version: 'v3', auth});
      console.log('✅ Google Drive client başarıyla başlatıldı');
    } else {
      driveClient = null;
      console.log('⚠️  Google Drive client başlatılamadı');
    }
  } catch (error) {
    console.error('❌ Google Drive client başlatma hatası:', error.message);
    driveClient = null;
  }
}

// Uygulama başlatıldığında Drive client'ı initialize et
initializeDriveClient();

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    service: 'Expense Tracker Backend',
    status: 'running',
    version: '1.0.0',
    platform: 'Firebase Cloud Functions',
    endpoints: {
      health: '/health',
      upload: '/upload (POST)',
    },
  });
});

// Upload endpoint
app.post('/upload', upload.single('file'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({error: 'Dosya bulunamadı'});
    }

    if (!driveClient) {
      return res.status(500).json({
        error: 'Google Drive client başlatılamadı',
        message: 'Service Account kimlik bilgileri bulunamadı.',
        solution: 'Firebase Functions config ile google.service_account_email ve google.service_account_private_key ayarlayın',
      });
    }

    const file = req.file;
    const ownerId = req.body.ownerId || 'unknown';

    console.log(`Dosya yükleme başlatıldı: ${file.originalname}, Owner: ${ownerId}`);

    // Dosya metadata'sı
    const fileMetadata = {
      name: file.originalname,
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

    let errorMessage = error.message;
    let solution = '';

    if (error.message.includes('No key or keyFile set')) {
      errorMessage = 'Google Drive kimlik bilgileri bulunamadı';
      solution = 'Firebase Functions config ile Service Account bilgilerini ayarlayın';
    } else if (error.message.includes('permission')) {
      errorMessage = 'Google Drive izin hatası';
      solution = 'Service Account\'a Google Drive API erişimi verildiğinden emin olun';
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
    platform: 'Firebase Cloud Functions',
  });
});

// Express uygulamasını Firebase Cloud Function olarak export et
exports.api = functions.https.onRequest(app);
