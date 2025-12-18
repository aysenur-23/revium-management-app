# Supabase Keep-Alive Script
# Bu script Supabase Edge Function'ını düzenli olarak çağırarak projenin duraklatılmasını önler

$supabaseUrl = "https://nemwuunbowzuuyvhmehi.supabase.co/functions/v1/upload"
$anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5lbXd1dW5ib3d6dXV5dmhtZWhpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwMTQ3OTUsImV4cCI6MjA4MDU5MDc5NX0.xHM791yFkBMSCi_EdF7OhdOq9iscD0-dT6sHuNr1JYM"

# Health check endpoint (parametresiz GET isteği)
$healthUrl = $supabaseUrl

Write-Host "=== Supabase Keep-Alive Script ===" -ForegroundColor Green
Write-Host "Supabase URL: $healthUrl" -ForegroundColor Cyan
Write-Host ""

# Headers
$headers = @{
    "apikey" = $anonKey
    "Authorization" = "Bearer $anonKey"
}

# Keep-alive fonksiyonu
function Invoke-KeepAlive {
    try {
        $response = Invoke-RestMethod -Uri $healthUrl -Method GET -Headers $headers -TimeoutSec 10
        
        if ($response.status -eq "ok") {
            Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] ✅ Keep-alive başarılı: $($response.message)" -ForegroundColor Green
            return $true
        } else {
            Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] ⚠️  Beklenmeyen yanıt: $($response | ConvertTo-Json)" -ForegroundColor Yellow
            return $false
        }
    } catch {
        Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] ❌ Keep-alive hatası: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Tek seferlik çalıştırma
if ($args[0] -eq "once") {
    Write-Host "Tek seferlik keep-alive çalıştırılıyor..." -ForegroundColor Yellow
    Invoke-KeepAlive
    exit
}

# Sürekli çalışma modu (her 6 saatte bir)
Write-Host "Sürekli keep-alive modu başlatılıyor..." -ForegroundColor Yellow
Write-Host "Her 6 saatte bir Supabase'e istek gönderilecek." -ForegroundColor Yellow
Write-Host "Durdurmak için Ctrl+C tuşlarına basın." -ForegroundColor Yellow
Write-Host ""

# İlk çağrıyı hemen yap
Invoke-KeepAlive

# Her 6 saatte bir (21600 saniye) çağrı yap
while ($true) {
    Write-Host ""
    Write-Host "Sonraki keep-alive: 6 saat sonra..." -ForegroundColor Gray
    Start-Sleep -Seconds 21600  # 6 saat = 21600 saniye
    
    Invoke-KeepAlive
}

