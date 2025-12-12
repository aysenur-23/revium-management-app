@echo off
chcp 65001 >nul
echo ========================================
echo Flutter APK Derleme ve Kurulum
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
echo 1. Flutter kontrol ediliyor...
where flutter >nul 2>&1
if errorlevel 1 (
    echo HATA: Flutter bulunamadi!
    echo PATH'i kontrol edin veya Flutter'i yeniden kurun.
    pause
    exit /b 1
)

flutter --version >nul 2>&1
if errorlevel 1 (
    echo HATA: Flutter calismiyor!
    pause
    exit /b 1
)

echo    Flutter bulundu!
echo.

echo 2. Flutter bagimliliklari kontrol ediliyor...
flutter pub get
if errorlevel 1 (
    echo HATA: flutter pub get basarisiz!
    pause
    exit /b 1
)

echo.
echo 3. APK derleniyor (bu biraz zaman alabilir, lutfen bekleyin)...
echo.
flutter build apk --release
if errorlevel 1 (
    echo.
    echo HATA: APK derleme basarisiz!
    pause
    exit /b 1
)

set APK_PATH=%CD%\build\app\outputs\flutter-apk\app-release.apk
if not exist "%APK_PATH%" (
    echo HATA: APK dosyasi bulunamadi: %APK_PATH%
    pause
    exit /b 1
)

echo.
echo 4. Bagli cihazlar kontrol ediliyor...
where adb >nul 2>&1
if errorlevel 1 (
    echo UYARI: ADB bulunamadi!
    echo APK dosyasi: %APK_PATH%
    echo.
    echo Manuel kurulum icin:
    echo   adb install -r "%APK_PATH%"
    pause
    exit /b 0
)

adb devices
echo.

echo 5. APK telefona kuruluyor...
adb install -r "%APK_PATH%"
if errorlevel 1 (
    echo.
    echo HATA: APK kurulumu basarisiz!
    echo.
    echo Kontrol edin:
    echo 1. Telefon USB ile bagli mi?
    echo 2. USB hata ayiklama acik mi? (Ayarlar -^> Telefon hakkinda -^> Yapim numarasi'na 7 kez tiklayin)
    echo 3. Telefonda kurulum izni verildi mi?
    echo.
    echo APK dosyasi: %APK_PATH%
    echo Manuel kurulum icin: adb install -r "%APK_PATH%"
    pause
    exit /b 1
)

echo.
echo ========================================
echo APK basariyla derlendi ve kuruldu!
echo ========================================
echo.

pause

