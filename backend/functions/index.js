/**
 * Firebase Cloud Functions
 * Express backend'i Firebase Functions olarak deploy eder
 */

const { onRequest } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { setGlobalOptions } = require('firebase-functions/v2/options');
const functions = require('firebase-functions/v1'); // Keep for safety if other parts need it, but mostly unused.
const admin = require('firebase-admin');
const express = require('express');
const multer = require('multer');
const Busboy = require('busboy');
const { google } = require('googleapis');
const cors = require('cors');
const MAX_FILE_SIZE = 50 * 1024 * 1024; // 50MB

// Firebase Admin SDK'yı başlat
admin.initializeApp();

const app = express();

// CORS ayarları - tüm originlere izin ver
app.use(cors({ origin: true }));

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
let sheetsClient = null; // Reusable sheets client (OAuth2 veya SA)
let saSheetsClient = null; // SA-only Sheets client (sabit tablolar için)
let saEmail = null; // SA e-postası
let driveAuth = null;
let isOAuth2Client = false;
/** Excel'e yazım yapan hesap e-postası (tabloya bu e-postayı düzenleyici ekleyin) */
let serviceAccountEmail = null;

// Spreadsheet ID önbelleği - her seferinde files.list yapmamak için
const spreadsheetCache = {};

// Google API Key (Google Sheets okuma için)
// Firebase Functions v7+ için secrets kullanıyoruz
// Secrets runtime'da process.env'e otomatik olarak eklenir
// Not: Bu değerler runtime'da secrets'tan yüklenecek
const GOOGLE_SHEETS_API = 'https://sheets.googleapis.com/v4/spreadsheets';
const GOOGLE_DRIVE_API_V3 = 'https://www.googleapis.com/drive/v3';

/** dd.MM.yyyy veya d.M.yyyy → yyyy-MM-dd */
function parseFuarTarih(raw) {
  if (!raw || typeof raw !== 'string') return null;
  const s = raw.trim();
  const parts = s.split(/[.\-/]/).map(p => parseInt(p, 10)).filter(n => !isNaN(n));
  if (parts.length !== 3) return null;
  const [a, b, c] = parts;
  let y, m, d;
  if (a > 31) {
    y = a; m = b; d = c;
  } else if (c > 31) {
    d = a; m = b; y = c;
  } else {
    d = a; m = b; y = c;
  }
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  try {
    return new Date(y, m - 1, d).toISOString().slice(0, 10);
  } catch (e) { return null; }
}

/** Fuarlar sheet'inden liste döner. Düzen: A=Fuar Adı, B=Başlangıç Tarihi, C=Bitiş Tarihi, D=Şehir, E=Web Site (veri A2:E500). */
async function fetchFuarlarList() {
  const apiKey = process.env.GOOGLE_API_KEY;
  const sheetId = process.env.GOOGLE_SHEETS_FUARLAR_ID;
  if (!apiKey || !sheetId) return [];
  try {
    const dataResp = await fetch(`${GOOGLE_SHEETS_API}/${sheetId}/values/A2:E500?key=${apiKey}`);
    if (!dataResp.ok) {
      const errBody = await dataResp.text();
      console.warn('fetchFuarlarList sheet okunamadı:', dataResp.status, errBody?.slice(0, 200));
      return [];
    }
    const data = await dataResp.json();
    const values = data.values || [];
    const fuarlar = [];
    for (let i = 0; i < values.length; i++) {
      const row = values[i];
      if (!row || row.length < 2) continue;
      const fuarAdi = row[0] ? String(row[0]).trim() : '';
      const rawBaslangic = row[1] ? String(row[1]).trim() : '';
      const rawBitis = row[2] ? String(row[2]).trim() : '';
      const yer = row[3] ? String(row[3]).trim() : '';
      const website = row[4] ? String(row[4]).trim() : '';
      if (!fuarAdi) continue;
      const tarihIso = parseFuarTarih(rawBaslangic);
      const bitisIso = parseFuarTarih(rawBitis) || null;
      fuarlar.push({ tarih: tarihIso, bitisTarih: bitisIso, yer, fuarAdi, website: website || null });
    }
    return fuarlar;
  } catch (e) {
    console.error('fetchFuarlarList error:', e.message);
    return [];
  }
}

// Runtime'da secrets'tan değerleri alacak helper fonksiyonlar
// Firebase Functions v7+ secrets'ları process.env'e otomatik olarak eklenir
function getGoogleApiKey() {
  return process.env.GOOGLE_API_KEY || '';
}

function getGoogleSheetsFixedExpensesId() {
  // Hardcoded to the user-provided spreadsheet for fixed expenses
  return '1ZjeJIJ3h0MaHEbmDIM5N-mRKI2YxKuOM';
}

// Tüm Excel/Sheets bu klasörde: listele buradan aç, yoksa burada oluştur (yeni Drive)
const SHEETS_FOLDER_ID_DEFAULT = '16kGuvI5LXtQ0HsCED6oW3Iv0vI3k-4Um';
const SHEETS_FOLDER_ID_OLD_BROKEN = '1yO4roZMvMLxHDW4oHnQ592hX6opIRthG';

function getGoogleSheetsFolderId() {
  const raw = process.env.GOOGLE_SHEETS_FOLDER_ID || SHEETS_FOLDER_ID_DEFAULT;
  const id = typeof raw === 'string' ? raw.trim() : '';
  if (!id || id === SHEETS_FOLDER_ID_OLD_BROKEN) return SHEETS_FOLDER_ID_DEFAULT;
  return id;
}

// maliyet-app ana klasörü: yüklenen dosyalar bu klasör içindeki MaliyetBelgeleri, GelirBelgeleri, VergiBelgeleri alt klasörlerine gider
// https://drive.google.com/drive/folders/1iJJ3qhYzC8B53gbJfMTEkdJGR0gjCmM_
const MALIYET_APP_ROOT_FOLDER_ID = '1iJJ3qhYzC8B53gbJfMTEkdJGR0gjCmM_';

function getGoogleDriveRootFolderId() {
  const raw = process.env.GOOGLE_DRIVE_ROOT_FOLDER_ID || process.env.GOOGLE_DRIVE_FOLDER_ID || MALIYET_APP_ROOT_FOLDER_ID || '';
  return typeof raw === 'string' ? raw.trim() : '';
}

// entryType → Drive alt klasör adı (görseldeki yapı)
const UPLOAD_SUBFOLDER_BY_ENTRY_TYPE = {
  expense: 'MaliyetBelgeleri',
  income: 'GelirBelgeleri',
  tax_deductible: 'VergiBelgeleri',
};

// Ana klasör içinde isimle alt klasör bulur veya oluşturur, ID döner
async function getOrCreateSubfolderId(drive, parentId, folderName) {
  const q = `'${parentId}' in parents and mimeType='application/vnd.google-apps.folder' and name='${folderName}' and trashed=false`;
  const list = await drive.files.list({
    q,
    fields: 'files(id, name)',
    spaces: 'drive',
  });
  const files = list.data.files || [];
  if (files.length > 0) {
    return files[0].id;
  }
  const create = await drive.files.create({
    requestBody: {
      name: folderName,
      mimeType: 'application/vnd.google-apps.folder',
      parents: [parentId],
    },
    fields: 'id',
  });
  return create.data.id;
}

// Excel/Sheets dosyalarının aranacağı klasör: root (maliyet-app) varsa "Excel" alt klasörü, yoksa GOOGLE_SHEETS_FOLDER_ID
async function getSheetsFolderIdForInit(drive) {
  const rootId = getGoogleDriveRootFolderId();
  if (rootId && drive) {
    try {
      const excelFolderId = await getOrCreateSubfolderId(drive, rootId, 'Excel');
      return excelFolderId;
    } catch (err) {
      console.warn('Excel alt klasörü alınamadı, GOOGLE_SHEETS_FOLDER_ID kullanılıyor:', err.message);
    }
  }
  return getGoogleSheetsFolderId();
}

// Dosya adı eşleştirme ve isimlendirme için: Türkçe karakterleri ASCII karşılıklarıyla değiştir
function normalizeTurkishCharacters(text) {
  if (!text || typeof text !== 'string') return '';
  // NFC normalizasyonu ile parçalı karakterleri (c + çengel) birleştirip sonra eşleştiriyoruz
  return text.normalize('NFC')
    .replace(/ı/g, 'i').replace(/İ/g, 'I')
    .replace(/ğ/g, 'g').replace(/Ğ/g, 'G')
    .replace(/ü/g, 'u').replace(/Ü/g, 'U')
    .replace(/ş/g, 's').replace(/Ş/g, 'S')
    .replace(/ö/g, 'o').replace(/Ö/g, 'O')
    .replace(/ç/g, 'c').replace(/Ç/g, 'C');
}

// Dosya adı eşleştirme: Türkçe karakterleri normalize et (Tüm ↔ Tum vb.)
function normalizeSheetName(name) {
  if (!name || typeof name !== 'string') return '';
  return normalizeTurkishCharacters(name)
    .trim()
    .toLowerCase();
}

// Sabit Excel eşlemesi (kullanıcının verdiği linkler). İsim normalize edilir (küçük harf, ı->i vb.).
// "Benim eklediklerim" KİŞİYE ÖZELdir: Sadece "Ad Soyad Eklediklerim" isteği, tam o normalize isimle eşleşirse sabit ID kullanılır.
// Örn. istek "Yılmaz UZUN Eklediklerim" → "yilmaz uzun eklediklerim" → sadece bu kullanıcının sabit dosyası. Başka kullanıcı "Ali Eklediklerim" derse sabit eşleşmez, kendi dosyası aranır/oluşturulur.
const MAIN_SPREADSHEET_ID = '1DflGMFqoS4PgmjD8Ekcx29WZgxMEmJ5AKq23E6bxcDw';

