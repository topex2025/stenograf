#!/bin/bash
# Собирает Stenograf.app. С --release собирает универсальное приложение с CLI.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${STENOGRAF_VERSION:-0.7.0}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Ожидается версия вида 0.7.0"; exit 1; }

APP="build/Stenograf.app"
RELEASE="${1:-}"
if [ "$RELEASE" = "--release" ]; then
  arm=(--scratch-path .build/release-arm64 -c release --triple arm64-apple-macosx13.0)
  intel=(--scratch-path .build/release-x86_64 -c release --triple x86_64-apple-macosx13.0)
  swift build "${arm[@]}"
  swift build "${intel[@]}"
  ARM_BIN=$(swift build "${arm[@]}" --show-bin-path)
  INTEL_BIN=$(swift build "${intel[@]}" --show-bin-path)
else
  swift build --product StenografApp
  BIN_DIR=$(swift build --show-bin-path)
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
if [ "$RELEASE" = "--release" ]; then
  for binary in StenografApp stenograf; do
    lipo -create "$ARM_BIN/$binary" "$INTEL_BIN/$binary" -output "$APP/Contents/MacOS/$binary"
  done
else
  cp "$BIN_DIR/StenografApp" "$APP/Contents/MacOS/StenografApp"
fi
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Stenograf</string>
    <key>CFBundleIdentifier</key><string>ru.stenograf.app</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleExecutable</key><string>StenografApp</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Стенограф записывает встречи по вашему запросу. Аудио остаётся на этом Mac.</string>
</dict>
</plist>
PLIST

if [ "${1:-}" = "--release" ]; then
  codesign --force --sign - "$APP/Contents/MacOS/stenograf"
  codesign --force --sign - "$APP"
  codesign --verify --deep --strict "$APP"
fi
echo "Готово: $APP"
echo "Запуск: open $APP  (первый раз система спросит доступ к микрофону)"
