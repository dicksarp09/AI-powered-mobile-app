@echo off
REM test_ai.bat - Run AI tests in terminal (Windows)

echo 🤖 AI Model Tester
echo ==================
echo.

REM Check if dart is available
dart --version >nul 2>&1
if %errorlevel% equ 0 (
    echo ✅ Dart found
    echo.
    dart test_ai.dart %*
    goto :end
)

REM Check if flutter is available
flutter --version >nul 2>&1
if %errorlevel% equ 0 (
    echo ✅ Flutter found (using Flutter's Dart)
    echo.
    flutter dart test_ai.dart %*
    goto :end
)

echo ❌ Neither Dart nor Flutter found in PATH
echo.
echo Please install Flutter:
echo   https://flutter.dev/docs/get-started/install
echo.
echo Or run the Flutter tests instead:
echo   flutter test
pause
exit /b 1

:end
pause
