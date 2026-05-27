@echo off
setlocal

if "%~1"=="" (
    echo Usage: build_prod_apk.bat https://your-backend-url.onrender.com
    exit /b 1
)

cd /d "%~dp0"

echo Building APK with backend URL: %~1
flutter build apk --release --dart-define=VOICE_TO_SHEET_API_URL=%~1

if errorlevel 1 (
    echo APK build failed.
    exit /b 1
)

echo.
echo APK created successfully.
echo Output: build\app\outputs\flutter-apk\app-release.apk
