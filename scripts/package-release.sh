#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

version="${1:?Укажи версию релиза, например 0.7.0}"
STENOGRAF_VERSION="$version" bash scripts/make-app.sh --release
lipo build/Stenograf.app/Contents/MacOS/StenografApp -verify_arch arm64 x86_64
lipo build/Stenograf.app/Contents/MacOS/stenograf -verify_arch arm64 x86_64

name="Stenograf-$version"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/$name/scripts"
ditto build/Stenograf.app "$stage/$name/Stenograf.app"
cp scripts/setup.sh "$stage/$name/scripts/"
cp LICENSE "$stage/$name/"
cat > "$stage/$name/Установка.txt" <<'TXT'
Стенограф для macOS 13 и новее, Apple Silicon и Intel.

1. Распакуйте архив целиком. Установите Homebrew с https://brew.sh, если его ещё нет.
2. Откройте Terminal в распакованной папке и выполните:
       bash scripts/setup.sh --prebuilt
   Скрипт установит Whisper, загрузит модель (около 500 МБ) и предложит войти в ChatGPT.
3. Откройте Stenograf.app и разрешите доступ к микрофону при первой записи.

Сборка не нотарифицирована Apple. Если macOS покажет предупреждение, сначала
убедитесь, что скачали архив с официальной страницы проекта. Инструкция Apple:
https://support.apple.com/en-us/102445
Релиз: https://github.com/topex2025/stenograf/releases/latest
TXT

mkdir -p build/releases
archive="$name-macos-universal.zip"
ditto -c -k --keepParent "$stage/$name" "build/releases/$archive"
(cd build/releases && shasum -a 256 "$archive" > "$archive.sha256")
printf 'Архив: build/releases/%s\n' "$archive"
