@echo off
echo ========================================
echo APK Telefona Kurulum
echo ========================================
echo.

set APK_PATH=app\build\app\outputs\flutter-apk\app-release.apk

if not exist "%APK_PATH%" (
    echo HATA: APK dosyasi bulunamadi: %APK_PATH%
    echo Lutfen once APK'yi derleyin (build_apk.bat)
    pause
    exit /b 1
)

echo Bagli cihazlar kontrol ediliyor...
adb devices
echo.

echo APK telefona kuruluyor...
adb install -r "%APK_PATH%"
if errorlevel 1 (
    echo.
    echo HATA: APK kurulumu basarisiz!
    echo.
    echo Kontrol edin:
    echo 1. Telefon USB ile bagli mi?
    echo 2. USB hata ayiklama acik mi?
    echo 3. ADB kurulu mu?
    pause
    exit /b 1
)

echo.
echo ========================================
echo APK basariyla kuruldu!
echo ========================================
echo.

pause

