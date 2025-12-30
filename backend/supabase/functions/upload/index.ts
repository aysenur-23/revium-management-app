/**
 * Supabase Edge Function - Google Drive Upload
 * Deno runtime
 */

// @ts-ignore
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
// @ts-ignore
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const GOOGLE_DRIVE_API = 'https://www.googleapis.com/upload/drive/v3';
const GOOGLE_DRIVE_API_V3 = 'https://www.googleapis.com/drive/v3';
const GOOGLE_SHEETS_API = 'https://sheets.googleapis.com/v4/spreadsheets';

// @ts-ignore
declare const Deno: { env: { get(key: string): string | undefined } };

function getDriveApiParams(extra: Record<string, string> = {}): string {
  return new URLSearchParams({ supportsAllDrives: 'true', includeItemsFromAllDrives: 'true', ...extra }).toString();
}

async function getAccessToken(): Promise<string | null> {
  const clientId = Deno.env.get('GOOGLE_CLIENT_ID');
  const clientSecret = Deno.env.get('GOOGLE_CLIENT_SECRET');
  const refreshToken = Deno.env.get('GOOGLE_REFRESH_TOKEN');

  if (!clientId || !clientSecret || !refreshToken) {
    console.error('❌ OAuth credentials missing');
    console.error(`   GOOGLE_CLIENT_ID: ${clientId ? '✓' : '✗'}`);
    console.error(`   GOOGLE_CLIENT_SECRET: ${clientSecret ? '✓' : '✗'}`);
    console.error(`   GOOGLE_REFRESH_TOKEN: ${refreshToken ? '✓' : '✗'}`);
    return null;
  }

  console.log('🔄 Refreshing OAuth token...');
  const resp = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: clientId,
      client_secret: clientSecret,
      refresh_token: refreshToken,
      grant_type: 'refresh_token',
    }),
  });

  if (!resp.ok) {
    const errorText = await resp.text();
    console.error('❌ Token refresh failed:', resp.status, errorText);
    try {
      const errorJson = JSON.parse(errorText);
      if (errorJson.error === 'invalid_grant') {
        console.error('⚠️ Refresh token geçersiz veya süresi dolmuş. Yeni refresh token alınmalı.');
      }
    } catch (_) {
      // JSON parse edilemezse text'i kullan
    }
    return null;
  }

  const data = await resp.json();
  const accessToken = data.access_token || null;
  
  if (accessToken) {
    console.log('✅ OAuth token başarıyla alındı');
    // Token'ın scope'larını kontrol et (eğer varsa)
    if (data.scope) {
      console.log(`📋 Token scope'ları: ${data.scope}`);
    }
  } else {
    console.error('❌ Access token alınamadı');
  }
  
  return accessToken;
}

