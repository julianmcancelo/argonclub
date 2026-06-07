@echo off
setlocal enabledelayedexpansion

cd /d "%~dp0"

echo [1/7] Stop Gradle daemons...
call .\android\gradlew.bat --stop >nul 2>nul

echo [2/7] Flutter clean...
call flutter clean
if errorlevel 1 goto :fail

echo [3/7] Flutter pub get...
call flutter pub get
if errorlevel 1 goto :fail

echo [4/7] APK DEBUG...
call flutter build apk --debug
if errorlevel 1 goto :fail

echo [5/7] APK RELEASE...
call flutter build apk --release
if errorlevel 1 goto :fail

echo [6/7] Windows RELEASE...
call taskkill /F /IM zuper_app.exe >nul 2>nul
call flutter build windows --release
if errorlevel 1 goto :fail

echo [7/7] Done.
echo APK Debug:   build\app\outputs\flutter-apk\app-debug.apk
echo APK Release: build\app\outputs\flutter-apk\app-release.apk
echo EXE:         build\windows\x64\runner\Release\zuper_app.exe
exit /b 0

:fail
echo Build failed with exit code %errorlevel%
exit /b %errorlevel%
