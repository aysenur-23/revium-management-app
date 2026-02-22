@echo off
title Expense Tracker - Cloud Setup
color 0A

echo ===================================================
echo   EXPENSE TRACKER - BULUT KURULUM SIHIRBAZI
echo ===================================================
echo.
echo Bu islem uygulamanizin her yerden erisilebilir olmasini saglayacak.
echo.

echo [1/3] Firebase Araclari Kontrol Ediliyor...
call npm list -g firebase-tools >nul 2>&1
if %errorlevel% neq 0 (
    echo Firebase Tools yukleniyor...
    call npm install -g firebase-tools
) else (
    echo Firebase Tools zaten yuklu.
)

echo.
echo [2/3] Giris Yapiliyor...
echo Lutfen acilan tarayici penceresinden Google hesabinizi secin.
call firebase login

echo.
echo [3/3] Buluta Yukleniyor (Deploy)...
cd functions
call npm install
call firebase deploy --only functions

echo.
echo ===================================================
echo   ISLEM TAMAMLANDI!
echo ===================================================
echo.
echo Yukarida "Function URL" kisminda bir link gormelisiniz.
echo Ornek: https://us-central1-....cloudfunctions.net/api
echo.
echo LUTFEN O LINKI KOPYALAYIP AI ASISTANA GONDERIN.
echo.
pause
