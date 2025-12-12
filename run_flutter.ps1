# Flutter komutlarını doğru dizinde çalıştırmak için yardımcı script
# Kullanım: .\run_flutter.ps1 <komut>
# Örnek: .\run_flutter.ps1 "flutter pub get"

param(
    [Parameter(Mandatory=$true)]
    [string]$Command
)

# Flutter projesinin root dizini
$flutterRoot = "C:\Users\aslan\Desktop\app\app"

# Dizine geç
Set-Location $flutterRoot

# pubspec.yaml kontrolü
if (-not (Test-Path "pubspec.yaml")) {
    Write-Host "HATA: pubspec.yaml bulunamadı!" -ForegroundColor Red
    Write-Host "Mevcut dizin: $PWD" -ForegroundColor Yellow
    exit 1
}

Write-Host "Flutter projesi dizini: $PWD" -ForegroundColor Green
Write-Host "Komut çalıştırılıyor: $Command" -ForegroundColor Cyan
Write-Host ""

# Komutu çalıştır
Invoke-Expression $Command

