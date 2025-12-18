/**
 * Supabase Edge Function - Google Drive Upload
 * Deno runtime
 */

// @ts-ignore
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';

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
    console.error('OAuth credentials missing');
    return null;
  }

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
    console.error('Token refresh failed:', await resp.text());
    return null;
  }

  const data = await resp.json();
  return data.access_token || null;
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

  console.log(`${req.method} ${url.pathname} endpoint=${endpoint} fileId=${fileIdParam}`);

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

    // ============ HEALTH CHECK (GET without params) ============
    if (req.method === 'GET' && !fileIdParam && !endpoint) {
      return new Response(JSON.stringify({ status: 'ok', message: 'Upload function ready' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // ============ GET FIXED EXPENSES FROM GOOGLE SHEETS (GET with endpoint=fixed-expenses) ============
    if (req.method === 'GET' && endpoint === 'fixed-expenses') {
      const token = await getAccessToken();
      if (!token) {
        return new Response(JSON.stringify({ error: 'Token alınamadı' }), {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      // Google Sheets dosya ID'si (Supabase secrets'tan alınabilir veya sabit)
      const spreadsheetId = Deno.env.get('GOOGLE_SHEETS_FIXED_EXPENSES_ID') || '1_M2g7x4DQs8OQuZzrk4qWkLTMFGRrd-1';
      const range = 'Sheet1!A:Z'; // Tüm sütunları oku (A'dan Z'ye)

      try {
        const sheetsResp = await fetch(
          `${GOOGLE_SHEETS_API}/${spreadsheetId}/values/${range}?valueRenderOption=UNFORMATTED_VALUE&dateTimeRenderOption=FORMATTED_STRING`,
          { headers: { Authorization: `Bearer ${token}` } }
        );

        if (!sheetsResp.ok) {
          const errorText = await sheetsResp.text();
          console.error('Google Sheets API error:', errorText);
          return new Response(JSON.stringify({ error: 'Google Sheets okunamadı', detail: errorText }), {
            status: sheetsResp.status,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          });
        }

        const sheetsData = await sheetsResp.json();
        const values = sheetsData.values || [];

        if (values.length === 0) {
          return new Response(JSON.stringify({ expenses: [] }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          });
        }

        // İlk satır başlık olabilir, kontrol et
        let startRow = 0;
        if (values.length > 0) {
          const firstRow = values[0].map((v: string) => String(v).toLowerCase()).join('');
          if (firstRow.includes('açıklama') || firstRow.includes('aciklama') || firstRow.includes('description') || 
              firstRow.includes('tutar') || firstRow.includes('amount')) {
            startRow = 1;
          }
        }

        // Verileri parse et
        const expenses = [];
        for (let i = startRow; i < values.length; i++) {
          const row = values[i];
          if (!row || row.length === 0) continue;

          // Minimum sütunlar: Açıklama, Tutar
          const description = row[0] ? String(row[0]).trim() : '';
          const amountStr = row[1] ? String(row[1]).trim().replace(/[^\d.,-]/g, '').replace(',', '.') : '0';
          const amount = parseFloat(amountStr) || 0;

          if (description && amount > 0) {
            const expense: Record<string, unknown> = {
              id: `sheet_${i}`,
              ownerId: 'system',
              ownerName: row[2] ? String(row[2]).trim() : 'Sistem',
              description: description,
              amount: amount,
              category: row[3] ? String(row[3]).trim() : null,
              recurrence: row[4] ? String(row[4]).trim().toLowerCase() : null,
              notes: row[5] ? String(row[5]).trim() : null,
              isActive: row[6] ? !['hayır', 'hayir', 'pasif', '0', 'false', 'no'].includes(String(row[6]).toLowerCase()) : true,
              createdAt: new Date().toISOString(),
            };

            // Boş değerleri null yap
            if (!expense.category) delete expense.category;
            if (!expense.recurrence) delete expense.recurrence;
            if (!expense.notes) delete expense.notes;

            expenses.push(expense);
          }
        }

        console.log(`Google Sheets'ten ${expenses.length} sabit gider okundu`);

        return new Response(JSON.stringify({ expenses: expenses }), {
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

      // Google Sheets klasör ID'si
      const sheetsFolderId = Deno.env.get('GOOGLE_SHEETS_FOLDER_ID') || '1yO4roZMvMLxHDW4oHnQ592hX6opIRthG';
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
            `${GOOGLE_SHEETS_API}/${existingSpreadsheetId}/values/Sheet1!A1:Z${values.length}?valueInputOption=RAW`,
            {
              method: 'PUT',
              headers: { 
                Authorization: `Bearer ${token}`, 
                'Content-Type': 'application/json',
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
          `${GOOGLE_SHEETS_API}/${spreadsheetId}/values/Sheet1!A1:Z${values.length}?valueInputOption=RAW`,
          {
            method: 'PUT',
            headers: { 
              Authorization: `Bearer ${token}`, 
              'Content-Type': 'application/json',
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

      const sheetsUrl = `https://docs.google.com/spreadsheets/d/${spreadsheetId}/edit`;
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

    // ============ 404 ============
    return new Response(JSON.stringify({ error: 'Not found', path: url.pathname }), {
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