const FIXED_SHEET_IDS = {
  'tum eklenenler': MAIN_SPREADSHEET_ID,
  'tum veriler': MAIN_SPREADSHEET_ID,
  'sabit giderler': '1ZjeJIJ3h0MaHEbmDIM5N-mRKI2YxKuOM',
  'ortak gelirleri': '1KqFnCDW03ZTXnK1WcYW1_v39GE24ugLp-GiC21ijut8',
  'vergiden dusulecekler': '1Q5WBm1SNt-Qu_VIWDazvfX4_jjzTOOjl_B2s8sFZnt8',
  'harcamalar': '1DxNSb4O5K_doKPf7magQZgklXGVfGHShfKGoPSpvbWI',
  'deneme eklediklerim': '11Dkvgg8j7LEx5RRIZ1IDOSRmJ05YzmokgGBkL_vOlOE',
  'yilmaz uzun eklediklerim': '1GondmqiF8q1MQThh3wy6htaG7Febf7i7TQcji1j363g',
};

// Klasörde arama için: uygulama isteği → Drive'daki alternatif dosya adları
const SHEET_NAME_ALIASES = {
  'tum eklenenler': ['Tum Eklenenler', 'Tüm Eklenenler', 'Excel', 'Tum Veriler', 'Tüm Veriler', 'MaliyetBelgeleri'],
  'tum veriler': ['Tum Veriler', 'Tüm Veriler', 'Excel', 'Tum Eklenenler', 'Tüm Eklenenler'],
  'sabit giderler': ['Sabit Giderler', 'MaliyetBelgeleri', 'Sabit Gider', 'VergiBelgeleri'],
  'ortak gelirleri': ['Ortak Gelirleri', 'GelirBelgeleri', 'Gelir Belgeleri'],
  'sabit gelirler': ['Sabit Gelirler', 'Sabit Gelir', 'GelirBelgeleri'],
  'vergiden dusulecekler': ['Vergiden Düşülecekler', 'VergiBelgeleri', 'Vergi Düşülecekler'],
  'harcamalar': ['Harcamalar', 'Giderler', 'Expenses'],
};

async function initializeDriveClient() {
  try {
    let auth;

    // 1. Service Account JSON dosyası var mı kontrol et
    /*
    const fs = require('fs');
    const path = require('path');
    const serviceAccountPath = path.join(__dirname, 'service-account.json');

    if (fs.existsSync(serviceAccountPath)) {
      const serviceAccount = require('./service-account.json');
      auth = new google.auth.JWT({
        email: serviceAccount.client_email,
        key: serviceAccount.private_key,
        scopes: ['https://www.googleapis.com/auth/drive.file', 'https://www.googleapis.com/auth/drive.readonly', 'https://www.googleapis.com/auth/spreadsheets'],
      });
      console.log('✅ Google Drive Service Account (JSON dosyası) ile başlatıldı');
    }
    */

    /* 
    // 1. Service Account JSON dosyası var mı kontrol et
    const fs = require('fs');
    const path = require('path');
    const serviceAccountPath = path.join(__dirname, 'service-account.json');

    if (fs.existsSync(serviceAccountPath)) {
       // ... Logic commented out to forced ADC
       // const serviceAccount = require('./service-account.json');
       // auth = ...
       console.log('⚠️ [DEBUG] JSON file check skipped to force ADC');
    }

    // 2. Yoksa environment variables kontrol et
    const serviceAccountEmail = process.env.GOOGLE_SERVICE_ACCOUNT_EMAIL;
    const serviceAccountPrivateKey = process.env.GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY;

    if (!auth && serviceAccountEmail && serviceAccountPrivateKey) {
       // ... Logic commented out
       console.log('⚠️ [DEBUG] Env vars check skipped to force ADC');
    }
    */
    // Öncelik 1: Uygulama hesabı (Refresh Token) – insan hesabının 15 GB kotası kullanılır; SA'nın ~0 byte kotası DEĞİL
    const rawClientId = process.env.GOOGLE_CLIENT_ID || '';
    const rawClientSecret = process.env.GOOGLE_CLIENT_SECRET || '';
    let refreshToken = (process.env.GOOGLE_REFRESH_TOKEN || '').trim();
    // UTF-8 BOM (PowerShell/Windows kaynaklı) kaldır
    if (refreshToken.charCodeAt(0) === 0xFEFF) refreshToken = refreshToken.slice(1).trim();
    const clientId = rawClientId.trim();
    const clientSecret = rawClientSecret.trim();

    if (clientId && clientSecret && refreshToken) {
      try {
        const oAuth2Client = new google.auth.OAuth2(clientId, clientSecret);
        oAuth2Client.setCredentials({ refresh_token: refreshToken });
        await oAuth2Client.getAccessToken();
        auth = oAuth2Client;
        isOAuth2Client = true;
        console.log('✅ Google Drive: Uygulama hesabı (Refresh Token) – insan kotası kullanılıyor');
        // Refresh token hesabının e-postasını al — 403 hatalarında kullanıcıya gösterilecek
        try {
          const tempDrive = google.drive({ version: 'v3', auth: oAuth2Client });
          const aboutRes = await tempDrive.about.get({ fields: 'user' });
          const email = aboutRes.data && aboutRes.data.user && aboutRes.data.user.emailAddress;
          if (email) {
            serviceAccountEmail = email;
            console.log(`📧 Refresh token hesabı: ${email} — tablolara bu e-postanın düzenleme izni olmalı`);
          }
        } catch (emailErr) {
          console.warn('⚠️ Refresh token e-postası alınamadı:', emailErr.message);
        }
      } catch (oauthErr) {
        const detail = oauthErr.response && oauthErr.response.data ? JSON.stringify(oauthErr.response.data) : oauthErr.message;
        console.warn('⚠️ Refresh Token kullanılamadı, Service Account deneniyor (yükleme kotası hatası alırsınız):', detail);
        if (oauthErr.response) console.warn('OAuth status:', oauthErr.response.status, 'data:', oauthErr.response.data);
      }
    }

    // Öncelik 2: Service Account (JSON dosyası) — sabit tablolara yazmak için ayrı SA client oluştur
    // SA her zaman oluşturulur (sabit tablolara yazmak için)
    try {
      const fs = require('fs');
      const path = require('path');
      const saPath = path.join(__dirname, 'service-account.json');
      if (fs.existsSync(saPath)) {
        const saJson = JSON.parse(fs.readFileSync(saPath, 'utf8'));
        const saAuth = new google.auth.JWT({
          email: saJson.client_email,
          key: saJson.private_key,
          scopes: [
            'https://www.googleapis.com/auth/drive',
            'https://www.googleapis.com/auth/drive.file',
            'https://www.googleapis.com/auth/spreadsheets',
          ],
        });
        await saAuth.authorize();
        saSheetsClient = google.sheets({ version: 'v4', auth: saAuth });
        saEmail = saJson.client_email;
        console.log(`✅ SA Sheets client oluşturuldu: ${saEmail}`);

        if (!auth) {
          auth = saAuth;
          console.log('✅ Google Drive: Service Account (JWT) — ana auth olarak atandı');
        }
      } else {
        console.warn('⚠️ service-account.json bulunamadı, ADC fallback deneniyor...');
        // ADC fallback
        const { GoogleAuth } = google.auth;
        const googleAuth = new GoogleAuth({
          scopes: [
            'https://www.googleapis.com/auth/drive',
            'https://www.googleapis.com/auth/drive.file',
            'https://www.googleapis.com/auth/spreadsheets',
          ],
        });
        const saAuthFallback = await googleAuth.getClient();
        saSheetsClient = google.sheets({ version: 'v4', auth: saAuthFallback });
        if (!auth) {
          auth = saAuthFallback;
          console.log('✅ Google Drive: Service Account (ADC fallback)');
        }
      }
    } catch (error) {
      console.warn('⚠️ SA client oluşturulamadı:', error.message);
      if (!auth) {
        console.error('❌ Google Drive kimlik bilgileri bulunamadı!');
        driveClient = null;
        return;
      }
    }

    if (auth) {
      try {
        let clientEmail = 'unknown';
        if (typeof auth.getCredentials === 'function') {
          const credentials = await auth.getCredentials();
          clientEmail = credentials.client_email || (auth.jsonContent && auth.jsonContent.client_email) || 'unknown';
        } else if (auth.credentials && auth.credentials.client_email) {
          clientEmail = auth.credentials.client_email;
        }
        console.log(`🔍 [DEBUG] Drive auth: ${clientEmail}`);
        // SA (ADC) kullanıyorsak ve henüz serviceAccountEmail atanmamışsa, SA e-postasını ata
        if (!isOAuth2Client && clientEmail !== 'unknown') {
          serviceAccountEmail = clientEmail;
          console.log(`📧 Excel düzenleme izni verilecek e-posta (SA): ${serviceAccountEmail}`);
        }
        // OAuth2 (Refresh Token) kullanıyorsak serviceAccountEmail zaten line 292'de atandı, üzerine yazma!
        console.log(`📧 [DEBUG] serviceAccountEmail sonuç: ${serviceAccountEmail}`);
      } catch (logError) {
        console.warn('⚠️ [DEBUG] Client email alınamadı:', logError.message);
      }
    }

    if (auth) {
      driveAuth = auth;
      driveClient = google.drive({ version: 'v3', auth });
      sheetsClient = google.sheets({ version: 'v4', auth }); // Sheets client'ı bir kez oluştur
      console.log('✅ Google Drive ve Sheets clientları başarıyla başlatıldı');
    } else {
      driveClient = null;
      sheetsClient = null;
      console.log('⚠️  Google Drive client başlatılamadı');
    }
  } catch (error) {
    console.error('❌ Google Drive client başlatma hatası:', error.message);
    driveClient = null;
  }
}

// Uygulama başlatıldığında Drive client'ı initialize et
// initializeDriveClient(); // Request anında lazy load yapacağız

