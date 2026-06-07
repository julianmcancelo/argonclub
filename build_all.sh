#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "[1/7] Stop Gradle daemons..."
./android/gradlew.bat --stop >/dev/null 2>&1 || true

echo "[2/7] Flutter clean..."
flutter clean

echo "[3/7] Flutter pub get..."
flutter pub get

echo "[4/7] APK DEBUG..."
flutter build apk --debug

echo "[5/7] APK RELEASE..."
flutter build apk --release

echo "[6/7] Windows RELEASE..."
taskkill /F /IM zuper_app.exe >/dev/null 2>&1 || true
flutter build windows --release

echo "[7/7] Done."
echo "APK Debug:   build/app/outputs/flutter-apk/app-debug.apk"
echo "APK Release: build/app/outputs/flutter-apk/app-release.apk"
echo "EXE:         build/windows/x64/runner/Release/zuper_app.exe"
