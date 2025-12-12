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

      // CSV header
      const headers = ['Tarih', 'Açıklama', 'Tutar', 'Kişi', 'Notlar', 'Dosya Linki'];
      const csvRows = [headers.join(',')];

      for (const e of allData) {
        const row = [
          e.dateTime || '',
          `"${(e.description || '').replace(/"/g, '""')}"`,
          e.amount || 0,
          `"${(e.ownerName || '').replace(/"/g, '""')}"`,
          `"${(e.notes || '').replace(/"/g, '""')}"`,
          e.fileUrl || '',
        ];
        csvRows.push(row.join(','));
      }

      const csvContent = csvRows.join('\n');
      const csvBytes = new TextEncoder().encode(csvContent);
      const folderId = Deno.env.get('GOOGLE_DRIVE_FOLDER_ID') || '';
      const fileName = `${sheetName}.csv`; // Sabit dosya adı (tarihsiz)

      // Önce mevcut dosyayı ara
      let existingFileId: string | null = null;
      const searchQuery = folderId 
        ? `name='${fileName}' and '${folderId}' in parents and trashed=false`
        : `name='${fileName}' and trashed=false`;
      
      const searchResp = await fetch(
        `${GOOGLE_DRIVE_API_V3}/files?q=${encodeURIComponent(searchQuery)}&fields=files(id,name)&${getDriveApiParams()}`,
        { headers: { Authorization: `Bearer ${token}` } }
      );

      if (searchResp.ok) {
        const searchData = await searchResp.json();
        if (searchData.files && searchData.files.length > 0) {
          existingFileId = searchData.files[0].id;
          console.log('Existing file found:', existingFileId);
        }
      }

      let csvFileId: string = '';
      let needsNewFile = !existingFileId;

      if (existingFileId) {
        // Mevcut dosyayı güncelle
        const updateResp = await fetch(
          `${GOOGLE_DRIVE_API}/files/${existingFileId}?uploadType=media&${getDriveApiParams()}`,
          {
            method: 'PATCH',
            headers: { 
              Authorization: `Bearer ${token}`, 
              'Content-Type': 'text/csv',
              'Content-Length': csvBytes.length.toString(),
            },
            body: csvBytes,
          }
        );

        if (!updateResp.ok) {
          console.log('Update failed, creating new file');
          needsNewFile = true;
        } else {
          csvFileId = existingFileId;
          console.log('File updated:', csvFileId);
        }
      }

      if (needsNewFile) {
        // Yeni dosya oluştur
        const metadata: Record<string, unknown> = { name: fileName, mimeType: 'text/csv' };
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
          return new Response(JSON.stringify({ error: 'CSV upload session failed', detail: await sessionResp.text() }), {
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

        const uploadResp = await fetch(uploadUrl, {
          method: 'PUT',
          headers: { 'Content-Type': 'text/csv', 'Content-Length': csvBytes.length.toString() },
          body: csvBytes,
        });

        if (!uploadResp.ok) {
          return new Response(JSON.stringify({ error: 'CSV upload failed', detail: await uploadResp.text() }), {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          });
        }

        const uploadData = await uploadResp.json();
        csvFileId = uploadData.id;

        // Set permissions (sadece yeni dosyalar için)
        await fetch(`${GOOGLE_DRIVE_API_V3}/files/${csvFileId}/permissions?${getDriveApiParams()}`, {
          method: 'POST',
          headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ role: 'reader', type: 'anyone' }),
        });
        
        console.log('New file created:', csvFileId);
      }

      const csvUrl = `https://drive.google.com/file/d/${csvFileId}/view`;
      console.log('CSV ready:', csvUrl);

      return new Response(
        JSON.stringify({ success: true, excelId: csvFileId, url: csvUrl, downloadUrl: `https://drive.google.com/uc?export=download&id=${csvFileId}` }),
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
