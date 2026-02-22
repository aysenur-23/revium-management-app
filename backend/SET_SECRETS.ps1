# Firebase Secret'lari dosyadan set et (yapistirma/Ctrl+Z gerekmez)
# Proje kokunden calistirin:  cd "c:\Users\aslan\Desktop\Desktop\Desktop\app"  sonra  .\backend\SET_SECRETS.ps1

$backend = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location (Split-Path -Parent $backend)

Write-Host "GOOGLE_REFRESH_TOKEN ayarlaniyor..." -ForegroundColor Cyan
Get-Content "$backend\refresh_token.txt" -Raw | firebase functions:secrets:set GOOGLE_REFRESH_TOKEN

Write-Host "GOOGLE_CLIENT_ID ayarlaniyor..." -ForegroundColor Cyan
Get-Content "$backend\secret_GOOGLE_CLIENT_ID.txt" -Raw | firebase functions:secrets:set GOOGLE_CLIENT_ID

Write-Host "GOOGLE_CLIENT_SECRET ayarlaniyor..." -ForegroundColor Cyan
Get-Content "$backend\secret_GOOGLE_CLIENT_SECRET.txt" -Raw | firebase functions:secrets:set GOOGLE_CLIENT_SECRET

Write-Host "" 
Write-Host "Tamam. Simdi: firebase deploy --only functions" -ForegroundColor Green
