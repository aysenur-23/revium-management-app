/**
 * Supabase Edge Function - Google Drive Upload
 * Deno runtime kullanır
 */

// @ts-ignore - Deno global type
declare const Deno: {
  env: {
    get(key: string): string | undefined;
  };
};

// @ts-ignore - Deno remote import
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const GOOGLE_DRIVE_API = 'https://www.googleapis.com/drive/v3';

interface DriveFile {
  id: string;
  name: string;
}

serve(async (req) => {
  // CORS preflight
  if (req.method === 'OPTIONS') {
    console.log('✅ CORS preflight request');
    return new Response('ok', { headers: corsHeaders });
  }

  console.log(`📥 ${req.method} ${req.url}`);
  console.log('Headers:', Object.fromEntries(req.headers.entries()));

  try {
    const url = new URL(req.url);
    const pathname = url.pathname;
    console.log(`📍 Pathname: ${pathname}`);
    
    // Supabase Edge Functions'da function adı zaten URL'de olduğu için
    // pathname '/' veya '/upload' olabilir, ya da tam path olabilir
    // Health check - root veya /health
    if (pathname === '/' || pathname === '/health' || pathname.endsWith('/health')) {
      console.log('✅ Health check endpoint çağrıldı');
      return new Response(
        JSON.stringify({
          service: 'Expense Tracker Backend',
          status: 'running',
          version: '1.0.0',
          platform: 'Supabase Edge Functions',
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // OAuth callback endpoint - refresh token almak için
    if ((pathname === '/auth/callback' || pathname.endsWith('/auth/callback')) && req.method === 'GET') {
      console.log('🔐 OAuth callback endpoint çağrıldı');
      const code = url.searchParams.get('code');
      console.log('OAuth code:', code ? `${code.substring(0, 20)}...` : 'YOK');
      
      if (!code) {
        console.error('❌ Authorization code bulunamadı');
        return new Response(
          JSON.stringify({ error: 'Authorization code bulunamadı' }),
          {
            status: 400,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          }
        );
      }

      const clientId = Deno.env.get('GOOGLE_CLIENT_ID');
      const clientSecret = Deno.env.get('GOOGLE_CLIENT_SECRET');
      // Supabase Edge Function URL'i: https://project.supabase.co/functions/v1/upload
      // Redirect URI: https://project.supabase.co/functions/v1/upload/auth/callback
      const redirectUri = `https://nemwuunbowzuuyvhmehi.supabase.co/functions/v1/upload/auth/callback`;

      if (!clientId || !clientSecret) {
        return new Response(
          JSON.stringify({ error: 'OAuth credentials bulunamadı' }),
          {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          }
        );
      }

      // Token exchange
      const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams({
          code: code,
          client_id: clientId,
          client_secret: clientSecret,
          redirect_uri: redirectUri,
          grant_type: 'authorization_code',
        }),
      });

      if (!tokenResponse.ok) {
        const error = await tokenResponse.text();
        return new Response(
          JSON.stringify({ error: 'Token exchange failed', details: error }),
          {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          }
        );
      }

      const tokenData = await tokenResponse.json();
      const refreshToken = tokenData.refresh_token;

      if (!refreshToken) {
        return new Response(
          JSON.stringify({ 
            error: 'Refresh token alınamadı',
            message: 'Token yanıtında refresh_token bulunamadı. OAuth flow\'u tekrar deneyin.',
            tokenData: tokenData
          }),
          {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          }
        );
      }

      // Refresh token'ı döndür (kullanıcı Supabase secrets'a ekleyecek)
      return new Response(
        JSON.stringify({
          success: true,
          refreshToken: refreshToken,
          message: 'Refresh token başarıyla alındı. Supabase secrets\'a ekleyin:',
          command: `supabase secrets set GOOGLE_REFRESH_TOKEN="${refreshToken}"`
        }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      );
    }

    // OAuth auth URL endpoint
    if ((pathname === '/auth' || pathname.endsWith('/auth')) && req.method === 'GET') {
      console.log('🔐 OAuth auth URL endpoint çağrıldı');
      const clientId = Deno.env.get('GOOGLE_CLIENT_ID');
      // Supabase Edge Function URL'i: https://project.supabase.co/functions/v1/upload
      // Redirect URI: https://project.supabase.co/functions/v1/upload/auth/callback
      const redirectUri = `https://nemwuunbowzuuyvhmehi.supabase.co/functions/v1/upload/auth/callback`;
      const scope = 'https://www.googleapis.com/auth/drive.file https://www.googleapis.com/auth/spreadsheets';

      console.log('OAuth config:', {
        hasClientId: !!clientId,
        clientIdLength: clientId?.length || 0,
        redirectUri: redirectUri,
        scope: scope,
      });

      if (!clientId) {
        console.error('❌ GOOGLE_CLIENT_ID bulunamadı');
        return new Response(
          JSON.stringify({ error: 'GOOGLE_CLIENT_ID bulunamadı' }),
          {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          }
        );
      }

      const authUrl = `https://accounts.google.com/o/oauth2/v2/auth?` +
        `access_type=offline&` +
        `scope=${encodeURIComponent(scope)}&` +
        `prompt=consent&` +
        `redirect_uri=${encodeURIComponent(redirectUri)}&` +
        `response_type=code&` +
        `client_id=${clientId}`;

      console.log('✅ OAuth auth URL oluşturuldu:', authUrl.substring(0, 100) + '...');

      return new Response(
        JSON.stringify({
          authUrl: authUrl,
          redirectUri: redirectUri,
          message: 'Bu URL\'yi tarayıcıda açın ve yetkilendirme yapın. Sonra /auth/callback endpoint\'ine yönlendirileceksiniz.'
        }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      );
    }

    // Upload endpoint
    // Supabase Edge Functions'da function adı zaten URL'de olduğu için
    // pathname '/' veya '/upload' veya tam path olabilir
    // POST isteği ve pathname kontrolü
    if ((pathname === '/' || pathname === '/upload' || pathname.endsWith('/upload')) && req.method === 'POST') {
      try {
        const formData = await req.formData();
        console.log('FormData alındı, field sayısı:', formData.entries().length);
        
        const file = formData.get('file') as File;
        const ownerId = formData.get('ownerId') as string || 'unknown';
        const ownerName = formData.get('ownerName') as string || 'unknown';
        const amount = formData.get('amount') as string || '0';

        console.log('Dosya kontrolü:', {
          hasFile: !!file,
          fileName: file?.name,
          fileSize: file?.size,
          fileType: file?.type,
          ownerId: ownerId,
          ownerName: ownerName,
          amount: amount,
        });

        if (!file) {
          console.error('❌ Dosya bulunamadı! FormData fields:', Array.from(formData.keys()));
          return new Response(
            JSON.stringify({ 
              error: 'Dosya bulunamadı',
              message: 'FormData\'da "file" field\'ı bulunamadı',
              debug: {
                formDataKeys: Array.from(formData.keys()),
                contentType: req.headers.get('content-type'),
              }
            }),
            { 
              status: 400,
              headers: { ...corsHeaders, 'Content-Type': 'application/json' }
            }
          );
        }

      // Google Drive'a yükle
      console.log('🔑 Access token alınıyor...');
      const accessToken = await getAccessToken();
      if (!accessToken) {
        // Secrets kontrolü için debug bilgisi
        const hasClientId = !!Deno.env.get('GOOGLE_CLIENT_ID');
        const hasClientSecret = !!Deno.env.get('GOOGLE_CLIENT_SECRET');
        const hasRefreshToken = !!Deno.env.get('GOOGLE_REFRESH_TOKEN');
        
        console.error('❌ Access token alınamadı. Secrets durumu:', {
          hasClientId,
          hasClientSecret,
          hasRefreshToken,
        });
        
        return new Response(
          JSON.stringify({
            error: 'Google Drive kimlik bilgileri bulunamadı',
            message: `OAuth credentials gerekli. Secrets durumu: CLIENT_ID=${hasClientId}, CLIENT_SECRET=${hasClientSecret}, REFRESH_TOKEN=${hasRefreshToken}`,
            debug: {
              hasClientId,
              hasClientSecret,
              hasRefreshToken,
            }
          }),
          {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          }
        );
      }
      console.log('✅ Access token alındı:', accessToken.substring(0, 20) + '...');

      const driveFolderId = Deno.env.get('GOOGLE_DRIVE_FOLDER_ID') || '';

      // Dosya ismini formatla: {ownerName}_{yyyy-MM-dd}_{amount}.{ext}
      const originalFileName = file.name;
      const fileExtension = originalFileName.split('.').pop() || 'pdf';
      const now = new Date();
      const dateStr = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
      
      // Owner name'i temizle (özel karakterleri kaldır, boşlukları alt çizgi ile değiştir)
      const cleanOwnerName = ownerName
        .replace(/[^a-zA-Z0-9ğüşıöçĞÜŞİÖÇ\s]/g, '') // Özel karakterleri kaldır
        .replace(/\s+/g, '') // Boşlukları kaldır
        .substring(0, 50); // Maksimum 50 karakter
      
      // Amount'u temizle (nokta yerine virgül, sadece sayı ve nokta)
      const cleanAmount = amount
        .replace(/[^\d.]/g, '') // Sadece sayı ve nokta
        .replace(/\./g, '_'); // Noktayı alt çizgi ile değiştir
      
      const newFileName = `${cleanOwnerName}_${dateStr}_${cleanAmount}.${fileExtension}`;
      
      console.log(`Dosya ismi formatlandı: "${originalFileName}" -> "${newFileName}"`);

      // Dosya metadata - Google Drive API formatı
      const fileMetadata: any = {
        name: newFileName,
      };
      
      // Sadece driveFolderId varsa parents ekle
      if (driveFolderId && driveFolderId.trim()) {
        fileMetadata.parents = [driveFolderId];
      }
      
      console.log('Dosya metadata:', JSON.stringify(fileMetadata));

      // Dosya içeriğini al
      const fileBuffer = await file.arrayBuffer();
      const fileBytes = new Uint8Array(fileBuffer);
      
      console.log(`Dosya yükleniyor: ${file.name}, ${fileBytes.length} bytes, MIME: ${file.type || 'application/octet-stream'}`);

      // Google Drive API - Media Upload (2 adımlı, en güvenilir yöntem)
      // 1. Adım: Metadata ile dosya oluştur ve upload URL al
      console.log('1. Adım: Resumable upload session oluşturuluyor...');
      const sessionResponse = await fetch(
        `${GOOGLE_DRIVE_API}/files?uploadType=resumable&fields=id`,
        {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(fileMetadata),
        }
      );

      if (!sessionResponse.ok) {
        const error = await sessionResponse.text();
        console.error('❌ Session oluşturma hatası:', {
          status: sessionResponse.status,
          statusText: sessionResponse.statusText,
          error: error.substring(0, 1000),
          metadata: JSON.stringify(fileMetadata),
        });
        
        // 400 hatası ise daha detaylı bilgi ver
        if (sessionResponse.status === 400) {
          try {
            const errorJson = JSON.parse(error);
            return new Response(
              JSON.stringify({
                error: 'Google Drive API hatası (400)',
                message: errorJson.error?.message || errorJson.message || error.substring(0, 500),
                details: errorJson.error || errorJson,
                status: 400,
              }),
              {
                status: 400,
                headers: { ...corsHeaders, 'Content-Type': 'application/json' }
              }
            );
          } catch (e) {
            // JSON parse edilemezse
          }
        }
        
        return new Response(
          JSON.stringify({
            error: 'Upload session oluşturulamadı',
            message: error.substring(0, 500),
            status: sessionResponse.status,
          }),
          {
            status: sessionResponse.status >= 400 && sessionResponse.status < 500 ? sessionResponse.status : 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          }
        );
      }

      // Location header'dan upload URL'yi al (body okunmadan önce!)
      const uploadUrl = sessionResponse.headers.get('Location');
      
      // Response body'yi oku (eğer varsa)
      let sessionResponseText = '';
      try {
        sessionResponseText = await sessionResponse.text();
        console.log('Session response:', sessionResponseText);
      } catch (e) {
        console.log('Session response body okunamadı (normal olabilir)');
      }
      
      console.log('Location header:', uploadUrl);

      let fileId: string | null = null;

      // Eğer response'da direkt id varsa (küçük dosyalar için)
      if (sessionResponseText && sessionResponseText.trim()) {
        try {
          const sessionData = JSON.parse(sessionResponseText);
          if (sessionData.id) {
            fileId = sessionData.id;
            console.log(`✅ Dosya direkt oluşturuldu (ID: ${fileId})`);
          }
        } catch (e) {
          // Response JSON değil, normal
          console.log('Session response JSON değil, resumable upload kullanılacak');
        }
      }

      // 2. Adım: Dosya içeriğini yükle (eğer Location header varsa)
      if (uploadUrl && !fileId) {
        console.log('📤 2. Adım: Dosya içeriği yükleniyor...');
        console.log('Upload URL:', uploadUrl);
        console.log('Dosya boyutu:', fileBytes.length, 'bytes');
        console.log('Content-Type:', file.type || 'application/octet-stream');
        
        const uploadResponse = await fetch(uploadUrl, {
          method: 'PUT',
          headers: {
            'Content-Type': file.type || 'application/octet-stream',
            'Content-Length': fileBytes.length.toString(),
          },
          body: fileBytes,
        });

        console.log('Upload response status:', uploadResponse.status, uploadResponse.statusText);

        if (!uploadResponse.ok) {
          const error = await uploadResponse.text();
          console.error('❌ Dosya yükleme hatası:', {
            status: uploadResponse.status,
            statusText: uploadResponse.statusText,
            error: error.substring(0, 500),
          });
          return new Response(
            JSON.stringify({
              error: 'Dosya yüklenemedi',
              message: error.substring(0, 500),
              status: uploadResponse.status,
            }),
            {
              status: 500,
              headers: { ...corsHeaders, 'Content-Type': 'application/json' }
            }
          );
        }
        console.log('✅ Dosya içeriği başarıyla yüklendi');

        // Upload response'dan file ID'yi al
        const uploadResponseText = await uploadResponse.text();
        if (uploadResponseText && uploadResponseText.trim()) {
          try {
            const uploadData = JSON.parse(uploadResponseText);
            if (uploadData.id) {
              fileId = uploadData.id;
            }
          } catch (e) {
            // Response boş veya JSON değil, dosya adı ile arama yap
            console.log('Upload response JSON değil, dosya adı ile arama yapılıyor...');
            const searchResponse = await fetch(
              `${GOOGLE_DRIVE_API}/files?q=name='${encodeURIComponent(file.name)}'&fields=files(id,name)&orderBy=createdTime desc&pageSize=1`,
              {
                headers: {
                  'Authorization': `Bearer ${accessToken}`,
                },
              }
            );
            if (searchResponse.ok) {
              const searchData = await searchResponse.json();
              if (searchData.files && searchData.files.length > 0) {
                fileId = searchData.files[0].id;
              }
            }
          }
        }
      } else if (!fileId) {
        // Location header yok ama response'da id de yok, dosya adı ile arama yap
        console.log('Location header yok, dosya adı ile arama yapılıyor...');
        const searchResponse = await fetch(
          `${GOOGLE_DRIVE_API}/files?q=name='${encodeURIComponent(file.name)}'&fields=files(id,name)&orderBy=createdTime desc&pageSize=1`,
          {
            headers: {
              'Authorization': `Bearer ${accessToken}`,
            },
          }
        );
        if (searchResponse.ok) {
          const searchData = await searchResponse.json();
          if (searchData.files && searchData.files.length > 0) {
            fileId = searchData.files[0].id;
          }
        }
      }

      // File ID yoksa, son çare olarak dosya adı ile arama yap
      if (!fileId) {
        console.log('⚠️ File ID alınamadı, dosya adı ile arama yapılıyor...');
        const finalSearchResponse = await fetch(
          `${GOOGLE_DRIVE_API}/files?q=name='${encodeURIComponent(file.name)}'&fields=files(id,name,createdTime)&orderBy=createdTime desc&pageSize=1`,
          {
            headers: {
              'Authorization': `Bearer ${accessToken}`,
            },
          }
        );
        
        if (finalSearchResponse.ok) {
          const finalSearchData = await finalSearchResponse.json();
          if (finalSearchData.files && finalSearchData.files.length > 0) {
            fileId = finalSearchData.files[0].id;
            console.log(`✅ File ID son aramada bulundu: ${fileId}`);
          }
        }
      }

      if (!fileId) {
        console.error('❌ File ID kesinlikle alınamadı!');
        return new Response(
          JSON.stringify({
            error: 'Dosya ID alınamadı',
            message: 'Dosya yüklendi ama ID alınamadı. Lütfen tekrar deneyin.',
          }),
          {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          }
        );
      }

      console.log(`✅ Dosya başarıyla yüklendi, File ID: ${fileId}`);
      
      // Dosyayı "herkes link ile görüntüleyebilir" olarak ayarla
      // Bu kritik - dosyanın görüntülenebilmesi için gerekli
      console.log('🔓 Dosya izinleri ayarlanıyor...');
      let permissionsSet = false;
      try {
        const permissionResponse = await fetch(
          `${GOOGLE_DRIVE_API}/files/${fileId}/permissions`,
          {
            method: 'POST',
            headers: {
              'Authorization': `Bearer ${accessToken}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              role: 'reader',
              type: 'anyone',
            }),
          }
        );

        if (permissionResponse.ok) {
          console.log('✅ Dosya izinleri başarıyla ayarlandı');
          permissionsSet = true;
        } else {
          const permError = await permissionResponse.text();
          console.error('⚠️ Dosya izinleri ayarlanamadı:', {
            status: permissionResponse.status,
            error: permError.substring(0, 200),
          });
          
          // İzinler ayarlanamazsa tekrar dene
          console.log('🔄 İzinler tekrar deneniyor...');
          await new Promise(resolve => setTimeout(resolve, 1000)); // 1 saniye bekle
          
          const retryPermissionResponse = await fetch(
            `${GOOGLE_DRIVE_API}/files/${fileId}/permissions`,
            {
              method: 'POST',
              headers: {
                'Authorization': `Bearer ${accessToken}`,
                'Content-Type': 'application/json',
              },
              body: JSON.stringify({
                role: 'reader',
                type: 'anyone',
              }),
            }
          );
          
          if (retryPermissionResponse.ok) {
            console.log('✅ Dosya izinleri tekrar denemede başarılı');
            permissionsSet = true;
          } else {
            console.error('❌ Dosya izinleri tekrar denemede de başarısız');
          }
        }
      } catch (permError) {
        console.error('❌ İzin ayarlama hatası:', permError);
      }

      // Görüntüleme URL'i oluştur
      // PDF'ler için viewer, görseller için uc?export=view
      const isPdf = file.name.toLowerCase().endsWith('.pdf') || file.type === 'application/pdf';
      const fileUrl = isPdf 
        ? `https://drive.google.com/file/d/${fileId}/view`
        : `https://drive.google.com/uc?export=view&id=${fileId}`;
      
      console.log('📎 Dosya URL\'i oluşturuldu:', {
        fileUrl: fileUrl,
        isPdf: isPdf,
        permissionsSet: permissionsSet,
      });

      // FormData'dan entry bilgilerini al (Sheets için)
      const description = formData.get('description') as string || '';
      const notes = formData.get('notes') as string || '';
      
      // Google Sheets'i güncelle (non-blocking)
      updateGoogleSheets(accessToken, {
        dateTime: new Date().toISOString(),
        notes: notes,
        ownerName: ownerName,
        amount: parseFloat(amount) || 0,
        description: description,
        fileUrl: fileUrl,
      }).catch((sheetsError) => {
        console.error('⚠️ Google Sheets güncelleme hatası (non-blocking):', sheetsError);
        // Hata olsa bile upload başarılı sayılır
      });

      return new Response(
        JSON.stringify({
          fileId: fileId,
          fileUrl: fileUrl,
        }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      );
      } catch (uploadError) {
        console.error('❌ Upload endpoint hatası:', uploadError);
        return new Response(
          JSON.stringify({
            error: 'Upload işlemi başarısız',
            message: uploadError instanceof Error ? uploadError.message : String(uploadError),
            stack: uploadError instanceof Error ? uploadError.stack : undefined,
          }),
          {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          }
        );
      }
    }

    // Delete endpoint - Google Drive'dan dosya sil
    if ((pathname === '/delete' || pathname.endsWith('/delete')) && req.method === 'POST') {
      try {
        const body = await req.json();
        const fileId = body.fileId as string;

        console.log('🗑️ Delete endpoint çağrıldı:', { fileId });

        if (!fileId) {
          return new Response(
            JSON.stringify({ 
              error: 'fileId gerekli',
              message: 'Silinecek dosyanın ID\'si gönderilmedi'
            }),
            { 
              status: 400,
              headers: { ...corsHeaders, 'Content-Type': 'application/json' }
            }
          );
        }

        // Access token al
        const accessToken = await getAccessToken();
        if (!accessToken) {
          return new Response(
            JSON.stringify({ 
              error: 'Access token alınamadı',
              message: 'Google Drive erişim token\'ı alınamadı. OAuth credentials kontrol edin.'
            }),
            { 
              status: 500,
              headers: { ...corsHeaders, 'Content-Type': 'application/json' }
            }
          );
        }

        // Google Drive'dan dosyayı sil
        const deleteResponse = await fetch(
          `${GOOGLE_DRIVE_API}/files/${fileId}`,
          {
            method: 'DELETE',
            headers: {
              'Authorization': `Bearer ${accessToken}`,
            },
          }
        );

        if (!deleteResponse.ok) {
          const errorText = await deleteResponse.text();
          console.error('❌ Google Drive silme hatası:', errorText);
          
          // 404 hatası dosya zaten silinmiş olabilir, bu durumda başarılı sayılabilir
          if (deleteResponse.status === 404) {
            console.log('⚠️ Dosya zaten silinmiş (404), başarılı sayılıyor');
            return new Response(
              JSON.stringify({
                success: true,
                message: 'Dosya zaten silinmiş veya bulunamadı',
              }),
              {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' }
              }
            );
          }

          return new Response(
            JSON.stringify({ 
              error: 'Dosya silinemedi',
              message: `Google Drive API hatası: ${deleteResponse.status} - ${errorText}`
            }),
            { 
              status: deleteResponse.status,
              headers: { ...corsHeaders, 'Content-Type': 'application/json' }
            }
          );
        }

        console.log('✅ Dosya başarıyla silindi:', fileId);

        return new Response(
          JSON.stringify({
            success: true,
            message: 'Dosya başarıyla silindi',
            fileId: fileId,
          }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          }
        );
      } catch (deleteError) {
        console.error('❌ Delete endpoint hatası:', deleteError);
        return new Response(
          JSON.stringify({
            error: 'Dosya silme işlemi başarısız',
            message: deleteError instanceof Error ? deleteError.message : String(deleteError),
            stack: deleteError instanceof Error ? deleteError.stack : undefined,
          }),
          {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          }
        );
      }
    }

    // Initialize Google Sheets with all existing entries endpoint
    if ((pathname === '/init-sheets' || pathname.endsWith('/init-sheets')) && req.method === 'POST') {
      try {
        console.log('📊 Init Sheets endpoint çağrıldı');

        const body = await req.json();
        const entries = body.entries as Array<{
          dateTime: string;
          notes: string;
          ownerName: string;
          amount: number;
          description: string;
          fileUrl: string;
        }> || [];

        console.log(`📝 ${entries.length} entry Google Sheets'e eklenecek`);

        const accessToken = await getAccessToken();
        if (!accessToken) {
          return new Response(
            JSON.stringify({ 
              error: 'Access token alınamadı',
              message: 'Google Drive kimlik bilgileri eksik.'
            }),
            { 
              status: 500,
              headers: { ...corsHeaders, 'Content-Type': 'application/json' }
            }
          );
        }

        const GOOGLE_SHEETS_API = 'https://sheets.googleapis.com/v4';
        const sheetsId = Deno.env.get('GOOGLE_SHEETS_ID');
        const driveFolderId = Deno.env.get('GOOGLE_DRIVE_FOLDER_ID') || '';

        // Sheets ID yoksa oluştur
        let actualSheetsId = sheetsId;
        if (!actualSheetsId) {
          console.log('📊 Google Sheets dosyası bulunamadı, oluşturuluyor...');
          
          // Yeni Sheets dosyası oluştur
          const createResponse = await fetch(
            `${GOOGLE_DRIVE_API}/files`,
            {
              method: 'POST',
              headers: {
                'Authorization': `Bearer ${accessToken}`,
                'Content-Type': 'application/json',
              },
              body: JSON.stringify({
                name: 'Harcama Takibi',
                mimeType: 'application/vnd.google-apps.spreadsheet',
                parents: driveFolderId ? [driveFolderId] : [],
              }),
            }
          );

          if (!createResponse.ok) {
            const error = await createResponse.text();
            console.error('❌ Sheets dosyası oluşturulamadı:', error);
            return new Response(
              JSON.stringify({ 
                error: 'Sheets dosyası oluşturulamadı',
                message: error
              }),
              { 
                status: 500,
                headers: { ...corsHeaders, 'Content-Type': 'application/json' }
              }
            );
          }

          const createdFile = await createResponse.json();
          actualSheetsId = createdFile.id;
          console.log(`✅ Sheets dosyası oluşturuldu, ID: ${actualSheetsId}`);
        }

        // Başlık satırını ekle (eğer dosya yeni oluşturulduysa)
        if (!sheetsId) {
          await fetch(
            `${GOOGLE_SHEETS_API}/spreadsheets/${actualSheetsId}/values/A1:append?valueInputOption=RAW`,
            {
              method: 'POST',
              headers: {
                'Authorization': `Bearer ${accessToken}`,
                'Content-Type': 'application/json',
              },
              body: JSON.stringify({
                values: [[
                  'Tarih/Saat',
                  'Açıklama',
                  'Yükleyen',
                  'Miktar',
                  'Harcama Kalemi',
                  'Dosya URL',
                ]],
              }),
            }
          );
          console.log('✅ Sheets başlık satırı eklendi');
        }

        // Tüm entry'leri ekle
        if (entries.length > 0) {
          const rows = entries.map(entry => {
            const date = new Date(entry.dateTime);
            const dateStr = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')} ${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
            
            return [
              dateStr,
              entry.notes || '',
              entry.ownerName,
              entry.amount.toString(),
              entry.description,
              entry.fileUrl,
            ];
          });

          // Batch olarak ekle (1000 satır limiti var, daha fazlası için batch'e böl)
          const batchSize = 1000;
          for (let i = 0; i < rows.length; i += batchSize) {
            const batch = rows.slice(i, i + batchSize);
            
            const appendResponse = await fetch(
              `${GOOGLE_SHEETS_API}/spreadsheets/${actualSheetsId}/values/A:append?valueInputOption=RAW`,
              {
                method: 'POST',
                headers: {
                  'Authorization': `Bearer ${accessToken}`,
                  'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                  values: batch,
                }),
              }
            );

            if (!appendResponse.ok) {
              const error = await appendResponse.text();
              console.error('❌ Sheets batch ekleme hatası:', error);
              throw new Error(`Sheets batch eklenemedi: ${error}`);
            }
          }

          console.log(`✅ ${entries.length} entry Google Sheets'e eklendi`);
        }

        const sheetsUrl = `https://docs.google.com/spreadsheets/d/${actualSheetsId}`;

        return new Response(
          JSON.stringify({
            success: true,
            sheetsId: actualSheetsId,
            url: sheetsUrl,
            entriesAdded: entries.length,
          }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          }
        );
      } catch (initError) {
        console.error('❌ Init Sheets endpoint hatası:', initError);
        return new Response(
          JSON.stringify({
            error: 'Google Sheets oluşturma/başlatma başarısız',
            message: initError instanceof Error ? initError.message : String(initError),
          }),
          {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          }
        );
      }
    }

    // Get Google Sheets link endpoint
    if ((pathname === '/sheets' || pathname.endsWith('/sheets')) && req.method === 'GET') {
      try {
        console.log('📊 Sheets link endpoint çağrıldı');

        const sheetsId = Deno.env.get('GOOGLE_SHEETS_ID');
        
        if (!sheetsId) {
          return new Response(
            JSON.stringify({ 
              error: 'Google Sheets ID bulunamadı',
              message: 'Google Sheets dosyası henüz oluşturulmamış. İlk dosya yüklendiğinde otomatik olarak oluşturulacak.'
            }),
            { 
              status: 404,
              headers: { ...corsHeaders, 'Content-Type': 'application/json' }
            }
          );
        }

        const sheetsUrl = `https://docs.google.com/spreadsheets/d/${sheetsId}`;
        
        console.log(`✅ Sheets link döndürülüyor: ${sheetsUrl}`);

        return new Response(
          JSON.stringify({
            success: true,
            sheetsId: sheetsId,
            url: sheetsUrl,
          }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          }
        );
      } catch (sheetsError) {
        console.error('❌ Sheets link endpoint hatası:', sheetsError);
        return new Response(
          JSON.stringify({
            error: 'Sheets link alınamadı',
            message: sheetsError instanceof Error ? sheetsError.message : String(sheetsError),
          }),
          {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          }
        );
      }
    }

    // 404
    return new Response(
      JSON.stringify({
        error: 'Not found',
        path: url.pathname,
        message: 'Endpoint bulunamadı',
      }),
      {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    );
  } catch (error) {
    console.error('❌ Genel hata:', error);
    console.error('Error type:', error?.constructor?.name);
    console.error('Error message:', error instanceof Error ? error.message : String(error));
    console.error('Error stack:', error instanceof Error ? error.stack : 'N/A');
    
    return new Response(
      JSON.stringify({
        error: 'Internal server error',
        message: error instanceof Error ? error.message : String(error),
        stack: error instanceof Error ? error.stack : undefined,
      }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    );
  }
});

/**
 * Google Drive için access token al
 * OAuth 2.0 refresh token kullanarak access token alır
 */
async function getAccessToken(): Promise<string | null> {
  try {
    const clientId = Deno.env.get('GOOGLE_CLIENT_ID');
    const clientSecret = Deno.env.get('GOOGLE_CLIENT_SECRET');
    const refreshToken = Deno.env.get('GOOGLE_REFRESH_TOKEN');

    console.log('🔍 OAuth credentials kontrol ediliyor...');
    console.log('Credentials durumu:', {
      hasClientId: !!clientId,
      hasClientSecret: !!clientSecret,
      hasRefreshToken: !!refreshToken,
      clientIdLength: clientId?.length || 0,
      clientSecretLength: clientSecret?.length || 0,
      refreshTokenLength: refreshToken?.length || 0,
    });

    if (!clientId || !clientSecret || !refreshToken) {
      console.error('❌ OAuth credentials bulunamadı:', {
        hasClientId: !!clientId,
        hasClientSecret: !!clientSecret,
        hasRefreshToken: !!refreshToken,
        clientIdLength: clientId?.length || 0,
        clientSecretLength: clientSecret?.length || 0,
        refreshTokenLength: refreshToken?.length || 0,
      });
      return null;
    }
    
    console.log('✅ OAuth credentials bulundu, access token alınıyor...');

    // Refresh token ile access token al
    const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({
        client_id: clientId,
        client_secret: clientSecret,
        refresh_token: refreshToken,
        grant_type: 'refresh_token',
      }),
    });

    console.log('Token refresh response status:', tokenResponse.status, tokenResponse.statusText);

    if (!tokenResponse.ok) {
      const error = await tokenResponse.text();
      console.error('❌ Token refresh error:', {
        status: tokenResponse.status,
        statusText: tokenResponse.statusText,
        error: error.substring(0, 500),
      });
      // Daha detaylı hata mesajı için
      try {
        const errorJson = JSON.parse(error);
        console.error('Token refresh error details:', JSON.stringify(errorJson, null, 2));
      } catch (e) {
        console.error('Token refresh error (raw):', error);
      }
      return null;
    }

    const tokenData = await tokenResponse.json();
    console.log('Token response keys:', Object.keys(tokenData));
    
    if (!tokenData.access_token) {
      console.error('❌ Access token alınamadı. Token response:', JSON.stringify(tokenData, null, 2));
      return null;
    }
    console.log('✅ Access token başarıyla alındı, uzunluk:', tokenData.access_token.length);
    return tokenData.access_token;
  } catch (error) {
    console.error('getAccessToken error:', error);
    return null;
  }
}

/**
 * Google Sheets'i günceller veya oluşturur
 * Her entry eklendiğinde yeni satır ekler
 */
async function updateGoogleSheets(
  accessToken: string,
  entryData: {
    dateTime: string;
    notes: string;
    ownerName: string;
    amount: number;
    description: string;
    fileUrl: string;
  }
): Promise<void> {
  try {
    const GOOGLE_SHEETS_API = 'https://sheets.googleapis.com/v4';
    const sheetsId = Deno.env.get('GOOGLE_SHEETS_ID');
    const driveFolderId = Deno.env.get('GOOGLE_DRIVE_FOLDER_ID') || '';

    // Sheets ID yoksa oluştur
    let actualSheetsId = sheetsId;
    if (!actualSheetsId) {
      console.log('📊 Google Sheets dosyası bulunamadı, oluşturuluyor...');
      
      // Yeni Sheets dosyası oluştur
      const createResponse = await fetch(
        `${GOOGLE_DRIVE_API}/files`,
        {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            name: 'Harcama Takibi',
            mimeType: 'application/vnd.google-apps.spreadsheet',
            parents: driveFolderId ? [driveFolderId] : [],
          }),
        }
      );

      if (!createResponse.ok) {
        const error = await createResponse.text();
        console.error('❌ Sheets dosyası oluşturulamadı:', error);
        throw new Error(`Sheets dosyası oluşturulamadı: ${error}`);
      }

      const createdFile = await createResponse.json();
      actualSheetsId = createdFile.id;
      console.log(`✅ Sheets dosyası oluşturuldu, ID: ${actualSheetsId}`);
      
      // İlk satırı (başlık) ekle
      await fetch(
        `${GOOGLE_SHEETS_API}/spreadsheets/${actualSheetsId}/values/A1:append?valueInputOption=RAW`,
        {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            values: [[
              'Tarih/Saat',
              'Açıklama',
              'Yükleyen',
              'Miktar',
              'Harcama Kalemi',
              'Dosya URL',
            ]],
          }),
        }
      );
      console.log('✅ Sheets başlık satırı eklendi');
    }

    // Tarih/saat formatla
    const date = new Date(entryData.dateTime);
    const dateStr = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')} ${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;

    // Yeni satır ekle
    const appendResponse = await fetch(
      `${GOOGLE_SHEETS_API}/spreadsheets/${actualSheetsId}/values/A:append?valueInputOption=RAW`,
      {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          values: [[
            dateStr,
            entryData.notes || '',
            entryData.ownerName,
            entryData.amount.toString(),
            entryData.description,
            entryData.fileUrl,
          ]],
        }),
      }
    );

    if (!appendResponse.ok) {
      const error = await appendResponse.text();
      console.error('❌ Sheets satır ekleme hatası:', error);
      throw new Error(`Sheets satır eklenemedi: ${error}`);
    }

    console.log('✅ Google Sheets güncellendi');
  } catch (error) {
    console.error('❌ updateGoogleSheets error:', error);
    throw error;
  }
}