serve(async (req) => {
  // CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const url = new URL(req.url);
  const params = new URLSearchParams(url.search);
  const endpoint = params.get('endpoint');
  const fileIdParam = params.get('fileId');

  console.log(`🔍 Request: ${req.method} ${url.pathname}`);
  console.log(`🔍 Full URL: ${req.url}`);
  console.log(`🔍 Search params: ${url.search}`);
  console.log(`🔍 Parsed endpoint: ${endpoint || 'null'}`);
  console.log(`🔍 Parsed fileId: ${fileIdParam || 'null'}`);

  try {
    // ============ DOWNLOAD (GET with fileId) ============
    if (req.method === 'GET' && fileIdParam) {
      const token = await getAccessToken();
      if (!token) {
        return new Response(JSON.stringify({ error: 'Token alınamadı' }), {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      const fileResp = await fetch(
        `${GOOGLE_DRIVE_API_V3}/files/${fileIdParam}?fields=id,name,mimeType,webViewLink,webContentLink&${getDriveApiParams()}`,
        { headers: { Authorization: `Bearer ${token}` } }
      );

      if (!fileResp.ok) {
        return new Response(JSON.stringify({ error: 'Dosya bulunamadı', detail: await fileResp.text() }), {
          status: fileResp.status,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      const fileData = await fileResp.json();
      console.log('File info:', fileData.name);

      return new Response(
        JSON.stringify({
          fileId: fileData.id,
          name: fileData.name,
          mimeType: fileData.mimeType,
          webViewLink: fileData.webViewLink,
          webContentLink: fileData.webContentLink,
          directDownloadLink: `https://drive.google.com/uc?export=download&id=${fileData.id}`,
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // ============ GET FIXED EXPENSES FROM GOOGLE SHEETS (GET with endpoint=fixed-expenses) ============
    // ÖNEMLİ: Bu kontrol health check'ten ÖNCE olmalı
    if (req.method === 'GET' && endpoint === 'fixed-expenses') {
      console.log('✅ Fixed expenses endpoint called');
      console.log(`Request URL: ${req.url}`);
      console.log(`Endpoint value: ${endpoint}`);
      
      // Google Sheets API Key (environment variable veya sabit)
      const googleApiKey = Deno.env.get('GOOGLE_API_KEY') || 'AIzaSyAqqldXUgQcdBp8tWhYVXCB0Hq4ImeIK4c';
      
      // Google Sheets dosya ID'si (Supabase secrets'tan alınabilir veya sabit)
      const spreadsheetId = Deno.env.get('GOOGLE_SHEETS_FIXED_EXPENSES_ID') || '1Ta2VG93hhih4kRxj_qAUJ5_NrNWCWxKLdRYZNvag-O4';
      
      // Önce dosyanın tipini kontrol et (Google Sheets mi yoksa Excel mi?)
      console.log(`📊 Checking file type for ID: ${spreadsheetId}`);
      const fileCheckUrl = `https://www.googleapis.com/drive/v3/files/${spreadsheetId}?fields=mimeType,name&key=${googleApiKey}`;
      try {
        const fileCheckResp = await fetch(fileCheckUrl);
        if (fileCheckResp.ok) {
          const fileInfo = await fileCheckResp.json();
          console.log(`📊 File info: name="${fileInfo.name}", mimeType="${fileInfo.mimeType}"`);
          
          // MIME type kontrolü
          if (fileInfo.mimeType === 'application/vnd.google-apps.spreadsheet') {
            console.log('✅ File is a native Google Sheets document');
          } else if (fileInfo.mimeType === 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet') {
            console.error('❌ File is still an Excel file (.xlsx). Please convert to Google Sheets format.');
            return new Response(JSON.stringify({ 
              error: 'Dosya hala Excel formatında',
              detail: 'Dosya Google Sheets formatına dönüştürülmemiş. Lütfen Google Drive\'da "File > Save as Google Sheets" yapın.',
              mimeType: fileInfo.mimeType,
              fileName: fileInfo.name
            }), {
              status: 400,
              headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            });
          } else {
            console.warn(`⚠️ Unknown file type: ${fileInfo.mimeType}`);
          }
        } else {
          const errorText = await fileCheckResp.text();
          console.warn(`⚠️ File check failed: ${fileCheckResp.status} - ${errorText}`);
        }
      } catch (error) {
        console.warn(`⚠️ File check error: ${error}`);
        // Devam et, belki dosya erişilebilir
      }
      
      // Dosya ID formatını kontrol et
      if (!spreadsheetId || spreadsheetId.length < 20) {
        console.error('❌ Geçersiz spreadsheet ID:', spreadsheetId);
        return new Response(JSON.stringify({ error: 'Geçersiz spreadsheet ID' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      // Önce metadata'dan sheet bilgilerini al
      let sheetName = 'aylik_gider_duzeni'; // Varsayılan
      let sheetId: number | null = null;
      const metadataUrl = `${GOOGLE_SHEETS_API}/${spreadsheetId}?key=${googleApiKey}`;
      console.log(`📊 Fetching metadata: ${metadataUrl}`);
      
      try {
        const metadataResp = await fetch(metadataUrl);
        if (metadataResp.ok) {
          const metadata = await metadataResp.json();
          if (metadata.sheets && metadata.sheets.length > 0) {
            // İlk sheet'i kullan
            sheetName = metadata.sheets[0].properties?.title || 'aylik_gider_duzeni';
            sheetId = metadata.sheets[0].properties?.sheetId || null;
            console.log(`✅ Found sheet: "${sheetName}" (ID: ${sheetId})`);
          }
        } else {
          console.warn(`⚠️ Metadata fetch failed: ${metadataResp.status}, using default sheet name`);
        }
      } catch (error) {
        console.warn(`⚠️ Metadata fetch error: ${error}, using default sheet name`);
      }
      
      console.log(`📊 Using sheet name: "${sheetName}"`);
      
      // Range oluştur - Google Sheets API için doğru format
      const cleanSheetName = sheetName.trim();
      
      // Özel karakterler kontrolü: boşluk, tire, nokta, iki nokta üst üste, artı varsa tek tırnak kullan
      const specialChars = [' ', '-', '.', ':', '+', '(', ')', '[', ']', '{', '}', '#', '@', '!', '$', '%', '^', '&', '*'];
      const needsQuotes = specialChars.some(char => cleanSheetName.includes(char));
      
      // Range formatı: SheetName!A1:Z1000 veya 'Sheet Name'!A1:Z1000
      const range = needsQuotes ? `'${cleanSheetName.replace(/'/g, "''")}'!A1:Z1000` : `${cleanSheetName}!A1:Z1000`;
      const encodedRange = encodeURIComponent(range);
      
      console.log(`📊 Reading from Google Sheets ID: ${spreadsheetId}`);
      console.log(`📊 Sheet name: "${cleanSheetName}"`);
      console.log(`📊 Sheet ID: ${sheetId}`);
      console.log(`📊 Needs quotes: ${needsQuotes}`);
      console.log(`📊 Range (raw): ${range}`);
      console.log(`📊 Range (encoded): ${encodedRange}`);
      console.log(`📊 Spreadsheet URL: https://docs.google.com/spreadsheets/d/${spreadsheetId}/edit`);

      try {
        // API key ile Google Sheets'ten veri oku
        // API key query parameter olarak eklenir
        // Range'i URL path'ine ekle, query parameter olarak değil
        let sheetsUrl = `${GOOGLE_SHEETS_API}/${spreadsheetId}/values/${encodedRange}?key=${googleApiKey}`;
        console.log(`📊 Fetching from: ${sheetsUrl}`);
        
        // Timeout kontrolü için AbortController kullan
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 50000); // 50 saniye timeout
        
        let sheetsResp: Response;
        try {
          sheetsResp = await fetch(sheetsUrl, { signal: controller.signal });
          clearTimeout(timeoutId);
        } catch (error: any) {
          clearTimeout(timeoutId);
          if (error.name === 'AbortError') {
            console.error('❌ Google Sheets API timeout (50 seconds)');
            return new Response(JSON.stringify({ 
              error: 'Google Sheets okuma zaman aşımı', 
              detail: 'İstek 50 saniye içinde tamamlanamadı. Lütfen tekrar deneyin.',
              timeout: true
            }), {
              status: 504,
              headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            });
          }
          throw error;
        }

        // Eğer 404 hatası alırsak, alternatif sheet adlarını deneyelim
        if (!sheetsResp.ok && sheetsResp.status === 404) {
          console.warn(`⚠️ Sheet "${cleanSheetName}" bulunamadı, alternatif sheet adlarını deniyorum...`);
          
          // Alternatif sheet adları: Sheet1, Sheet 1
          const alternativeSheetNames = ['Sheet1', 'Sheet 1'];
          
          for (const altSheetName of alternativeSheetNames) {
            const altRange = `${altSheetName}!A1:Z1000`;
            const altEncodedRange = encodeURIComponent(altRange);
            const altSheetsUrl = `${GOOGLE_SHEETS_API}/${spreadsheetId}/values/${altEncodedRange}?key=${googleApiKey}`;
            
            console.log(`📊 Trying alternative sheet name: ${altSheetName}`);
            const altController = new AbortController();
            const altTimeoutId = setTimeout(() => altController.abort(), 50000);
            try {
              sheetsResp = await fetch(altSheetsUrl, { signal: altController.signal });
              clearTimeout(altTimeoutId);
            } catch (error: any) {
              clearTimeout(altTimeoutId);
              if (error.name === 'AbortError') {
                console.error(`❌ Alternative sheet "${altSheetName}" timeout`);
                continue;
              }
              throw error;
            }
            
            if (sheetsResp.ok) {
              console.log(`✅ Found sheet with name: ${altSheetName}`);
              break;
            } else {
              console.log(`⚠️ Sheet "${altSheetName}" not found (${sheetsResp.status})`);
            }
          }
        }

        if (!sheetsResp.ok) {
          const errorText = await sheetsResp.text();
          console.error('❌ Google Sheets API error:', sheetsResp.status, errorText);
          console.error('❌ Request URL was:', sheetsUrl);
          console.error('❌ Spreadsheet ID:', spreadsheetId);
          console.error('❌ Sheet name:', cleanSheetName);
          
          // Daha açıklayıcı hata mesajı
          let errorMessage = 'Google Sheets okunamadı';
          let errorDetail = errorText;
          
          try {
            const errorJson = JSON.parse(errorText);
            if (errorJson.error) {
              errorDetail = errorJson.error.message || String(errorJson.error);
              if (errorJson.error.code) {
                errorDetail += ` (code: ${errorJson.error.code})`;
              }
            }
          } catch (_) {
            // JSON parse edilemezse text'i kullan
          }
          
          if (sheetsResp.status === 404) {
            errorMessage = `Sheet "${cleanSheetName}" bulunamadı. Lütfen sheet adının doğru olduğundan emin olun.`;
            errorDetail += `\n\n💡 Kontrol edin:\n`;
            errorDetail += `1. Dosya: https://docs.google.com/spreadsheets/d/${spreadsheetId}/edit\n`;
            errorDetail += `2. Sheet adı: "${cleanSheetName}" olmalı\n`;
            errorDetail += `3. Dosya "Herkes linki olan herkes görüntüleyebilir" olarak paylaşılmış olmalı`;
          } else if (sheetsResp.status === 403) {
            errorMessage = 'Dosyaya erişim izni yok. API key ile erişim için dosya public olmalı.';
            errorDetail += `\n\n🔒 ÇÖZÜM:\n`;
            errorDetail += `1. Google Sheets dosyasını açın: https://docs.google.com/spreadsheets/d/${spreadsheetId}/edit\n`;
            errorDetail += `2. "Share" butonuna tıklayın\n`;
            errorDetail += `3. "Anyone with the link" seçin ve "Viewer" izni verin\n`;
            errorDetail += `4. Link'i kopyalayın ve tekrar deneyin`;
          } else           if (sheetsResp.status === 400) {
            // "This operation is not supported for this document" hatası genellikle Excel dosyası olduğunu gösterir
            if (errorDetail.includes('not supported for this document')) {
              errorMessage = 'Dosya Excel formatında. Google Sheets formatına dönüştürmeniz gerekiyor.';
              errorDetail += `\n\n🔧 ÇÖZÜM:\n`;
              errorDetail += `1. Google Drive'da dosyayı açın: https://docs.google.com/spreadsheets/d/${spreadsheetId}/edit\n`;
              errorDetail += `2. File > Save as Google Sheets yapın\n`;
              errorDetail += `3. VEYA "Open with" > "Google Sheets" seçin\n`;
              errorDetail += `4. Yeni dosya ID'sini alın ve backend'de güncelleyin\n\n`;
              errorDetail += `⚠️ NOT: Excel dosyaları (.xlsx) Google Sheets API ile okunamaz. Dosyanın native Google Sheets formatında olması gerekir.`;
            } else {
              errorMessage = 'Geçersiz istek. Sheet adı veya range formatı hatalı olabilir.';
              errorDetail += `\n\n💡 Kontrol edin:\n`;
              errorDetail += `Sheet adı: "${cleanSheetName}"\n`;
              errorDetail += `Range: '${cleanSheetName}'!A1:Z1000`;
            }
          }
          
          return new Response(JSON.stringify({ 
            error: errorMessage, 
            detail: errorDetail,
            spreadsheetId: spreadsheetId,
            sheetName: cleanSheetName,
            requestUrl: sheetsUrl,
            status: sheetsResp.status
          }), {
            status: sheetsResp.status,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          });
        }
        
        console.log(`✅ Google Sheets API response OK: ${sheetsResp.status}`);

        const sheetsData = await sheetsResp.json();
        const values = sheetsData.values || [];

        console.log(`📊 Google Sheets'ten ${values.length} satır okundu`);
        console.log(`📊 First row sample:`, values.length > 0 ? JSON.stringify(values[0]) : 'No rows');
        console.log(`📊 Second row sample:`, values.length > 1 ? JSON.stringify(values[1]) : 'No second row');

        if (values.length === 0) {
          console.log('⚠️ Google Sheets boş - expenses boş döndürülüyor');
          return new Response(JSON.stringify({ expenses: [] }), {
            status: 200,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          });
        }

        // İlk satır başlık olabilir, kontrol et
        // Format: A=Ekleme Tarihi, B=Gider Kalemi, C=Yıllık Tutar, D=Aylık Tutar
        let startRow = 0;
        if (values.length > 0) {
          const firstRow = values[0].map((v: string) => String(v).toLowerCase()).join('');
          if (firstRow.includes('ekleme') || firstRow.includes('gider') || firstRow.includes('tarih') || 
              firstRow.includes('tutar') || firstRow.includes('kalemi')) {
            startRow = 1;
            console.log(`📊 First row is header, starting from row ${startRow}`);
          }
        }

        // Verileri parse et - Format: A=Tarih, B=Gider Kalemi, C=Yıllık Tutar, D=Aylık Tutar
        const expenses: Array<Record<string, unknown>> = [];
        console.log(`📊 Parsing ${values.length - startRow} rows starting from row ${startRow}`);
        console.log(`📊 First 5 rows sample:`, JSON.stringify(values.slice(startRow, Math.min(startRow + 5, values.length)), null, 2));
        
        for (let i = startRow; i < values.length; i++) {
          const row = values[i];
          if (!row || row.length === 0) {
            console.log(`⚠️ Row ${i} is empty, skipping`);
            continue;
          }

          // Row içeriğini logla
          console.log(`📊 Row ${i} raw data:`, JSON.stringify(row));

          // Sütun yapısı: A=Tarih, B=Gider Kalemi (açıklama), C=Yıllık Tutar, D=Aylık Tutar
          const description = row[1] ? String(row[1]).trim() : ''; // B sütunu: Gider Kalemi
          
          // Aylık tutarı kullan (D sütunu), yoksa yıllık tutarı 12'ye böl (C sütunu)
          let amountStr = '';
          if (row[3] && String(row[3]).trim()) {
            // D sütunu: Aylık Tutar
            const rawAmount = String(row[3]).trim();
            amountStr = rawAmount.replace(/[^\d.,-]/g, '').replace(',', '.');
            console.log(`📊 Row ${i} - Aylık tutar (D sütunu): raw="${rawAmount}", cleaned="${amountStr}"`);
          } else if (row[2] && String(row[2]).trim()) {
            // C sütunu: Yıllık Tutar - 12'ye böl
            const rawAmount = String(row[2]).trim();
            const yearlyAmount = parseFloat(rawAmount.replace(/[^\d.,-]/g, '').replace(',', '.')) || 0;
            amountStr = (yearlyAmount / 12).toFixed(2);
            console.log(`📊 Row ${i} - Yıllık tutar (C sütunu): raw="${rawAmount}", yearly=${yearlyAmount}, monthly=${amountStr}`);
          } else {
            amountStr = '0';
            console.log(`⚠️ Row ${i} - No amount found in C or D column`);
          }
          
          const amount = parseFloat(amountStr) || 0;

          console.log(`📊 Row ${i} parsed: description="${description}", amount=${amount}`);

          // Description veya amount boşsa uyarı ver ama yine de ekle (amount 0 olsa bile)
          if (!description || description.length === 0) {
            console.warn(`⚠️ Row ${i} has no description, skipping`);
            continue;
          }
          
          // Amount 0 olsa bile ekle (aktif/pasif kontrolü için)
          if (description) {
            // Tarih varsa parse et
            let createdAt = new Date().toISOString();
            if (row[0] && String(row[0]).trim()) {
              try {
                // Tarih formatı: DD.MM.YYYY
                const dateStr = String(row[0]).trim();
                const dateParts = dateStr.split('.');
                if (dateParts.length === 3) {
                  const day = parseInt(dateParts[0], 10);
                  const month = parseInt(dateParts[1], 10) - 1; // JS months are 0-indexed
                  const year = parseInt(dateParts[2], 10);
                  createdAt = new Date(year, month, day).toISOString();
                }
              } catch (e) {
                console.warn(`⚠️ Could not parse date from row ${i}: ${row[0]}`);
              }
            }

            const expense: Record<string, unknown> = {
              id: `sheet_${i}`,
              ownerId: 'system',
              ownerName: 'Sistem',
              description: description,
              amount: amount,
              category: null, // Bu formatta kategori yok
              recurrence: 'monthly', // Aylık giderler için varsayılan
              notes: null,
              isActive: true, // Varsayılan olarak aktif
              createdAt: createdAt,
            };

            if (!expense.category) delete expense.category;
            if (!expense.notes) delete expense.notes;

            expenses.push(expense);
            console.log(`✅ Added expense #${expenses.length}: ${description} - ${amount}₺`);
          }
        }
        
        console.log(`📊 Total expenses parsed: ${expenses.length}`);
        if (expenses.length > 0) {
          console.log(`📊 First expense sample:`, JSON.stringify(expenses[0], null, 2));
        }

        console.log(`✅ Google Sheets'ten ${expenses.length} sabit gider okundu`);
        console.log(`📊 Expenses sample:`, expenses.length > 0 ? JSON.stringify(expenses[0]) : 'No expenses');

        const responseBody = JSON.stringify({ expenses: expenses });
        console.log(`📤 Response body length: ${responseBody.length} bytes`);
        
        return new Response(responseBody, {
          status: 200,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      } catch (error) {
        console.error('Google Sheets okuma hatası:', error);
        return new Response(JSON.stringify({ error: 'Google Sheets okuma hatası', message: String(error) }), {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }
    }

    // ============ INIT-SHEETS (POST with endpoint=init-sheets) ============
    if (req.method === 'POST' && endpoint === 'init-sheets') {
      const token = await getAccessToken();
      if (!token) {
        return new Response(JSON.stringify({ error: 'Token alınamadı' }), {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      const body = await req.json();
      const entries = body.entries || [];
      const fixedExpenses = body.fixedExpenses || [];
      const sheetName = body.sheetName || 'Giderler'; // Sabit dosya adı
      const allData = [...entries, ...fixedExpenses];

      // Google Sheets için veri hazırla
      const headers = ['Tarih', 'Açıklama', 'Tutar', 'Kişi', 'Notlar', 'Dosya Linki'];
      const values = [headers];

      for (const e of allData) {
        values.push([
          e.dateTime || '',
          e.description || '',
          e.amount || 0,
          e.ownerName || '',
          e.notes || '',
          e.fileUrl || '',
        ]);
      }

      // Google Sheets klasör ID'si (Excel dosyaları bu klasöre kaydedilir)
      const sheetsFolderId = Deno.env.get('GOOGLE_SHEETS_FOLDER_ID') || '1yO4roZMvMLxHDW4oHnQ592hX6opIRthG';
      console.log(`Using Google Sheets folder ID: ${sheetsFolderId}`);
      const fileName = `${sheetName}`; // Sabit dosya adı (tarihsiz)

      // Önce mevcut Google Sheets dosyasını ara
      let existingSpreadsheetId: string | null = null;
      const searchQuery = `name='${fileName}' and '${sheetsFolderId}' in parents and mimeType='application/vnd.google-apps.spreadsheet' and trashed=false`;
      
      const searchResp = await fetch(
        `${GOOGLE_DRIVE_API_V3}/files?q=${encodeURIComponent(searchQuery)}&fields=files(id,name)&${getDriveApiParams()}`,
        { headers: { Authorization: `Bearer ${token}` } }
      );

      if (searchResp.ok) {
        const searchData = await searchResp.json();
        if (searchData.files && searchData.files.length > 0) {
          existingSpreadsheetId = searchData.files[0].id;
          console.log('Existing Google Sheets found:', existingSpreadsheetId);
        }
      }

      let spreadsheetId: string = '';
      let needsNewFile = !existingSpreadsheetId;

      if (existingSpreadsheetId) {
        // Mevcut Google Sheets'i güncelle (Values API ile)
        try {
          const updateResp = await fetch(
            `${GOOGLE_SHEETS_API}/${existingSpreadsheetId}/values/Sheet1!A1:Z${values.length}?valueInputOption=USER_ENTERED`,
            {
              method: 'PUT',
              headers: { 
                Authorization: `Bearer ${token}`, 
                'Content-Type': 'application/json; charset=utf-8',
              },
              body: JSON.stringify({ values: values }),
            }
          );

          if (updateResp.ok) {
            spreadsheetId = existingSpreadsheetId;
            console.log('Google Sheets updated:', spreadsheetId);
          } else {
            const errorText = await updateResp.text();
            console.log('Update failed, creating new file:', errorText);
            needsNewFile = true;
          }
        } catch (error) {
          console.log('Update error, creating new file:', error);
          needsNewFile = true;
        }
      }

      if (needsNewFile) {
        // Yeni Google Sheets oluştur
        const metadata: Record<string, unknown> = { 
          name: fileName, 
          mimeType: 'application/vnd.google-apps.spreadsheet',
          parents: [sheetsFolderId],
        };

        const createResp = await fetch(
          `${GOOGLE_DRIVE_API_V3}/files?${getDriveApiParams({ fields: 'id' })}`,
          {
            method: 'POST',
            headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
            body: JSON.stringify(metadata),
          }
        );

        if (!createResp.ok) {
          const errorText = await createResp.text();
          return new Response(JSON.stringify({ error: 'Google Sheets oluşturulamadı', detail: errorText }), {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          });
        }

        const createData = await createResp.json();
        spreadsheetId = createData.id;

        if (!spreadsheetId) {
          return new Response(JSON.stringify({ error: 'Google Sheets ID alınamadı' }), {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          });
        }

        // Verileri Google Sheets'e yaz
        const writeResp = await fetch(
          `${GOOGLE_SHEETS_API}/${spreadsheetId}/values/Sheet1!A1:Z${values.length}?valueInputOption=USER_ENTERED`,
          {
            method: 'PUT',
            headers: { 
              Authorization: `Bearer ${token}`, 
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: JSON.stringify({ values: values }),
          }
        );

        if (!writeResp.ok) {
          const errorText = await writeResp.text();
          console.error('Google Sheets write error:', errorText);
          // Dosya oluşturuldu ama veri yazılamadı, yine de başarılı say
        }

        // Set permissions (sadece yeni dosyalar için)
        await fetch(`${GOOGLE_DRIVE_API_V3}/files/${spreadsheetId}/permissions?${getDriveApiParams()}`, {
          method: 'POST',
          headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ role: 'reader', type: 'anyone' }),
        });
        
        console.log('New Google Sheets created:', spreadsheetId);
      }

      const sheetsUrl = `https://docs.google.com/spreadsheets/d/${spreadsheetId}/view`;
      console.log('Google Sheets ready:', sheetsUrl);

      return new Response(
        JSON.stringify({ 
          success: true, 
          excelId: spreadsheetId, 
          spreadsheetId: spreadsheetId,
          url: sheetsUrl, 
          downloadUrl: `https://docs.google.com/spreadsheets/d/${spreadsheetId}/export?format=xlsx` 
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // ============ DELETE (POST to /delete) ============
    if (req.method === 'POST' && url.pathname.includes('/delete')) {
      const token = await getAccessToken();
      if (!token) {
        return new Response(JSON.stringify({ error: 'Token alınamadı' }), {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      const body = await req.json();
      const fileId = body.fileId;

      if (!fileId) {
        return new Response(JSON.stringify({ error: 'fileId gerekli' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      const delResp = await fetch(`${GOOGLE_DRIVE_API_V3}/files/${fileId}?${getDriveApiParams()}`, {
        method: 'DELETE',
        headers: { Authorization: `Bearer ${token}` },
      });

      if (!delResp.ok && delResp.status !== 404) {
        return new Response(JSON.stringify({ error: 'Silme hatası', detail: await delResp.text() }), {
          status: delResp.status,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      return new Response(JSON.stringify({ success: true }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // ============ UPLOAD (POST without endpoint) ============
    if (req.method === 'POST' && !endpoint) {
      const token = await getAccessToken();
      if (!token) {
        return new Response(JSON.stringify({ error: 'Token alınamadı' }), {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      const formData = await req.formData();
      const file = formData.get('file') as File;
      const ownerId = (formData.get('ownerId') as string) || 'unknown';
      const ownerName = (formData.get('ownerName') as string) || 'unknown';
      const amount = (formData.get('amount') as string) || '0';

      if (!file) {
        return new Response(JSON.stringify({ error: 'Dosya bulunamadı' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      const folderId = Deno.env.get('GOOGLE_DRIVE_FOLDER_ID') || '';
      const ext = file.name.split('.').pop() || 'pdf';
      const dateStr = new Date().toISOString().split('T')[0];
      const cleanOwner = ownerName.replace(/[^a-zA-Z0-9ğüşıöçĞÜŞİÖÇ]/g, '').substring(0, 30);
      const cleanAmount = amount.replace(/[^\d.]/g, '').replace(/\./g, '_');
      const newFileName = `${cleanOwner}_${dateStr}_${cleanAmount}.${ext}`;

      const metadata: Record<string, unknown> = { name: newFileName };
      if (folderId) metadata.parents = [folderId];

      const sessionResp = await fetch(
        `${GOOGLE_DRIVE_API}/files?uploadType=resumable&${getDriveApiParams({ fields: 'id' })}`,
        {
          method: 'POST',
          headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
          body: JSON.stringify(metadata),
        }
      );

      if (!sessionResp.ok) {
        return new Response(JSON.stringify({ error: 'Upload session failed', detail: await sessionResp.text() }), {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      const uploadUrl = sessionResp.headers.get('Location');
      if (!uploadUrl) {
        return new Response(JSON.stringify({ error: 'Upload URL alınamadı' }), {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      const fileBytes = new Uint8Array(await file.arrayBuffer());
      const uploadResp = await fetch(uploadUrl, {
        method: 'PUT',
        headers: { 'Content-Type': file.type || 'application/octet-stream', 'Content-Length': fileBytes.length.toString() },
        body: fileBytes,
      });

      if (!uploadResp.ok) {
        return new Response(JSON.stringify({ error: 'Upload failed', detail: await uploadResp.text() }), {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      const uploadData = await uploadResp.json();
      const fileId = uploadData.id;

      if (!fileId) {
        return new Response(JSON.stringify({ error: 'File ID alınamadı' }), {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      // Set permissions
      await fetch(`${GOOGLE_DRIVE_API_V3}/files/${fileId}/permissions?${getDriveApiParams()}`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ role: 'reader', type: 'anyone' }),
      });

      // Get file info
      const infoResp = await fetch(
        `${GOOGLE_DRIVE_API_V3}/files/${fileId}?fields=id,webViewLink&${getDriveApiParams()}`,
        { headers: { Authorization: `Bearer ${token}` } }
      );

      let webViewLink = `https://drive.google.com/file/d/${fileId}/view`;
      if (infoResp.ok) {
        const info = await infoResp.json();
        webViewLink = info.webViewLink || webViewLink;
      }

      console.log('File uploaded:', fileId);

      return new Response(
        JSON.stringify({ fileId, fileUrl: webViewLink, webViewLink }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // ============ HEALTH CHECK (GET without params) ============
    if (req.method === 'GET' && !fileIdParam && !endpoint) {
      // Supabase client ile DB query yaparak keep-alive sağla
      try {
        const supabaseUrl = Deno.env.get('SUPABASE_URL') || 'https://nemwuunbowzuuyvhmehi.supabase.co';
        const supabaseKey = Deno.env.get('SUPABASE_ANON_KEY') || req.headers.get('apikey') || '';
        
        const supabase = createClient(supabaseUrl, supabaseKey);
        
        // Basit bir DB query yap (users tablosundan 1 kayıt çek)
        const { data, error } = await supabase
          .from('users')
          .select('id')
          .limit(1);
        
        if (error) {
          console.log('⚠️ Keep-alive DB query hatası (normal):', error.message);
          // Hata olsa bile 200 döndür (keep-alive için önemli olan isteğin gelmesi)
        } else {
          console.log('✅ Keep-alive DB query başarılı:', data?.length || 0, 'kayıt');
        }
        
        return new Response(JSON.stringify({ 
          status: 'ok', 
          message: 'Upload function ready',
          dbQuery: error ? 'failed' : 'success',
          timestamp: new Date().toISOString()
        }), {
          status: 200,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      } catch (dbError) {
        console.log('⚠️ Keep-alive DB query exception (normal):', dbError);
        // Exception olsa bile 200 döndür
        return new Response(JSON.stringify({ 
          status: 'ok', 
          message: 'Upload function ready (DB query failed)',
          timestamp: new Date().toISOString()
        }), {
          status: 200,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }
    }

    // ============ 404 ============
    console.log(`❌ 404 - Endpoint not found: method=${req.method}, endpoint=${endpoint || 'null'}, fileId=${fileIdParam || 'null'}, path=${url.pathname}, search=${url.search}`);
    return new Response(JSON.stringify({ error: 'Not found', path: url.pathname, endpoint: endpoint || null, method: req.method }), {
      status: 404,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('Error:', error);
    return new Response(
      JSON.stringify({ error: 'Internal error', message: String(error) }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
