#!/bin/bash
# Собирает меню-бар приложение Stenograf.app (без подписи — для локального запуска).
# Для продажи понадобится Apple Developer ID + нотаризация (см. docs/DECISIONS.md D8).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build --product StenografApp

APP="Stenograf.app"
rm -rf "$APP" "build/$APP"
mkdir -p "build/$APP/Contents/MacOS"
cp .build/debug/StenografApp "build/$APP/Contents/MacOS/StenografApp"
cat > "build/$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Stenograf</string>
    <key>CFBundleIdentifier</key><string>ru.stenograf.app</string>
    <key>CFBundleVersion</key><string>0.1.0</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleExecutable</key><string>StenografApp</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Стенограф записывает встречи по вашему запросу. Аудио остаётся на этом Mac.</string>
</dict>
</plist>
PLIST

echo "Готово: build/$APP"
echo "Запуск: open build/$APP  (первый раз система спросит доступ к микрофону)"
