/**
 * Supabase Keep-Alive Script
 * Bu script Supabase Edge Function'ını düzenli olarak çağırarak projenin duraklatılmasını önler
 */

const SUPABASE_URL = 'https://nemwuunbowzuuyvhmehi.supabase.co/functions/v1/upload';
const ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5lbXd1dW5ib3d6dXV5dmhtZWhpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwMTQ3OTUsImV4cCI6MjA4MDU5MDc5NX0.xHM791yFkBMSCi_EdF7OhdOq9iscD0-dT6sHuNr1JYM';

// Keep-alive fonksiyonu
async function keepAlive() {
  try {
    const response = await fetch(SUPABASE_URL, {
      method: 'GET',
      headers: {
        'apikey': ANON_KEY,
        'Authorization': `Bearer ${ANON_KEY}`,
      },
      signal: AbortSignal.timeout(10000), // 10 saniye timeout
    });

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`);
    }

    const data = await response.json();
    
    if (data.status === 'ok') {
      const timestamp = new Date().toISOString();
      console.log(`[${timestamp}] ✅ Keep-alive başarılı: ${data.message}`);
      return true;
    } else {
      const timestamp = new Date().toISOString();
      console.log(`[${timestamp}] ⚠️  Beklenmeyen yanıt:`, JSON.stringify(data));
      return false;
    }
  } catch (error) {
    const timestamp = new Date().toISOString();
    console.error(`[${timestamp}] ❌ Keep-alive hatası:`, error.message);
    return false;
  }
}

// Ana fonksiyon
async function main() {
  const mode = process.argv[2];

  console.log('=== Supabase Keep-Alive Script ===');
  console.log(`Supabase URL: ${SUPABASE_URL}`);
  console.log('');

  // Tek seferlik çalıştırma
  if (mode === 'once') {
    console.log('Tek seferlik keep-alive çalıştırılıyor...');
    await keepAlive();
    process.exit(0);
  }

  // Sürekli çalışma modu (her 6 saatte bir)
  console.log('Sürekli keep-alive modu başlatılıyor...');
  console.log('Her 6 saatte bir Supabase\'e istek gönderilecek.');
  console.log('Durdurmak için Ctrl+C tuşlarına basın.');
  console.log('');

  // İlk çağrıyı hemen yap
  await keepAlive();

  // Her 6 saatte bir (21600000 ms) çağrı yap
  const INTERVAL_MS = 6 * 60 * 60 * 1000; // 6 saat

  setInterval(async () => {
    console.log('');
    console.log('Sonraki keep-alive: 6 saat sonra...');
    await keepAlive();
  }, INTERVAL_MS);
}

// Script'i çalıştır
main().catch((error) => {
  console.error('Fatal error:', error);
  process.exit(1);
});

