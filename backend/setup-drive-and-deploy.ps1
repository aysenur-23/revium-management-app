# Drive secret'larini ayarlayip functions deploy eden tek script
#
# Calistirma (proje kokunden):
#   .\backend\setup-drive-and-deploy.ps1
# veya backend icinden:
#   .\setup-drive-and-deploy.ps1
#
# Onkosul: Once get-refresh-token.ps1 ile refresh_token.txt olusturulmali.

$ErrorActionPreference = "Stop"
$backendRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$tokenFile = Join-Path $backendRoot "refresh_token.txt"

# Proje kokunu bul (firebase.json burada olmali)
$projectRoot = Split-Path -Parent $backendRoot
if (-not (Test-Path (Join-Path $projectRoot "firebase.json"))) {
    $projectRoot = $backendRoot
}
Push-Location $projectRoot

try {
    Write-Host "=== Drive secret + deploy ===" -ForegroundColor Green
    Write-Host ""

    # 1) GOOGLE_DRIVE_ROOT_FOLDER_ID (maliyet-app ana klasor)
    $folderId = "1iJJ3qhYzC8B53gbJfMTEkdJGR0gjCmM_"
    Write-Host "[1/3] GOOGLE_DRIVE_ROOT_FOLDER_ID ayarlaniyor..." -ForegroundColor Cyan
    $folderId | firebase functions:secrets:set GOOGLE_DRIVE_ROOT_FOLDER_ID
    if ($LASTEXITCODE -ne 0) { throw "GOOGLE_DRIVE_ROOT_FOLDER_ID set edilemedi" }
    Write-Host "  OK" -ForegroundColor Green
    Write-Host ""

    # 2) GOOGLE_REFRESH_TOKEN (dosyadan)
    if (-not (Test-Path $tokenFile)) {
        Write-Host "UYARI: refresh_token.txt bulunamadi: $tokenFile" -ForegroundColor Yellow
        Write-Host "Once get-refresh-token.ps1 calistirip token alin, sonra bu scripti tekrar calistirin." -ForegroundColor Yellow
        exit 1
    }
    Write-Host "[2/3] GOOGLE_REFRESH_TOKEN dosyadan ayarlaniyor..." -ForegroundColor Cyan
    Get-Content $tokenFile -Raw | firebase functions:secrets:set GOOGLE_REFRESH_TOKEN
    if ($LASTEXITCODE -ne 0) { throw "GOOGLE_REFRESH_TOKEN set edilemedi" }
    Write-Host "  OK" -ForegroundColor Green
    Write-Host ""

    # 3) Deploy
    Write-Host "[3/3] firebase deploy --only functions..." -ForegroundColor Cyan
    firebase deploy --only functions
    if ($LASTEXITCODE -ne 0) { throw "Deploy basarisiz" }
    Write-Host ""
    Write-Host "Bitti. Backend /health ile driveAuthType: oauth2 kontrol edebilirsiniz." -ForegroundColor Green
} finally {
    Pop-Location
}