// Health check endpoint
app.get('/health', async (req, res) => {
  // Service Account Email'i bulmaya çalış
  let currentServiceAccount = process.env.GOOGLE_SERVICE_ACCOUNT_EMAIL || 'Bilinmiyor (Env var yok)';

  if (!driveClient) await initializeDriveClient();

  if (driveAuth) {
    if (driveAuth.email) {
      currentServiceAccount = driveAuth.email;
    } else if (driveAuth.getCredentials) {
      try {
        const creds = await driveAuth.getCredentials();
        if (creds.client_email) currentServiceAccount = creds.client_email;
      } catch (e) {
        console.error('Credentials alma hatası:', e);
      }
    } else if (driveAuth.jsonContent && driveAuth.jsonContent.client_email) {
      currentServiceAccount = driveAuth.jsonContent.client_email;
    }
  }

  const excelReady = !!(driveClient && sheetsClient);
  res.json({
    status: 'ok',
    message: 'Backend çalışıyor',
    service: 'Expense Tracker Backend',
    version: '1.0.1',
    platform: 'Firebase Cloud Functions',
    excelReady,
    serviceAccountEmail: currentServiceAccount,
    driveAuthType: isOAuth2Client ? 'oauth2' : 'service_account',
    config: {
      sheetsFolderId: process.env.GOOGLE_SHEETS_FOLDER_ID ? 'SET' : 'NOT SET',
      fixedExpensesId: process.env.GOOGLE_SHEETS_FIXED_EXPENSES_ID ? 'SET' : 'NOT SET',
      apiKey: process.env.GOOGLE_API_KEY ? 'SET' : 'NOT SET',
      clientId: process.env.GOOGLE_CLIENT_ID ? 'SET' : 'NOT SET',
      clientSecret: process.env.GOOGLE_CLIENT_SECRET ? 'SET' : 'NOT SET',
      refreshToken: process.env.GOOGLE_REFRESH_TOKEN ? 'SET' : 'NOT SET',
    },
    endpoints: {
      health: '/health',
      upload: '/upload (POST)',
      delete: '/delete (POST)',
      fixedExpenses: '/?endpoint=fixed-expenses (GET)',
      fileInfo: '/?fileId=... (GET)',
      initSheets: '/?endpoint=init-sheets (POST)',
    },
  });
});


// Firebase Cloud Functions'ta istek gövdesi bazen önceden buffer'lanır; Multer stream beklediği için
// "Unexpected end of form" hatası verir. Bu yüzden multipart için önce body'yi buffer'a alıp
// busboy ile parse ediyoruz.
function bufferUploadBody(req, res, next) {
  const contentType = req.headers['content-type'] || '';
  if (!contentType.includes('multipart/form-data')) {
    return res.status(400).json({ error: 'Dosya alınamadı', message: 'Content-Type: multipart/form-data gerekli.' });
  }
  // Bazı ortamlar (Firebase vb.) body'yi zaten req.rawBody olarak verir
  if (req.rawBody && Buffer.isBuffer(req.rawBody)) {
    return next();
  }
  const chunks = [];
  let totalSize = 0;
  req.on('data', (chunk) => {
    totalSize += chunk.length;
    if (totalSize > MAX_FILE_SIZE) {
      req.destroy();
      return res.status(400).json({ error: 'Dosya alınamadı', message: 'Dosya boyutu 50MB sınırını aşıyor.' });
    }
    chunks.push(chunk);
  });
  req.on('end', () => {
    req.rawBody = Buffer.concat(chunks);
    next();
  });
  req.on('error', (err) => {
    console.error('Upload body read error:', err);
    if (!res.headersSent) {
      res.status(400).json({ error: 'Dosya alınamadı', message: err.message || 'İstek gövdesi okunamadı.' });
    }
  });
}

function parseMultipartWithBusboy(req, res, next) {
  if (!req.rawBody || !(req.rawBody instanceof Buffer)) {
    return res.status(400).json({ error: 'Dosya alınamadı', message: 'Unexpected end of form' });
  }
  req.body = {};
  req.file = null;
  const bb = Busboy({ headers: req.headers, limits: { fileSize: MAX_FILE_SIZE } });
  bb.on('file', (fieldname, fileStream, info) => {
    const { filename, mimeType } = info;
    const chunks = [];
    fileStream.on('data', (d) => chunks.push(d));
    fileStream.on('end', () => {
      req.file = {
        buffer: Buffer.concat(chunks),
        originalname: filename || 'file',
        mimetype: mimeType || 'application/octet-stream',
      };
    });
    fileStream.on('error', (err) => {
      console.error('Busboy file stream error:', err);
    });
  });
  bb.on('field', (name, value) => {
    req.body[name] = value;
  });
  bb.on('finish', () => next());
  bb.on('error', (err) => {
    console.error('Busboy error:', err);
    if (!res.headersSent) {
      res.status(400).json({ error: 'Dosya alınamadı', message: err.message || 'Form parse hatası.' });
    }
  });
  bb.end(req.rawBody);
}

