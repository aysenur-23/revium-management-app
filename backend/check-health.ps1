# Backend health ve driveAuthType kontrolu
$url = "https://us-central1-manage-d9a18.cloudfunctions.net/api/health"
Write-Host "GET $url" -ForegroundColor Cyan
$r = Invoke-RestMethod -Uri $url -Method Get
Write-Host ""
Write-Host "driveAuthType: " -NoNewline
Write-Host $r.driveAuthType -ForegroundColor $(if ($r.driveAuthType -eq 'oauth2') { 'Green' } else { 'Yellow' })
Write-Host "status: $($r.status)"
Write-Host "serviceAccountEmail: $($r.serviceAccountEmail)"
Write-Host ""
if ($r.driveAuthType -eq 'oauth2') {
    Write-Host "Drive OAuth kullaniliyor; kota hatasi duzeldi olmali." -ForegroundColor Green
} else {
    Write-Host "Drive Service Account kullaniliyor. GOOGLE_REFRESH_TOKEN secret'ini kontrol edin." -ForegroundColor Yellow
}
