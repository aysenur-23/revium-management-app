# Service Account bilgilerini Firebase secrets'a ekleme scripti
# Kullanım: JSON dosyasını backend klasörüne kaydedin, sonra bu scripti çalıştırın

Write-Host "`n🔐 Service Account Secrets Ayarlama Scripti" -ForegroundColor Cyan
Write-Host "=" * 50 -ForegroundColor Gray

# JSON dosyasını bul
$jsonFiles = Get-ChildItem -Path . -Filter "*.json" | Where-Object { 
    $_.Name -like "*firebase*" -or 
    $_.Name -like "*service*" -or 
    $_.Name -like "*admin*" 
}

if ($jsonFiles.Count -eq 0) {
    Write-Host "`n❌ JSON dosyası bulunamadı!" -ForegroundColor Red
    Write-Host "`n💡 Lütfen Firebase Console'dan Service Account key dosyasını indirin:" -ForegroundColor Yellow
    Write-Host "   https://console.firebase.google.com/project/management-app0/settings/serviceaccounts/adminsdk" -ForegroundColor Gray
    Write-Host "`n   Adımlar:" -ForegroundColor White
    Write-Host "   1. 'Generate new private key' butonuna tıklayın" -ForegroundColor Gray
    Write-Host "   2. JSON dosyasını indirin" -ForegroundColor Gray
    Write-Host "   3. JSON dosyasını backend klasörüne kaydedin" -ForegroundColor Gray
    Write-Host "   4. Bu scripti tekrar çalıştırın" -ForegroundColor Gray
    exit 1
}

# İlk JSON dosyasını kullan
$jsonFile = $jsonFiles[0]
Write-Host "`n✅ JSON dosyası bulundu: $($jsonFile.Name)" -ForegroundColor Green

# JSON dosyasını oku
try {
    $jsonContent = Get-Content $jsonFile.FullName -Raw | ConvertFrom-Json
    
    if (-not $jsonContent.client_email) {
        Write-Host "`n❌ JSON dosyasında 'client_email' bulunamadı!" -ForegroundColor Red
        exit 1
    }
    
    if (-not $jsonContent.private_key) {
        Write-Host "`n❌ JSON dosyasında 'private_key' bulunamadı!" -ForegroundColor Red
        exit 1
    }
    
    $email = $jsonContent.client_email
    $privateKey = $jsonContent.private_key
    
    Write-Host "`n📧 Email: $email" -ForegroundColor Cyan
    Write-Host "🔑 Private Key: $($privateKey.Substring(0, [Math]::Min(50, $privateKey.Length)))..." -ForegroundColor Gray
    
    # Firebase secrets'a ekle
    Write-Host "`n🚀 Firebase secrets'a ekleniyor..." -ForegroundColor Yellow
    
    # Email ekle
    Write-Host "`n1️⃣ GOOGLE_SERVICE_ACCOUNT_EMAIL ekleniyor..." -ForegroundColor Cyan
    $email | firebase functions:secrets:set GOOGLE_SERVICE_ACCOUNT_EMAIL
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   ✅ Email başarıyla eklendi!" -ForegroundColor Green
    } else {
        Write-Host "   ❌ Email eklenirken hata oluştu!" -ForegroundColor Red
        exit 1
    }
    
    # Private Key ekle
    Write-Host "`n2️⃣ GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY ekleniyor..." -ForegroundColor Cyan
    $privateKey | firebase functions:secrets:set GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   ✅ Private Key başarıyla eklendi!" -ForegroundColor Green
    } else {
        Write-Host "   ❌ Private Key eklenirken hata oluştu!" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "`n✅ Tüm secrets başarıyla eklendi!" -ForegroundColor Green
    Write-Host "`n🚀 Şimdi deploy'u deneyebilirsiniz:" -ForegroundColor Yellow
    Write-Host "   firebase deploy --only functions" -ForegroundColor Gray
    
} catch {
    Write-Host "`n❌ JSON dosyası okunamadı: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

