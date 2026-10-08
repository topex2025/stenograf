#!/bin/bash
# Одна команда проверки: сборка + все тесты (unit + E2E на реальном whisper) + смоук CLI.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> swift build"
swift build

echo "==> swift test (unit + E2E транскрипция, если есть whisper-cli и модель)"
swift test

echo "==> CLI smoke: config"
.build/debug/stenograf config || {
  echo "!! команда config упала" >&2
  exit 1
}

echo "==> CLI smoke: help"
.build/debug/stenograf help >/dev/null

echo "OK: всё зелёное."