// Upload endpoint - busboy ile multipart parse (Firebase'de Multer stream sorunu için)
app.post('/upload', bufferUploadBody, parseMultipartWithBusboy, async (req, res) => {
  try {
    if (!driveClient) await initializeDriveClient();
    if (!req.file) {
      return res.status(400).json({ error: 'Dosya bulunamadı' });
    }

    if (!driveClient) {
      return res.status(500).json({
        error: 'Google Drive client başlatılamadı',
        message: 'Service Account kimlik bilgileri bulunamadı.',
        solution: 'Firebase Functions secrets: GOOGLE_SERVICE_ACCOUNT_EMAIL, GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY',
      });
    }

    const file = req.file;
    const ownerId = req.body.ownerId || 'unknown';
    const entryType = (req.body.entryType || 'expense').toLowerCase();

    // Hedef klasör: GOOGLE_DRIVE_ROOT_FOLDER_ID (maliyet-app) varsa ilgili alt klasöre, yoksa tek klasöre
    let driveFolderId;
    const rootId = getGoogleDriveRootFolderId();
    if (rootId) {
      const subfolderName = UPLOAD_SUBFOLDER_BY_ENTRY_TYPE[entryType] || UPLOAD_SUBFOLDER_BY_ENTRY_TYPE.expense;
      driveFolderId = await getOrCreateSubfolderId(driveClient, rootId, subfolderName);
      console.log(`Dosya yükleme: ${file.originalname}, entryType=${entryType} → ${subfolderName} (${driveFolderId})`);
    } else {
      driveFolderId = process.env.GOOGLE_DRIVE_FOLDER_ID || getGoogleSheetsFolderId();
    }
    if (!driveFolderId) {
      return res.status(500).json({
        error: 'Klasör ayarı eksik',
        message: 'GOOGLE_DRIVE_ROOT_FOLDER_ID (maliyet-app) veya GOOGLE_DRIVE_FOLDER_ID veya GOOGLE_SHEETS_FOLDER_ID tanımlı olmalı.',
      });
    }

    const ownerNameRaw = (req.body.ownerName || 'Kullanici').trim();
    const ownerNameNormalized = normalizeTurkishCharacters(ownerNameRaw);
    const ownerName = ownerNameNormalized.replace(/[^\w\s\-.]/g, '_').replace(/\s+/g, '_').slice(0, 40) || 'Kullanici';

    const amount = req.body.amount != null ? Number(req.body.amount) : 0;

    const descriptionRaw = (req.body.description || '').trim();
    const descriptionNormalized = normalizeTurkishCharacters(descriptionRaw);
    const description = descriptionNormalized.replace(/[^\w\s\-.,]/g, ' ').replace(/\s+/g, '_').slice(0, 30) || 'belge';

    const ext = (file.originalname && file.originalname.includes('.')) ? file.originalname.split('.').pop().toLowerCase() : 'pdf';

    let typeLabel = entryType === 'income' ? 'Gelir' : entryType === 'tax_deductible' ? 'Vergi' : 'Maliyet';
    typeLabel = normalizeTurkishCharacters(typeLabel);

    const dateStr = new Date().toISOString().slice(0, 10);
    const safeName = `${ownerName}_${typeLabel}_${amount}TL_${description}_${dateStr}.${ext}`.replace(/\.+/g, '.');

    console.log(`Dosya yükleme başlatıldı: ${file.originalname} → Drive adı: ${safeName}, Owner: ${ownerId}`);

    const fileMetadata = {
      name: safeName,
      parents: [driveFolderId],
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

    // Web view link'i al
    const fileInfo = await driveClient.files.get({
      fileId: fileId,
      fields: 'webViewLink',
    });

    res.json({
      fileId: fileId,
      fileUrl: fileUrl,
      webViewLink: fileInfo.data.webViewLink || fileUrl,
    });
  } catch (error) {
    console.error('Upload hatası:', error);
    if (res.headersSent) return;

    const errMsg = error.message || '';
    const errReason = error.errors && error.errors[0] ? error.errors[0].reason : '';
    const isQuota = errMsg.includes('quota') || errReason === 'storageQuotaExceeded';

    let errorMessage = errMsg || 'Bilinmeyen hata';
    let solution = '';

    if (errMsg.includes('No key or keyFile set')) {
      errorMessage = 'Google Drive kimlik bilgileri bulunamadı';
      solution = 'Firebase secrets: GOOGLE_SERVICE_ACCOUNT_EMAIL, GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY';
    } else if (errMsg.includes('permission')) {
      errorMessage = 'Google Drive izin hatası';
      solution = "Service Account'a Drive klasörüne yazma izni verin";
    } else if (isQuota) {
      errorMessage = 'Google Drive kotası aşıldı';
      solution = isOAuth2Client
        ? 'Drive depolama alanını kontrol edin (OAuth hesabı kullanılıyor).'
        : "Backend şu an Service Account kullanıyor (Drive kotası yok). GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET ve GOOGLE_REFRESH_TOKEN secret'larını doğru ayarlayıp yeniden deploy edin; böylece kendi Drive kotanız kullanılır.";
      console.warn('Kota hatası – driveAuthType:', isOAuth2Client ? 'oauth2' : 'service_account');
    }

    res.status(500).json({
      error: 'Dosya yükleme başarısız',
      message: errorMessage,
      solution: solution || 'Firebase Console > Functions > Logs',
    });
  }
});

// GET endpoint - Google Sheets okuma ve dosya bilgisi alma
app.get('/', async (req, res) => {
  if (!driveClient) await initializeDriveClient(); // Lazy init
  try {
    const endpoint = req.query.endpoint;
    const fileId = req.query.fileId;

    // Dosya bilgisi alma endpoint'i
    if (fileId) {
      if (!driveClient) {
        return res.status(500).json({
          error: 'Google Drive client başlatılamadı',
          message: 'Service Account kimlik bilgileri bulunamadı.',
        });
      }

      try {
        const fileResp = await driveClient.files.get({
          fileId: fileId,
          fields: 'id,name,mimeType,webViewLink,webContentLink',
          supportsAllDrives: true,
        });

        const fileData = fileResp.data;
        console.log('File info:', fileData.name);

        return res.json({
          fileId: fileData.id,
          name: fileData.name,
          mimeType: fileData.mimeType,
          webViewLink: fileData.webViewLink,
          webContentLink: fileData.webContentLink,
          directDownloadLink: `https://drive.google.com/uc?export=download&id=${fileData.id}`,
        });
      } catch (error) {
        console.error('File info error:', error);
        return res.status(500).json({
          error: 'Dosya bulunamadı',
          detail: error.message,
        });
      }
    }

    // Google Sheets'ten sabit giderleri okuma — sadece tek dosyadan (GOOGLE_SHEETS_FIXED_EXPENSES_ID)
    if (endpoint === 'fixed-expenses') {
      const apiKey = process.env.GOOGLE_API_KEY;
      const sheetId = getGoogleSheetsFixedExpensesId();
      if (!apiKey || !sheetId) {
        return res.status(500).json({
          error: 'Sabit giderler ayarı eksik',
          message: 'GOOGLE_API_KEY ve GOOGLE_SHEETS_FIXED_EXPENSES_ID (veya varsayılan) gerekli.',
          expenses: [],
        });
      }
      try {
        let values = [];
        let sheetName = 'Sheet1';

        // Önce Sheets API ile dene (native Google Sheets dosyaları için)
        let sheetsApiWorked = false;
        const metaResp = await fetch(`${GOOGLE_SHEETS_API}/${sheetId}?key=${apiKey}`);
        if (metaResp.ok) {
          const meta = await metaResp.json();
          let sheetsList = [];
          if (meta.sheets && meta.sheets.length > 0) {
            sheetsList = meta.sheets.map(s => s.properties?.title || 'Unknown');
          }

          let bestSheet = sheetsList[0] || 'Sheet1';
          let maxRows = -1;

          for (const sName of sheetsList) {
            try {
              const r = `'${sName.replace(/'/g, "''")}'!A1:A50`;
              const dResp = await fetch(`${GOOGLE_SHEETS_API}/${sheetId}/values/${encodeURIComponent(r)}?key=${apiKey}`);
              if (dResp.ok) {
                const d = await dResp.json();
                const rowCount = d.values ? d.values.length : 0;
                console.log(`ℹ️ [fixed-expenses] Sheet candidate "${sName}" rows: ${rowCount}`);
                const isExcellentMatch = sName.toLowerCase() === 'sabit giderler';
                const isGoodMatch = sName.toLowerCase().includes('gider') || sName.toLowerCase().includes('sabit');
                if (rowCount > maxRows) { maxRows = rowCount; bestSheet = sName; }
                else if (rowCount === maxRows && (isExcellentMatch || isGoodMatch)) { bestSheet = sName; }
              }
            } catch (e) {
              console.error(`❌ [fixed-expenses] Failed to check sheet "${sName}":`, e.message);
            }
          }

          sheetName = bestSheet;
          console.log(`🎯 [fixed-expenses] Final choice: "${sheetName}" with ~${maxRows} rows.`);

          const range = `'${sheetName.replace(/'/g, "''")}'!A1:Z1000`;
          const dataResp = await fetch(`${GOOGLE_SHEETS_API}/${sheetId}/values/${encodeURIComponent(range)}?key=${apiKey}`);
          if (dataResp.ok) {
            const data = await dataResp.json();
            values = data.values || [];
            sheetsApiWorked = true;
          } else {
            console.warn('[fixed-expenses] Sheets API values okunamadı:', dataResp.status);
          }
        } else {
          console.warn('[fixed-expenses] Sheets API metadata okunamadı (muhtemelen xlsx dosyası):', metaResp.status);
        }

        // Sheets API çalışmadıysa CSV export ile dene (xlsx dosyaları için)
        if (!sheetsApiWorked) {
          console.log('[fixed-expenses] CSV export fallback deneniyor...');
          const csvUrl = `https://docs.google.com/spreadsheets/d/${sheetId}/export?format=csv`;
          const csvResp = await fetch(csvUrl);
          if (csvResp.ok) {
            const csvText = await csvResp.text();
            const lines = csvText.split('\n').map(line => {
              const result = [];
              let current = '';
              let inQuotes = false;
              for (let i = 0; i < line.length; i++) {
                const ch = line[i];
                if (ch === '"') { inQuotes = !inQuotes; }
                else if (ch === ',' && !inQuotes) { result.push(current.trim()); current = ''; }
                else { current += ch; }
              }
              result.push(current.trim());
              return result;
            }).filter(row => row.some(cell => cell.length > 0));
            values = lines;
            sheetName = 'CSV Export';
            console.log(`✅ [fixed-expenses] CSV export başarılı: ${values.length} satır`);
          } else {
            console.error('[fixed-expenses] CSV export de başarısız:', csvResp.status);
            return res.json({ expenses: [] });
          }
        }
        console.log(`📊 [fixed-expenses] Sheet parsed: "${sheetName}", total rows: ${values.length}`);


        const allExpenses = [];
        let startRow = 0;
        let isStandardFixedSheet = false;

        if (values.length > 0) {
          const firstRowStr = values[0].map(v => String(v).toLowerCase()).join('|');
          if (firstRowStr.includes('tarih') || firstRowStr.includes('açıklama') || firstRowStr.includes('tutar') || firstRowStr.includes('gider kalemi')) {
            startRow = 1;
            isStandardFixedSheet = true;
          }
        }

        console.log(`ℹ️ [fixed-expenses] Parsing startRow: ${startRow}, isStandardFixedSheet: ${isStandardFixedSheet}`);

        for (let i = startRow; i < values.length; i++) {
          const row = values[i];
          if (!row || row.length < 2) continue;

          let category = null;
          let description = '';
          let amountStr = '0';
          let ownerName = 'Sistem';
          let recurrence = 'monthly';
          let isActive = true;
          let notes = null;
          let dateVal = row[0];

          let yearlyAmount = null;
          if (isStandardFixedSheet) {
            category = row[1] ? String(row[1]).trim() : null;
            const col2 = row[2] ? String(row[2]).trim() : '';
            const col3 = row[3] ? String(row[3]).trim() : '';
            const col2Num = col2.replace(/[^\d.,-]/g, '').replace(',', '.');
            const col3Num = col3.replace(/[^\d.,-]/g, '').replace(',', '.');

            const hasAylikYillik = row.length >= 4 && !isNaN(parseFloat(col3Num)) && col3Num !== '';
            if (hasAylikYillik) {
              description = row[1] ? String(row[1]).trim() : '';
              amountStr = col3Num;
              yearlyAmount = parseFloat(col2Num) || null;
            } else {
              description = row.length > 2 ? col2 : (row[1] ? String(row[1]).trim() : '');
              if (row.length > 3 && !isNaN(parseFloat(col3Num)) && col3Num !== '') amountStr = col3Num;
              else if (col2 && !isNaN(parseFloat(col2Num)) && col2Num !== '') amountStr = col2Num;
            }
            ownerName = row[4] ? String(row[4]).trim() : 'Sistem';
            recurrence = row[5] ? String(row[5]).trim().toLowerCase() : 'monthly';
            isActive = row[6] ? String(row[6]).toLowerCase().includes('aktif') : true;
            notes = row[7] ? String(row[7]).trim() : null;
          } else {
            // Non-standard sheet (like "Sayfa1" with regular data)
            // Column 0: Date, 1: Category, 2: Description, 3: Amount, 4: Owner
            category = row[1] ? String(row[1]).trim() : null;
            description = row[2] ? String(row[2]).trim() : (row[1] ? String(row[1]).trim() : '');
            amountStr = row[3] ? String(row[3]).trim().replace(/[^\d.,-]/g, '').replace(',', '.') : '0';
            ownerName = row[4] ? String(row[4]).trim() : 'Sistem';
          }

          if (!description && !category) {
            console.log(`⚠️ [fixed-expenses] Row ${i} skipped: Empty. Data:`, JSON.stringify(row));
            continue;
          }

          if (!description) description = category || 'İsimsiz Gider';

          const amount = parseFloat(amountStr) || 0;
          let createdAt = new Date().toISOString();

          if (dateVal) {
            try {
              const dParts = String(dateVal).trim().split('.');
              if (dParts.length === 3) {
                const day = parseInt(dParts[0], 10);
                const month = parseInt(dParts[1], 10);
                const year = parseInt(dParts[2], 10);
                if (!isNaN(day) && !isNaN(month) && !isNaN(year)) {
                  createdAt = new Date(year, month - 1, day).toISOString();
                }
              } else {
                const parsedDate = new Date(dateVal);
                if (!isNaN(parsedDate.getTime())) {
                  createdAt = parsedDate.toISOString();
                }
              }
            } catch (e) {
              console.warn(`⚠️ [fixed-expenses] Row ${i} date parse error:`, e.message);
            }
          }

          const expenseObj = {
            id: `sheet_${sheetId.substring(0, 8)}_${i}`,
            ownerId: 'system',
            ownerName,
            description,
            amount,
            category,
            recurrence,
            isActive,
            notes,
            createdAt,
          };
          if (yearlyAmount != null) expenseObj.yearlyAmount = yearlyAmount;
          allExpenses.push(expenseObj);
        }
        console.log(`✅ Sabit giderler: ${allExpenses.length} kalem (Kaynak: ${sheetName})`);
        return res.json({ expenses: allExpenses });
      } catch (e) {
        console.error('fixed-expenses hatası:', e.message);
        return res.status(500).json({ error: 'Sabit giderler okunamadı', message: e.message, expenses: [] });
      }
    }

    // Fuarlar listesi (Google Sheet: Tarih, Yer, Fuar Adı, Website)
    if (endpoint === 'fuarlar') {
      if (!process.env.GOOGLE_API_KEY || !process.env.GOOGLE_SHEETS_FUARLAR_ID) {
        return res.status(500).json({
          error: 'Fuarlar ayarı eksik',
          message: 'GOOGLE_SHEETS_FUARLAR_ID ve GOOGLE_API_KEY tanımlı olmalı.',
        });
      }
      try {
        const fuarlar = await fetchFuarlarList();
        console.log(`✅ Fuarlar: ${fuarlar.length} kayıt`);
        return res.json({ fuarlar });
      } catch (err) {
        console.error('Fuarlar endpoint hatası:', err);
        return res.status(500).json({ error: 'Fuarlar okunamadı', message: err.message, fuarlar: [] });
      }
    }

    // Root endpoint - bilgi döndür
    res.json({
      service: 'Expense Tracker Backend',
      status: 'running',
      version: '1.0.0',
      platform: 'Firebase Cloud Functions',
      endpoints: {
        health: '/health',
        upload: '/upload (POST)',
        delete: '/delete (POST)',
        fixedExpenses: '/?endpoint=fixed-expenses (GET)',
        fuarlar: '/?endpoint=fuarlar (GET)',
        fileInfo: '/?fileId=... (GET)',
        initSheets: '/?endpoint=init-sheets (POST)',
      },
    });
  } catch (error) {
    console.error('GET endpoint error:', error);
    if (!res.headersSent) {
      res.status(500).json({
        error: 'Backend hatası',
        message: error.message || 'Sunucu işlenirken bir hata oluştu.',
      });
    }
  }
});

// DELETE endpoint - Dosya silme
app.post('/delete', async (req, res) => {
  if (!driveClient) await initializeDriveClient(); // Lazy init
  try {
    if (!driveClient) {
      return res.status(500).json({
        error: 'Google Drive client başlatılamadı',
        message: 'Service Account kimlik bilgileri bulunamadı.',
      });
    }

    const { fileId } = req.body;

    if (!fileId) {
      return res.status(400).json({
        error: 'fileId gerekli',
        message: 'Silinecek dosyanın ID\'si gönderilmelidir.',
      });
    }

    try {
      await driveClient.files.delete({
        fileId: fileId,
        supportsAllDrives: true,
      });

      console.log(`Dosya silindi: ${fileId}`);
      return res.json({
        success: true,
        message: 'Dosya başarıyla silindi',
        fileId: fileId,
      });
    } catch (error) {
      console.error('Delete error:', error);

      if (error.code === 404) {
        return res.status(404).json({
          error: 'Dosya bulunamadı',
          message: 'Dosya zaten silinmiş olabilir.',
        });
      }

      return res.status(500).json({
        error: 'Dosya silme hatası',
        message: error.message,
      });
    }
  } catch (error) {
    console.error('Delete endpoint error:', error);
    if (!res.headersSent) {
      res.status(500).json({
        error: 'Backend hatası',
        message: error.message || 'Sunucu işlenirken bir hata oluştu.',
      });
    }
  }
});

// POST endpoint - Google Sheets oluşturma/güncelleme
app.post('/', async (req, res) => {
  if (!driveClient) await initializeDriveClient(); // Lazy init
  try {
    const endpoint = req.query.endpoint;

    // Ön hazırlık (prewarm) - production'da 200 dön, gerçek prewarm opsiyonel
    if (endpoint === 'prewarm-sheets') {
      if (!driveClient) await initializeDriveClient();
      if (driveClient && sheetsClient) {
        try {
          const prewarmBody = req.body && typeof req.body === 'object' ? req.body : {};
          const { ownerName } = prewarmBody;
          const sheetNames = [
            ownerName ? `${ownerName} Eklediklerim.csv` : 'Eklediklerim.csv',
            'Tum Eklenenler.csv',
            'Ortak Gelirleri.csv',
            'Sabit Giderler',
          ];
          const results = [];
          const sheetsFolderId = driveClient ? await getSheetsFolderIdForInit(driveClient) : getGoogleSheetsFolderId();
          for (const name of sheetNames) {
            const cleanName = name.replace(/\.(xlsx|csv)$/i, '');
            if (spreadsheetCache[cleanName]) {
              results.push({ name: cleanName, status: 'cached', id: spreadsheetCache[cleanName] });
              continue;
            }
            try {
              const wantNorm = normalizeSheetName(cleanName);
              if (FIXED_SHEET_IDS[wantNorm]) {
                spreadsheetCache[cleanName] = FIXED_SHEET_IDS[wantNorm];
                results.push({ name: cleanName, status: 'fixed', id: FIXED_SHEET_IDS[wantNorm] });
                continue;
              }
              const q = `name='${cleanName.replace(/'/g, "\\'")}' and '${sheetsFolderId}' in parents and trashed=false and mimeType='application/vnd.google-apps.spreadsheet'`;
              const list = await driveClient.files.list({ q, fields: 'files(id,name)', supportsAllDrives: true });
              if (list.data.files && list.data.files.length > 0) {
                const sid = list.data.files[0].id;
                spreadsheetCache[cleanName] = sid;
                results.push({ name: cleanName, status: 'found', id: sid });
              } else {
                results.push({ name: cleanName, status: 'skipped' });
              }
            } catch (e) {
              results.push({ name: cleanName, status: 'error', error: e.message });
            }
          }
          return res.json({ success: true, results });
        } catch (err) {
          console.warn('Prewarm error:', err.message);
        }
      }
      return res.json({ success: true, message: 'Prewarm skipped or no credentials' });
    }

    // Google Sheets oluşturma/güncelleme endpoint'i
    if (endpoint === 'init-sheets') {
      const body = req.body && typeof req.body === 'object' ? req.body : {};
      const driveAccessToken = body.driveAccessToken;
      let activeDrive = driveClient;
      let activeSheets = sheetsClient;
      let oauthUserEmail = null;

      if (driveAccessToken) {
        try {
          const oauth2Client = new google.auth.OAuth2();
          oauth2Client.setCredentials({ access_token: driveAccessToken });
          activeDrive = google.drive({ version: 'v3', auth: oauth2Client });
          activeSheets = google.sheets({ version: 'v4', auth: oauth2Client });
          console.log('📱 Kullanıcı Drive token kullanılıyor (OAuth) - dosyalar kullanıcının kotasında');
          try {
            const userinfoRes = await fetch('https://www.googleapis.com/oauth2/v2/userinfo', {
              headers: { Authorization: `Bearer ${driveAccessToken}` },
            });
            if (userinfoRes.ok) {
              const userinfo = await userinfoRes.json();
              oauthUserEmail = userinfo.email || null;
              if (oauthUserEmail) console.log(`📧 Excel düzenleme izni verilecek e-posta (OAuth kullanıcı): ${oauthUserEmail}`);
            }
          } catch (e) {
            console.warn('OAuth userinfo alınamadı (e-posta loglanamadı):', e.message);
          }
        } catch (err) {
          console.warn('OAuth client oluşturulamadı, SA kullanılacak:', err.message);
        }
      }

      if (!activeDrive || !activeSheets) {
        return res.status(500).json({
          error: 'Google Drive client başlatılamadı',
          message: driveAccessToken ? 'Drive token geçersiz veya süresi dolmuş. Ayarlardan tekrar bağlanın.' : 'Service Account kimlik bilgileri bulunamadı.',
        });
      }

      try {
        const entries = Array.isArray(body.entries) ? body.entries : [];
        const deletedEntries = Array.isArray(body.deletedEntries) ? body.deletedEntries : [];
        const fixedExpenses = Array.isArray(body.fixedExpenses) ? body.fixedExpenses : [];
        const sheetName = typeof body.sheetName === 'string' ? body.sheetName : 'Giderler';
        const allData = [...entries, ...fixedExpenses];

        // Excel klasörü: Kullanıcı token (activeDrive) varsa onu kullan (kullanıcı bazlı kota/dosya), yoksa SA (driveClient) kullan
        const driveForFolder = activeDrive || driveClient;
        const sheetsFolderId = await getSheetsFolderIdForInit(driveForFolder);

        // Google Sheets için veri hazırla
        let headers = [];
        // 2. Verileri hazırla (Normalize edilmiş helper'ı kullan)
        const isEntry = entries.length > 0;
        const values = prepareSheetValues(isEntry ? entries : fixedExpenses, !isEntry);

        let cleanSheetName = sheetName.replace(/\.(xlsx|csv)$/i, '');
        cleanSheetName = normalizeTurkishCharacters(cleanSheetName);
        const wantNorm = cleanSheetName.trim().toLowerCase();
        console.log(`📁 [init-sheets] sheetName: "${cleanSheetName}", sheetsFolderId: ${sheetsFolderId || '(yok)'}, entries: ${entries.length}, fixedExpenses: ${fixedExpenses.length}, toplam satır: ${values.length - 1}`);

        // Önce mevcut dosyayı kontrol et (L1: Memory Cache)
        let spreadsheetId = spreadsheetCache[cleanSheetName];

        // L0: Sabit Excel eşlemesi (kullanıcının verdiği linkler) — öncelikli, liste/oluşturma yok
        if (!spreadsheetId && FIXED_SHEET_IDS[wantNorm]) {
          spreadsheetId = FIXED_SHEET_IDS[wantNorm];
          spreadsheetCache[cleanSheetName] = spreadsheetId;
          console.log(`📌 Sabit eşleşme: "${cleanSheetName}" → ${spreadsheetId}, yazılacak satır: ${values.length - 1}`);
        }

        console.log(`Processing sheet: ${cleanSheetName}, Cached ID: ${spreadsheetId || 'None'}, entries: ${entries.length}`);

        // Sabit tablolarda (ortak gelirleri, vergiden düşülecekler) tek sekme "Sayfa1" — önce doğrudan Sayfa1'e yaz
        // Sabit tablolara SA ile yaz (tablolar SA ile paylaşıldığı için, SA yeni dosya oluşturmaz sadece günceller)
        // Kullanıcı dosyaları (kişisel eklediklerim vb.) için kullanıcı token'ı kullan
        const isFixedSheet = !!spreadsheetId && FIXED_SHEET_IDS[wantNorm] === spreadsheetId;
        const sheetsForUpdate = isFixedSheet && saSheetsClient ? saSheetsClient : (activeSheets || sheetsClient);
        const writingWithSa = sheetsForUpdate === saSheetsClient;
        const writingEmail = writingWithSa ? (saEmail || serviceAccountEmail) : (oauthUserEmail || serviceAccountEmail || 'OAuth Kullanıcısı');

        console.log(`📧 [init-sheets] İşlem yapacak hesap: ${writingEmail} (Tip: ${writingWithSa ? 'Service Account' : 'OAuth User'}, Sabit Tablo: ${isFixedSheet ? 'EVET' : 'HAYIR'})`);
        const getFirstSheetName = async (sid) => {
          try {
            const meta = await sheetsForUpdate.spreadsheets.get({ spreadsheetId: sid });
            const sheets = meta.data.sheets || [];
            if (sheets.length > 0 && sheets[0].properties && sheets[0].properties.title) {
              const name = sheets[0].properties.title;
              console.log(`📄 İlk sayfa adı (${sid}): "${name}"`);
              return name;
            }
          } catch (e) {
            console.warn('Sheet adı alınamadı (spreadsheets.get):', e.message);
          }
          return 'Sheet1';
        };

        // Helper function for updating sheet data (activeSheets = kullanıcı token veya SA)
        const updateSheetData = async (sid, targetSheetName) => {
          let actualSheetName = targetSheetName || 'Sheet1';
          try {
            // 1. Sayfa var mı kontrol et veya oluştur
            const ssMeta = await sheetsForUpdate.spreadsheets.get({ spreadsheetId: sid });
            const sheets = ssMeta.data.sheets || [];
            const sheetExists = sheets.some(s => s.properties.title === actualSheetName);

            if (!sheetExists) {
              console.log(`🆕 Yeni sayfa oluşturuluyor: "${actualSheetName}" (${sid})`);
              await sheetsForUpdate.spreadsheets.batchUpdate({
                spreadsheetId: sid,
                requestBody: {
                  requests: [{ addSheet: { properties: { title: actualSheetName } } }]
                }
              });
            }

            console.log(`📌 Hedef sayfa: "${actualSheetName}" (${sid})`);

            // 2. Sayfayı TAMAMEN temizle (silinenlerin satırları kalmasın)
            // Sadece sayfa adını range olarak vermek tüm içeriği temizler
            const fullSheetRange = actualSheetName.indexOf(' ') >= 0 || actualSheetName.includes("'") ? `'${actualSheetName.replace(/'/g, "''")}'` : actualSheetName;
            try {
              await sheetsForUpdate.spreadsheets.values.clear({
                spreadsheetId: sid,
                range: fullSheetRange,
              });
              console.log(`🗑️ Sayfa temizlendi: "${actualSheetName}"`);
            } catch (clearErr) {
              console.warn(`⚠️ Sayfa temizleme hatası (devam ediliyor): ${clearErr.message}`);
            }

            // === Opsiyonel: Eski "Silinenler" sayfasını sil (kafa karışıklığını önlemek için) ===
            const deleteDeletedSheetIfExist = async (sid) => {
              try {
                const ss = await sheetsForUpdate.spreadsheets.get({ spreadsheetId: sid });
                const deletedSheet = ss.data.sheets.find(s => s.properties.title === 'Silinenler');
                if (deletedSheet) {
                  console.log(`🗑️ Eski "Silinenler" sayfası bulundu, siliniyor... (${sid})`);
                  await sheetsForUpdate.spreadsheets.batchUpdate({
                    spreadsheetId: sid,
                    requestBody: {
                      requests: [{ deleteSheet: { sheetId: deletedSheet.properties.sheetId } }]
                    }
                  });
                  console.log(`✅ "Silinenler" sayfası başarıyla silindi.`);
                }
              } catch (err) {
                console.warn(`⚠️ "Silinenler" sayfasını silme hatası (atlandı):`, err.message);
              }
            };

            // 3. Verileri yaz
            const writeRange = actualSheetName.indexOf(' ') >= 0 || actualSheetName.includes("'") ? `'${actualSheetName.replace(/'/g, "''")}'!A1` : `${actualSheetName}!A1`;
            await sheetsForUpdate.spreadsheets.values.update({
              spreadsheetId: sid,
              range: writeRange,
              valueInputOption: 'RAW',
              requestBody: { values: values },
            });
            await deleteDeletedSheetIfExist(sid);
            console.log(`✅ Sheet güncelleme başarılı: ${sid} (sayfa: ${actualSheetName}, ${values.length - 1} kayıt)`);

          } catch (err) {
            console.error(`❌ Sheet güncelleme hatası (${sid}):`, err.message);
            // Eğer hala hata alıyorsak (özellikle sayfa/range bulunamadıysa) son çare Sheet1 oluşturmayı dene
            if (err.message.includes('Unable to parse range') || err.message.includes('not found')) {
              try {
                console.log(`🔄 Son çare: Sheet1 oluşturuluyor...`);
                try {
                  await sheetsForUpdate.spreadsheets.batchUpdate({
                    spreadsheetId: sid,
                    requestBody: { requests: [{ addSheet: { properties: { title: 'Sheet1' } } }] }
                  });
                } catch (addErr) { /* Zaten varsa geç */ }

                await sheetsForUpdate.spreadsheets.values.update({
                  spreadsheetId: sid,
                  range: 'Sheet1!A1',
                  valueInputOption: 'RAW',
                  requestBody: { values: values },
                });
                console.log(`✅ Sheet1 üzerine yazıldı: ${sid}`);
              } catch (finalErr) {
                console.error(`❌ Kritik güncelleme hatası: ${finalErr.message}`);
                throw finalErr;
              }
            } else {
              throw err;
            }
          }
        };

        // === Silinenler sayfası (DEVRE DIŞI BIRAKILDI) ===
        const updateDeletedSheet = async (sid) => {
          // Bu fonksiyon artık kullanıcı talebiyle işlem yapmıyor.
          return;
        };


        if (spreadsheetId) {
          console.log(`🚀 Önbellekten kullanılıyor: ${spreadsheetId}. Senkronize güncelleniyor...`);

          await updateSheetData(spreadsheetId, cleanSheetName);
          // updateDeletedSheet(spreadsheetId) kaldırıldı.

          const previewUrl = `https://docs.google.com/spreadsheets/d/${spreadsheetId}/edit`;
          return res.json({
            success: true,
            url: previewUrl,
            fileId: spreadsheetId,
            rowCount: values.length - 1,
            message: 'Google Sheets güncellendi (Senkronize)',
          });
        }

        // Önbellekte yoksa: klasördeki TÜM spreadsheet'leri listele, sonra isim/alias ile eşleştir (yeni dosya oluşturma)
        let effectiveFolderId = sheetsFolderId;
        if (sheetsFolderId) {
          try {
            console.log(`🔍 Klasördeki tüm Excel/Sheets listeleniyor, aranan: ${cleanSheetName}`);
            const allSheets = await driveForFolder.files.list({
              q: `'${sheetsFolderId}' in parents and trashed=false and mimeType='application/vnd.google-apps.spreadsheet'`,
              fields: 'files(id, name)',
              supportsAllDrives: true,
              includeItemsFromAllDrives: true,
            });
            const files = allSheets.data.files || [];
            console.log(`🔍 Klasörde ${files.length} dosya bulundu: ${files.map(f => f.name).join(', ')}`);

            const wantNorm = normalizeSheetName(cleanSheetName);
            const aliases = SHEET_NAME_ALIASES[wantNorm] || [cleanSheetName];
            let matched = null;

            for (const f of files) {
              const fnorm = normalizeSheetName(f.name);
              if (fnorm === wantNorm || f.name === cleanSheetName) {
                matched = f;
                console.log(`🔍 Eşleşme (tam/normalize): "${cleanSheetName}" → "${f.name}"`);
                break;
              }
              if (aliases.some(a => a === f.name || normalizeSheetName(a) === fnorm)) {
                matched = f;
                console.log(`🔍 Eşleşme (alias): "${cleanSheetName}" → "${f.name}"`);
                break;
              }
            }

            if (matched) {
              spreadsheetId = matched.id;
              spreadsheetCache[cleanSheetName] = spreadsheetId;
              await updateSheetData(spreadsheetId, cleanSheetName);
              // updateDeletedSheet(spreadsheetId) kaldırıldı.
              const previewUrl = `https://docs.google.com/spreadsheets/d/${spreadsheetId}/edit`;
              return res.json({
                success: true,
                url: previewUrl,
                fileId: spreadsheetId,
                rowCount: values.length - 1,
                message: 'Google Sheets bulundu ve güncellendi',
              });
            }
          } catch (error) {
            console.warn('Klasör listeleme hatası:', error.message);
            if (error.message && (error.message.includes('File not found') || error.message.includes('404') || error.message.includes('not found'))) {
              effectiveFolderId = null;
            }
          }
        }

        // Bulunamadıysa oluştur: yeni kişi / yeni "X Eklediklerim" için klasörde dosya oluştur, ekledikleri bu dosyaya yazılır
        console.log(`🆕 Yeni dosya oluşturuluyor (kişi/ sayfa): ${cleanSheetName}, klasör: ${effectiveFolderId || '(root)'}`);
        let newFile;
        const createOpts = {
          requestBody: {
            name: cleanSheetName,
            mimeType: 'application/vnd.google-apps.spreadsheet',
            ...(effectiveFolderId ? { parents: [effectiveFolderId] } : {}),
          },
          fields: 'id',
          supportsAllDrives: true,
        };
        try {
          newFile = await driveForFolder.files.create(createOpts);
        } catch (createErr) {
          const msg = createErr.message || '';
          if (msg.includes('quota') || msg.includes('storage quota') || msg.includes('exceeded')) {
            console.error('Drive depolama kotası dolu (yeni kişi dosyası oluşturulamadı):', msg);
            return res.status(507).json({
              error: 'Google Drive depolama dolu',
              message: "Drive kotası aşıldı. Ayarlardan 'Google Drive Bağla' ile kendi hesabını bağlarsan senin kotan kullanılır.",
              code: 'QUOTA_EXCEEDED',
            });
          }
          if (effectiveFolderId && (msg.includes('File not found') || msg.includes('404') || msg.includes('not found') || msg.includes('403'))) {
            console.warn('Klasör erişilemedi, kökte oluşturuluyor:', msg);
            newFile = await driveForFolder.files.create({
              requestBody: { name: cleanSheetName, mimeType: 'application/vnd.google-apps.spreadsheet' },
              fields: 'id',
              supportsAllDrives: true,
            });
          } else {
            throw createErr;
          }
        }

        spreadsheetId = newFile.data.id;
        spreadsheetCache[cleanSheetName] = spreadsheetId;

        await updateSheetData(spreadsheetId, cleanSheetName);
        // updateDeletedSheet(spreadsheetId) kaldırıldı.

        try {
          await driveForFolder.permissions.create({
            fileId: spreadsheetId,
            requestBody: { role: 'reader', type: 'anyone' },
          });
        } catch (permErr) {
          console.warn('İzin ayarlama atlandı (dosya kullanıcı Drive\'ında olabilir):', permErr.message);
        }

        const previewUrl = `https://docs.google.com/spreadsheets/d/${spreadsheetId}/edit`;
        return res.json({
          success: true,
          url: previewUrl,
          fileId: spreadsheetId,
          rowCount: values.length - 1,
          message: 'Yeni Google Sheets oluşturuldu',
        });

      } catch (error) {
        console.error('Init sheets error:', error);
        const msg = (error.message || '').toLowerCase();
        if (msg.includes('quota') || msg.includes('storage quota') || msg.includes('exceeded')) {
          return res.status(507).json({
            error: 'Google Drive depolama dolu',
            message: "Drive depolama kotası aşıldı. Google Drive'da yer açın veya gereksiz dosyaları silin.",
            code: 'QUOTA_EXCEEDED',
          });
        }
        if (error.code === 403 || msg.includes('403') || msg.includes('forbidden') || msg.includes('permission')) {
          const requiredEmail = saEmail || serviceAccountEmail || null;
          return res.status(403).json({
            error: 'Tabloya yazma yetkisi yok',
            message: requiredEmail
              ? `Bu tabloya yazılamıyor. Google Sheet'te Paylaş'a tıklayıp "${requiredEmail}" adresini düzenleyici olarak ekleyin.`
              : 'Bu tabloya yazılamıyor. Ayarlardan "Google Drive Bağla" yapın veya tabloyu düzenleyici olarak paylaşın.',
            requiredEmail: requiredEmail,
          });
        }
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
    if (!res.headersSent) {
      res.status(500).json({
        error: 'Backend hatası',
        message: error.message || 'Sunucu işlenirken bir hata oluştu.',
      });
    }
  }
});

// Express uygulamasını Firebase Cloud Function olarak export et
// Firebase Functions v7+ için secrets'ları runtime config ile kullanıyoruz
// Secrets'lar process.env'e otomatik olarak eklenir
// Secrets configuration for V2
// Sadece mevcut olan secrets'ları ekle
// Tüm yakalanmamış hatalar JSON 500 dönsün (HTML Internal Server Error yerine)
app.use((err, req, res, next) => {
  console.error('Express uncaught error:', err);
  if (!res.headersSent) {
    res.status(500).json({
      error: 'Sunucu hatası',
      message: err.message || 'İstek işlenirken bir hata oluştu.',
    });
  }
});

// --- Google Sheets Senkronizasyon Helper Fonksiyonları ---

/** Google Sheets için veri hazırlar */
function prepareSheetValues(allData, isFixedExpense = false) {
  const values = [];
  if (isFixedExpense) {
    const headers = ['Tarih', 'Kategori', 'Aciklama', 'Tutar', 'Kisi', 'Tekrar', 'Durum', 'Notlar'];
    values.push(headers);
    for (const e of allData) {
      const dateStr = e.dateTime || e.startDate || e.createdAt || new Date().toISOString();
      values.push([
        dateStr,
        normalizeTurkishCharacters(e.category || ''),
        normalizeTurkishCharacters(e.description || ''),
        e.amount != null ? Number(e.amount) : 0,
        normalizeTurkishCharacters(e.ownerName || ''),
        normalizeTurkishCharacters(e.recurrence || ''),
        (e.isActive === false) ? 'Pasif' : 'Aktif',
        normalizeTurkishCharacters(e.notes || ''),
      ]);
    }
  } else {
    const headers = ['Tarih', 'Tur', 'Kategori', 'Aciklama', 'Tutar', 'Kisi', 'Notlar', 'Dosya Linki'];
    values.push(headers);
    for (const e of allData) {
      let typeLabel = e.entryType === 'income' ? 'Gelir' : e.entryType === 'tax_deductible' ? 'Vergi Dusulebilir' : 'Gider';
      const dateStr = e.dateTime || e.createdAt || '';
      values.push([
        dateStr,
        typeLabel,
        normalizeTurkishCharacters(e.category || ''),
        normalizeTurkishCharacters(e.description || ''),
        e.amount != null ? Number(e.amount) : 0,
        normalizeTurkishCharacters(e.ownerName || ''),
        normalizeTurkishCharacters(e.notes || ''),
        e.fileUrl || '',
      ]);
    }
  }
  return values;
}

/** İlk sayfa adını alır */
async function getFirstSheetName(sheetsClient, spreadsheetId) {
  try {
    const meta = await sheetsClient.spreadsheets.get({ spreadsheetId });
    const sheets = meta.data.sheets || [];
    if (sheets.length > 0 && sheets[0].properties && sheets[0].properties.title) {
      return sheets[0].properties.title;
    }
  } catch (e) {
    console.warn('Sheet adı alınamadı:', e.message);
  }
  return 'Sheet1';
}

/** Tek bir Google Sheet'i günceller */
async function updateGoogleSheet(sheetsClient, spreadsheetId, values, isFixedSheet = false) {
  let targetSheetName = 'Sheet1';
  try {
    // 1. Sayfa adını tespit et
    if (isFixedSheet) {
      try {
        await sheetsClient.spreadsheets.get({ spreadsheetId, ranges: ['Sayfa1!A1'] });
        targetSheetName = 'Sayfa1';
      } catch (_) {
        targetSheetName = await getFirstSheetName(sheetsClient, spreadsheetId);
      }
    } else {
      targetSheetName = await getFirstSheetName(sheetsClient, spreadsheetId);
    }

    const fullSheetRange = targetSheetName.indexOf(' ') >= 0 || targetSheetName.includes("'")
      ? `'${targetSheetName.replace(/'/g, "''")}'`
      : targetSheetName;

    // 2. Sayfayı temizle
    try {
      await sheetsClient.spreadsheets.values.clear({ spreadsheetId, range: fullSheetRange });
    } catch (clearErr) {
      console.warn(`⚠️ Temizleme hatası: ${clearErr.message}`);
    }

    // 3. Verileri yaz
    const writeRange = `${fullSheetRange}!A1`;
    await sheetsClient.spreadsheets.values.update({
      spreadsheetId,
      range: writeRange,
      valueInputOption: 'RAW',
      requestBody: { values: values },
    });

    // Silinenler sayfasını temizle (varsa)
    try {
      const ss = await sheetsClient.spreadsheets.get({ spreadsheetId });
      const deletedSheet = ss.data.sheets.find(s => s.properties.title === 'Silinenler');
      if (deletedSheet) {
        await sheetsClient.spreadsheets.batchUpdate({
          spreadsheetId,
          requestBody: { requests: [{ deleteSheet: { sheetId: deletedSheet.properties.sheetId } }] }
        });
      }
    } catch (err) { /* ignore */ }

    return true;
  } catch (err) {
    console.error(`❌ Sheet güncelleme hatası (${spreadsheetId}):`, err.message);
    throw err;
  }
}

/** Tüm verileri (gelir, gider, vergi) ilgili tüm tablolara yazar */
async function syncAllRelevantSheets(sheetsClient, allEntries) {
  console.log(`🚀 [syncAllRelevantSheets] Başlatıldı. Toplam kayıt: ${allEntries.length}`);

  // 1. "Tum Eklenenler" (All Entries) Güncelle
  const allValues = prepareSheetValues(allEntries);
  const allEntriesId = FIXED_SHEET_IDS['tum eklenenler'];
  if (allEntriesId) {
    try {
      await updateGoogleSheet(sheetsClient, allEntriesId, allValues, true);
    } catch (e) {
      console.error('❌ "Tum Eklenenler" güncellenemedi:', e.message);
    }
  }

  // 2. Kişisel Tabloları Güncelle (ownerName'e göre grupla)
  const owners = [...new Set(allEntries.map(e => e.ownerName))].filter(Boolean);
  for (const owner of owners) {
    const ownerEntries = allEntries.filter(e => e.ownerName === owner);
    const ownerValues = prepareSheetValues(ownerEntries);
    const ownerSheetNameIdx = normalizeSheetName(`${owner} Eklediklerim`);

    // Eğer sabit bir ID varsa onu kullan, yoksa klasörde ara (bu kısım biraz daha karmaşık, 
    // şimdilik sadece sabit eşleşenleri veya klasörde bulunabilenleri güncelleyelim)
    let spreadsheetId = FIXED_SHEET_IDS[ownerSheetNameIdx];

    // Not: Arka plan tetikleyicisinde klasör araması yapmak maliyetli olabilir, 
    // şimdilik FIXED_SHEET_IDS içindekileri güncellemek en güvenlisi.
    if (spreadsheetId) {
      try {
        await updateGoogleSheet(sheetsClient, spreadsheetId, ownerValues, false);
      } catch (e) {
        console.warn(`⚠️ "${owner}" kişisel tablosu güncellenemedi:`, e.message);
      }
    }
  }

  // 3. Özel Tablolar (Gelir / Vergi)
  // Ortak Gelirleri
  const incomeEntries = allEntries.filter(e => e.entryType === 'income');
  const incomeValues = prepareSheetValues(incomeEntries);
  const incomeId = FIXED_SHEET_IDS['ortak gelirleri'];
  if (incomeId) {
    try {
      await updateGoogleSheet(sheetsClient, incomeId, incomeValues, true);
    } catch (e) {
      console.error('❌ "Ortak Gelirleri" güncellenemedi:', e.message);
    }
  }

  // Vergiden Düşülecekler
  const taxEntries = allEntries.filter(e => e.entryType === 'tax_deductible');
  const taxValues = prepareSheetValues(taxEntries);
  const taxId = FIXED_SHEET_IDS['vergiden dusulecekler'];
  if (taxId) {
    try {
      await updateGoogleSheet(sheetsClient, taxId, taxValues, true);
    } catch (e) {
      console.error('❌ "Vergiden Dusulecekler" güncellenemedi:', e.message);
    }
  }

  // Harcamalar (sadece Gider kayıtları)
  const expenseEntries = allEntries.filter(e => e.entryType === 'expense');
  const expenseValues = prepareSheetValues(expenseEntries);
  const expenseId = FIXED_SHEET_IDS['harcamalar'];
  if (expenseId) {
    try {
      await updateGoogleSheet(sheetsClient, expenseId, expenseValues, true);
    } catch (e) {
      console.error('❌ "Harcamalar" güncellenemedi:', e.message);
    }
  }

  console.log('✅ [syncAllRelevantSheets] Tüm tablolar senkronize edildi.');
}

setGlobalOptions({
  secrets: [
    'GOOGLE_API_KEY',
    'GOOGLE_SHEETS_FOLDER_ID',
    'GOOGLE_SHEETS_FIXED_EXPENSES_ID',
    'GOOGLE_SHEETS_FUARLAR_ID',
    'GOOGLE_SERVICE_ACCOUNT_EMAIL',
    'GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY',
    'GOOGLE_CLIENT_ID',
    'GOOGLE_CLIENT_SECRET',
    'GOOGLE_REFRESH_TOKEN'
  ]
});

exports.api = onRequest({
  timeoutSeconds: 120,
  maxInstances: 10,
  memory: '512MB',
  secrets: [
    'GOOGLE_API_KEY',
    'GOOGLE_SHEETS_FOLDER_ID',
    'GOOGLE_SHEETS_FIXED_EXPENSES_ID',
    'GOOGLE_SHEETS_FUARLAR_ID',
    'GOOGLE_SERVICE_ACCOUNT_EMAIL',
    'GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY',
    'GOOGLE_CLIENT_ID',
    'GOOGLE_CLIENT_SECRET',
    'GOOGLE_REFRESH_TOKEN',
    'GOOGLE_DRIVE_ROOT_FOLDER_ID'
  ]
}, app);

// Fuarlar hatırlatma bildirimleri: başlangıç tarihi (tarih) öncesinde 20, 10 ve 7 gün kala tüm üyelere push
const FUAR_REMINDER_DAYS = [20, 10, 7];
exports.fuarlarNotifications = onSchedule({
  schedule: 'every day 10:00',
  timeoutSeconds: 120,
  secrets: ['GOOGLE_API_KEY', 'GOOGLE_SHEETS_FUARLAR_ID'],
}, async () => {
  const fuarlar = await fetchFuarlarList();
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const messages = [];
  for (const f of fuarlar) {
    if (!f.tarih) continue;
    // Başlangıç tarihine kalan gün (bitiş değil)
    const [y, m, d] = f.tarih.split('-').map(Number);
    const fairStartDate = new Date(y, m - 1, d);
    fairStartDate.setHours(0, 0, 0, 0);
    const diffMs = fairStartDate - today;
    const daysLeft = Math.round(diffMs / (24 * 60 * 60 * 1000));
    if (FUAR_REMINDER_DAYS.includes(daysLeft)) {
      const yer = f.yer || 'Fuar';
      messages.push({ title: 'Fuar hatırlatması', body: `${yer}'deki ${f.fuarAdi} fuarına ${daysLeft} gün kaldı.` });
    }
  }
  if (messages.length === 0) return;
  const usersSnap = await admin.firestore().collection('users').get();
  const tokens = [];
  usersSnap.docs.forEach(doc => {
    const t = doc.data().fcmToken;
    if (t && typeof t === 'string') tokens.push(t);
  });
  if (tokens.length === 0) {
    console.log('Fuarlar bildirimi: Firestore\'da FCM token yok, atlanıyor.');
    return;
  }
  console.log(`Fuarlar bildirimi: ${messages.length} mesaj, ${tokens.length} cihaza gönderiliyor.`);
  const BATCH = 500;
  for (let i = 0; i < tokens.length; i += BATCH) {
    const chunk = tokens.slice(i, i + BATCH);
    for (const msg of messages) {
      try {
        await admin.messaging().sendEachForMulticast({
          tokens: chunk,
          notification: msg,
          android: { priority: 'high', notification: { channelId: 'high_importance_channel_v3', priority: 'high' } },
          data: {
            title: msg.title,
            body: msg.body,
            click_action: 'FLUTTER_NOTIFICATION_CLICK',
          },
        });
      } catch (e) {
        console.error('Fuarlar FCM send error:', e.message);
      }
    }
  }
});

/**
 * Firestore tetikleyicisi: Bir kayıt (entries/{entryId}) oluşturulduğunda, güncellendiğinde veya silindiğinde
 * Google Sheets dosyalarını (Tüm Eklenenler, Kişisel Tablo vb.) otomatik günceller.
 */
exports.onEntryChange = onDocumentWritten({
  document: 'entries/{entryId}',
  secrets: [
    'GOOGLE_API_KEY',
    'GOOGLE_SHEETS_FOLDER_ID',
    'GOOGLE_SHEETS_FIXED_EXPENSES_ID',
    'GOOGLE_SHEETS_FUARLAR_ID',
    'GOOGLE_SERVICE_ACCOUNT_EMAIL',
    'GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY',
    'GOOGLE_CLIENT_ID',
    'GOOGLE_CLIENT_SECRET',
    'GOOGLE_REFRESH_TOKEN',
    'GOOGLE_DRIVE_ROOT_FOLDER_ID'
  ]
}, async (event) => {
  console.log(`📝 [onEntryChange] Tetiklendi: ${event.params.entryId}`);

  try {
    // 1. Tüm aktif kayıtları Firestore'dan çek (Gerçek zamanlı güncel veri için)
    const entriesSnap = await admin.firestore().collection('entries').get();
    const allEntries = entriesSnap.docs
      .map(doc => ({ ...doc.data(), id: doc.id }))
      .filter(e => e.status !== 'deleted');
    console.log(`📊 [onEntryChange] Firestore'dan ${allEntries.length} aktif kayıt çekildi.`);

    // 2. Drive Client ve Sheets Client'ı SA ile başlat (Backend tetikleyicisi için)
    if (!saSheetsClient) {
      await initializeDriveClient(); // Bu fonksiyon saSheetsClient'ı set eder
    }

    if (!saSheetsClient) {
      console.error('❌ [onEntryChange] Service Account Sheets Client başlatılamadı.');
      return;
    }

    // 3. Senkronizasyon işlemini başlat
    await syncAllRelevantSheets(saSheetsClient, allEntries);

  } catch (error) {
    console.error('❌ [onEntryChange] Kritik hata:', error.message);
  }
});

/**
 * Firestore tetikleyicisi: Bir sabit gider (fixed_expenses/{entryId}) oluşturulduğunda, 
 * güncellendiğinde veya silindiğinde Google Sheets dosyasını günceller.
 */
exports.onFixedExpenseChange = onDocumentWritten({
  document: 'fixed_expenses/{entryId}',
  secrets: [
    'GOOGLE_API_KEY',
    'GOOGLE_SHEETS_FIXED_EXPENSES_ID',
    'GOOGLE_SERVICE_ACCOUNT_EMAIL',
    'GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY'
  ]
}, async (event) => {
  console.log(`📌 [onFixedExpenseChange] Tetiklendi: ${event.params.entryId}`);

  try {
    // 1. Tüm sabit giderleri çek
    const fixedSnap = await admin.firestore().collection('fixed_expenses').get();
    const allFixed = fixedSnap.docs.map(doc => ({ ...doc.data(), id: doc.id }));
    console.log(`📊 [onFixedExpenseChange] Firestore'dan ${allFixed.length} sabit gider çekildi.`);

    // 2. Drive/Sheets client hazırla
    if (!saSheetsClient) {
      await initializeDriveClient();
    }

    if (!saSheetsClient) {
      console.error('❌ [onFixedExpenseChange] Sheets Client başlatılamadı.');
      return;
    }

    // 3. Sabit Giderler dosyasını güncelle
    const values = prepareSheetValues(allFixed, true);
    const spreadsheetId = FIXED_SHEET_IDS['sabit giderler'];

    if (spreadsheetId) {
      await updateGoogleSheet(saSheetsClient, spreadsheetId, values, true);
      console.log('✅ [onFixedExpenseChange] Sabit Giderler senkronize edildi.');
    }

  } catch (error) {
    console.error('❌ [onFixedExpenseChange] Kritik hata:', error.message);
  }
});
