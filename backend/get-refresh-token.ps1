# Refresh Token Alma Scripti

# Google OAuth credentials - Environment variables, client_secret.json veya manuel giris
$clientId = $env:GOOGLE_CLIENT_ID
$clientSecret = $env:GOOGLE_CLIENT_SECRET
$redirectUri = "http://localhost:4000/auth/callback"

Write-Host "=== OAuth 2.0 Refresh Token Alma ===" -ForegroundColor Green
Write-Host ""

# Eger environment variable'lar yoksa, client_secret.json dosyasini kontrol et
if (-not $clientId -or -not $clientSecret) {
    $clientSecretPath = Join-Path $PSScriptRoot "client_secret.json"
    if (Test-Path $clientSecretPath) {
        Write-Host "client_secret.json dosyasi bulundu, okunuyor..." -ForegroundColor Cyan
        try {
            $jsonContent = Get-Content $clientSecretPath -Raw | ConvertFrom-Json
            if ($jsonContent.web.client_id) {
                $clientId = $jsonContent.web.client_id
                Write-Host "OK: Client ID client_secret.json'dan alindi" -ForegroundColor Green
            }
            if ($jsonContent.web.client_secret) {
                $clientSecret = $jsonContent.web.client_secret
                Write-Host "OK: Client Secret client_secret.json'dan alindi" -ForegroundColor Green
            }
        } catch {
            Write-Host "UYARI: client_secret.json okunamadi: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

# Eger hala yoksa kullanicidan iste
if (-not $clientId) {
    Write-Host ""
    Write-Host "GOOGLE_CLIENT_ID bulunamadi." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Supabase Dashboard'dan almak icin:" -ForegroundColor Cyan
    Write-Host "1. https://supabase.com/dashboard/project/nemwuunbowzuuyvhmehi/settings/functions" -ForegroundColor White
    Write-Host "2. Secrets bolumunde 'GOOGLE_CLIENT_ID' degerini kopyalayin (Reveal butonuna tiklayin)" -ForegroundColor White
    Write-Host ""
    Write-Host "VEYA Google Cloud Console'dan:" -ForegroundColor Cyan
    Write-Host "1. https://console.cloud.google.com/apis/credentials" -ForegroundColor White
    Write-Host "2. OAuth 2.0 Client ID'nizi secin ve Client ID'yi kopyalayin" -ForegroundColor White
    Write-Host ""
    $clientId = Read-Host "Client ID'yi yapistirin"
}

if (-not $clientSecret) {
    Write-Host ""
    Write-Host "GOOGLE_CLIENT_SECRET bulunamadi." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Supabase Dashboard'dan almak icin:" -ForegroundColor Cyan
    Write-Host "1. https://supabase.com/dashboard/project/nemwuunbowzuuyvhmehi/settings/functions" -ForegroundColor White
    Write-Host "2. Secrets bolumunde 'GOOGLE_CLIENT_SECRET' degerini kopyalayin (Reveal butonuna tiklayin)" -ForegroundColor White
    Write-Host ""
    Write-Host "VEYA Google Cloud Console'dan:" -ForegroundColor Cyan
    Write-Host "1. https://console.cloud.google.com/apis/credentials" -ForegroundColor White
    Write-Host "2. OAuth 2.0 Client ID'nizi secin ve Client Secret'i kopyalayin" -ForegroundColor White
    Write-Host ""
    $clientSecret = Read-Host "Client Secret'i yapistirin"
}

if (-not $clientId -or -not $clientSecret) {
    Write-Host ""
    Write-Host "HATA: Client ID ve Client Secret gerekli!" -ForegroundColor Red
    Write-Host "Script sonlandiriliyor..." -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "OK: Credentials alindi!" -ForegroundColor Green
Write-Host ""

Write-Host ""
Write-Host "1. Asagidaki URL'yi tarayicida acin:" -ForegroundColor Yellow
Write-Host ""

$scope = "https://www.googleapis.com/auth/drive.file https://www.googleapis.com/auth/spreadsheets.readonly"
# PowerShell'de URL encoding icin [uri]::EscapeDataString kullan
$encodedScope = [uri]::EscapeDataString($scope)
$encodedRedirectUri = [uri]::EscapeDataString($redirectUri)
$authUrl = "https://accounts.google.com/o/oauth2/v2/auth?access_type=offline&scope=$encodedScope&prompt=consent&response_type=code&client_id=$clientId&redirect_uri=$encodedRedirectUri"

Write-Host $authUrl -ForegroundColor Cyan
Write-Host ""

# URL'yi tarayicida ac
Start-Process $authUrl

Write-Host "2. Google hesabinizla giris yapin ve izin verin" -ForegroundColor Yellow
Write-Host "3. Callback server baslatiliyor..." -ForegroundColor Cyan
Write-Host ""

# Basit HTTP listener baslat
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:4000/")
$listener.Start()

Write-Host "OK: Callback server http://localhost:4000/ adresinde calisiyor" -ForegroundColor Green
Write-Host "   (Tarayiciyi kapatip tekrar acabilirsiniz)" -ForegroundColor Gray
Write-Host ""

$code = $null
$timeout = 300 # 5 dakika timeout

try {
    Write-Host "Bekleniyor... (Tarayicida OAuth flow'u tamamlayin)" -ForegroundColor Yellow
    Write-Host ""
    
    # Async olarak context al
    $contextTask = $listener.GetContextAsync()
    $context = $null
    
    # Timeout ile bekle
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($stopwatch.Elapsed.TotalSeconds -lt $timeout) {
        if ($contextTask.IsCompleted) {
            $context = $contextTask.Result
            break
        }
        Start-Sleep -Milliseconds 100
    }
    
    if ($null -eq $context) {
        Write-Host ""
        Write-Host "TIMEOUT: 5 dakika icinde callback alinamadi." -ForegroundColor Red
        Write-Host "Lutfen URL'den code'u manuel olarak kopyalayin:" -ForegroundColor Yellow
        Write-Host "   Ornek: http://localhost:4000/auth/callback?code=4/0Aean...&scope=..." -ForegroundColor Gray
        Write-Host ""
        $code = Read-Host "Authorization Code (veya tam URL)"
    } else {
        $request = $context.Request
        $response = $context.Response
        
        # URL'den code'u cikar
        $queryString = $request.Url.Query
        if ($queryString -match 'code=([^&]+)') {
            $code = $matches[1]
            Write-Host ""
            Write-Host "OK: Code alindi!" -ForegroundColor Green
        } else {
            Write-Host ""
            Write-Host "UYARI: URL'de code parametresi bulunamadi." -ForegroundColor Yellow
            Write-Host "Tam URL: $($request.Url)" -ForegroundColor Gray
            Write-Host ""
            $code = Read-Host "Authorization Code'u manuel olarak girin"
        }
        
        # Basit HTML response gonder
        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>OAuth Success</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        h1 { color: #4CAF50; }
        p { color: #666; }
    </style>
</head>
<body>
    <h1>✅ OAuth Authorization Successful!</h1>
    <p>You can close this window and return to the PowerShell window.</p>
    <p>Bu pencereyi kapatabilirsiniz.</p>
</body>
</html>
"@
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
        $response.ContentLength64 = $buffer.Length
        $response.ContentType = "text/html; charset=utf-8"
        $response.StatusCode = 200
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.Close()
    }
} catch {
    Write-Host ""
    Write-Host "HATA: Callback server hatasi: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Lutfen URL'den code'u manuel olarak kopyalayin:" -ForegroundColor Yellow
    Write-Host ""
    $code = Read-Host "Authorization Code (veya tam URL)"
} finally {
    $listener.Stop()
    Write-Host ""
    Write-Host "Callback server durduruldu." -ForegroundColor Gray
    Write-Host ""
}

# Eger code URL formatindaysa, sadece code'u cikar
if ($code -and $code -match 'code=([^&]+)') {
    $code = $matches[1]
}

if ($code) {
    Write-Host ""
    Write-Host "Token aliniyor..." -ForegroundColor Green
    
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
            Write-Host "OK: Refresh Token basariyla alindi!" -ForegroundColor Green
            Write-Host ""
            Write-Host "Refresh Token:" -ForegroundColor Yellow
            Write-Host $response.refresh_token -ForegroundColor Cyan
            Write-Host ""
            Write-Host "Supabase secrets'a eklemek icin:" -ForegroundColor Yellow
            Write-Host "supabase secrets set GOOGLE_REFRESH_TOKEN=`"$($response.refresh_token)`" --project-ref nemwuunbowzuuyvhmehi" -ForegroundColor Cyan
            Write-Host ""
            
            # Supabase secrets'a ekle
            Write-Host ""
            $addToSupabase = Read-Host "Supabase secrets'a simdi eklemek ister misiniz? (Y/N)"
            if ($addToSupabase -eq "Y" -or $addToSupabase -eq "y") {
                Write-Host ""
                Write-Host "Supabase secrets'a ekleniyor..." -ForegroundColor Green
                Set-Location C:\Users\aslan\Desktop\app
                $secretCommand = "supabase secrets set GOOGLE_REFRESH_TOKEN=`"$($response.refresh_token)`" --project-ref nemwuunbowzuuyvhmehi"
                Write-Host "Komut: $secretCommand" -ForegroundColor Gray
                Invoke-Expression $secretCommand
                if ($LASTEXITCODE -eq 0) {
                    Write-Host ""
                    Write-Host "OK: Refresh Token Supabase secrets'a basariyla eklendi!" -ForegroundColor Green
                } else {
                    Write-Host ""
                    Write-Host "UYARI: Supabase secrets'a ekleme basarisiz. Manuel olarak ekleyin:" -ForegroundColor Yellow
                    Write-Host "supabase secrets set GOOGLE_REFRESH_TOKEN=`"$($response.refresh_token)`" --project-ref nemwuunbowzuuyvhmehi" -ForegroundColor Cyan
                }
            } else {
                Write-Host ""
                Write-Host "Manuel olarak eklemek icin:" -ForegroundColor Yellow
                Write-Host "supabase secrets set GOOGLE_REFRESH_TOKEN=`"$($response.refresh_token)`" --project-ref nemwuunbowzuuyvhmehi" -ForegroundColor Cyan
            }
        } else {
            Write-Host ""
            Write-Host "UYARI: Refresh token alinamadi. Access token alindi:" -ForegroundColor Yellow
            Write-Host $response.access_token -ForegroundColor Cyan
            Write-Host ""
            Write-Host "Not: Refresh token almak icin 'prompt=consent' parametresi kullanilmali." -ForegroundColor Yellow
        }
    } catch {
        Write-Host ""
        Write-Host "HATA: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.Exception.Response) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $responseBody = $reader.ReadToEnd()
            Write-Host "Response: $responseBody" -ForegroundColor Red
        }
    }
} else {
    Write-Host ""
    Write-Host "Code girilmedi, islem iptal edildi." -ForegroundColor Yellow
}
