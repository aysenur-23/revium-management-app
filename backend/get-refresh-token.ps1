# Refresh Token Alma Scripti

# Google OAuth credentials - Set these from environment variables or Google Cloud Console
$clientId = $env:GOOGLE_CLIENT_ID
$clientSecret = $env:GOOGLE_CLIENT_SECRET
$redirectUri = "http://localhost:4000/auth/callback"

Write-Host "=== OAuth 2.0 Refresh Token Alma ===" -ForegroundColor Green
Write-Host ""
Write-Host "1. Aşağıdaki URL'yi tarayıcıda açın:" -ForegroundColor Yellow
Write-Host ""

$authUrl = "https://accounts.google.com/o/oauth2/v2/auth?access_type=offline&scope=https://www.googleapis.com/auth/drive.file&prompt=consent&response_type=code&client_id=$clientId&redirect_uri=$redirectUri"

Write-Host $authUrl -ForegroundColor Cyan
Write-Host ""

# URL'yi tarayıcıda aç
Start-Process $authUrl

Write-Host "2. Google hesabınızla giriş yapın ve izin verin" -ForegroundColor Yellow
Write-Host "3. Redirect URL'den 'code' parametresini kopyalayın" -ForegroundColor Yellow
Write-Host "   Örnek: http://localhost:4000/auth/callback?code=4/0Aean...&scope=..." -ForegroundColor Gray
Write-Host ""
Write-Host "4. Code'u aşağıya yapıştırın ve Enter'a basın:" -ForegroundColor Yellow
Write-Host ""

$code = Read-Host "Authorization Code"

if ($code) {
    Write-Host ""
    Write-Host "Token alınıyor..." -ForegroundColor Green
    
    $body = @{
        client_id = $clientId
        client_secret = $clientSecret
        code = $code
        grant_type = "authorization_code"
        redirect_uri = $redirectUri
    }
    
    try {
        $response = Invoke-RestMethod -Uri "https://oauth2.googleapis.com/token" -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
        
        if ($response.refresh_token) {
            Write-Host ""
            Write-Host "✅ Refresh Token başarıyla alındı!" -ForegroundColor Green
            Write-Host ""
            Write-Host "Refresh Token:" -ForegroundColor Yellow
            Write-Host $response.refresh_token -ForegroundColor Cyan
            Write-Host ""
            Write-Host "Supabase secrets'a eklemek için:" -ForegroundColor Yellow
            Write-Host "supabase secrets set GOOGLE_REFRESH_TOKEN=`"$($response.refresh_token)`"" -ForegroundColor Cyan
            Write-Host ""
            
            # Supabase secrets'a ekle
            $addToSupabase = Read-Host "Supabase secrets'a şimdi eklemek ister misiniz? (Y/N)"
            if ($addToSupabase -eq "Y" -or $addToSupabase -eq "y") {
                cd C:\Users\aslan\Desktop\app\backend
                supabase secrets set GOOGLE_REFRESH_TOKEN="$($response.refresh_token)"
                Write-Host ""
                Write-Host "✅ Refresh Token Supabase secrets'a eklendi!" -ForegroundColor Green
            }
        } else {
            Write-Host ""
            Write-Host "⚠️  Refresh token alınamadı. Access token alındı:" -ForegroundColor Yellow
            Write-Host $response.access_token -ForegroundColor Cyan
            Write-Host ""
            Write-Host "Not: Refresh token almak için 'prompt=consent' parametresi kullanılmalı." -ForegroundColor Yellow
        }
    } catch {
        Write-Host ""
        Write-Host "❌ Hata: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host $_.Exception.Response -ForegroundColor Red
    }
} else {
    Write-Host ""
    Write-Host "Code girilmedi, işlem iptal edildi." -ForegroundColor Yellow
}

