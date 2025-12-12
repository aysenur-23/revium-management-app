@echo off
chcp 65001 >nul
echo ========================================
echo Flutter APK Derleme
echo ========================================
echo.

REM Script'in bulunduğu klasöre git
cd /d "%~dp0"

REM app klasörüne git
if not exist "app" (
    echo HATA: app klasoru bulunamadi!
    echo Mevcut konum: %CD%
    pause
    exit /b 1
)

cd app

REM Flutter'ın çalışıp çalışmadığını kontrol et
echo Flutter kontrol ediliyor...
where flutter >nul 2>&1
if errorlevel 1 (
    echo HATA: Flutter bulunamadi!
    echo PATH'i kontrol edin veya Flutter'i yeniden kurun.
    pause
    exit /b 1
)

flutter --version
if errorlevel 1 (
    echo HATA: Flutter calismiyor!
    pause
    exit /b 1
)

echo.
echo Flutter basariyla bulundu!
echo.

echo Flutter bagimliliklari kontrol ediliyor...
flutter pub get
if errorlevel 1 (
    echo HATA: flutter pub get basarisiz!
    pause
    exit /b 1
)

echo.
echo APK derleniyor (bu biraz zaman alabilir, lutfen bekleyin)...
echo.
flutter build apk --release
if errorlevel 1 (
    echo.
    echo HATA: APK derleme basarisiz!
    pause
    exit /b 1
)

echo.
echo ========================================
echo APK basariyla derlendi!
echo ========================================
echo.
set APK_PATH=%CD%\build\app\outputs\flutter-apk\app-release.apk
if exist "%APK_PATH%" (
    echo APK konumu: %APK_PATH%
    echo.
    echo Dosya boyutu:
    dir "%APK_PATH%" | find "app-release.apk"
) else (
    echo UYARI: APK dosyasi bulunamadi!
)

echo.
pause

