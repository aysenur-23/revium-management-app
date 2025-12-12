# Flutter APK Derleme ve Kurulum Scripti
Write-Host "Flutter APK derleme başlatılıyor..." -ForegroundColor Green

# app klasörüne git
Set-Location -Path "app"

# Flutter bağımlılıklarını kontrol et
Write-Host "Flutter bağımlılıkları kontrol ediliyor..." -ForegroundColor Yellow
flutter pub get

# APK derle
Write-Host "APK derleniyor (bu biraz zaman alabilir)..." -ForegroundColor Yellow
flutter build apk --release

# APK dosyasının yolunu bul
$apkPath = "build\app\outputs\flutter-apk\app-release.apk"

if (Test-Path $apkPath) {
    Write-Host "APK başarıyla derlendi: $apkPath" -ForegroundColor Green
    
    # ADB ile telefona kur
    Write-Host "Telefona kuruluyor..." -ForegroundColor Yellow
    
    # ADB'nin yolunu bul (Android SDK içinde olabilir)
    $adbPath = $null
    
    # Yaygın ADB yolları
    $possibleAdbPaths = @(
        "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
        "$env:USERPROFILE\AppData\Local\Android\Sdk\platform-tools\adb.exe",
        "C:\Android\Sdk\platform-tools\adb.exe",
        "$env:ANDROID_HOME\platform-tools\adb.exe"
    )
    
    foreach ($path in $possibleAdbPaths) {
        if (Test-Path $path) {
            $adbPath = $path
            break
        }
    }
    
    if ($adbPath) {
        Write-Host "ADB bulundu: $adbPath" -ForegroundColor Green
        
        # Cihazları kontrol et
        Write-Host "Bağlı cihazlar kontrol ediliyor..." -ForegroundColor Yellow
        & $adbPath devices
        
        # APK'yı kur
        Write-Host "APK kuruluyor..." -ForegroundColor Yellow
        & $adbPath install -r $apkPath
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "APK başarıyla kuruldu!" -ForegroundColor Green
        } else {
            Write-Host "APK kurulumu başarısız oldu. Hata kodu: $LASTEXITCODE" -ForegroundColor Red
            Write-Host "Manuel olarak kurmak için: adb install -r $apkPath" -ForegroundColor Yellow
        }
    } else {
        Write-Host "ADB bulunamadı. APK dosyası: $((Get-Location).Path)\$apkPath" -ForegroundColor Yellow
        Write-Host "Manuel olarak kurmak için:" -ForegroundColor Yellow
        Write-Host "1. Android SDK platform-tools'u PATH'e ekleyin" -ForegroundColor Yellow
        Write-Host "2. Veya şu komutu çalıştırın: adb install -r $apkPath" -ForegroundColor Yellow
    }
} else {
    Write-Host "APK dosyası bulunamadı: $apkPath" -ForegroundColor Red
    Write-Host "Derleme başarısız olmuş olabilir." -ForegroundColor Red
}

# Ana dizine dön
Set-Location -Path ".."

Write-Host "İşlem tamamlandı!" -ForegroundColor Green

