#!/bin/bash
# Стенограф — установка «с нуля» на чистый Mac (macOS 13+, Apple Silicon или Intel).
# Ставит: whisper.cpp + модель + Codex CLI (мост к подписке ChatGPT), собирает приложение.
# В конце предлагает войти в ChatGPT. Всё локально, без ключей.
set -euo pipefail
cd "$(dirname "$0")/.."

PREBUILT="${1:-}"
if [ "$PREBUILT" = "--prebuilt" ]; then
  APP="Stenograf.app"
  CLI="$APP/Contents/MacOS/stenograf"
  [ -x "$CLI" ] || { echo "В архиве не нашёлся Stenograf.app. Распакуй архив целиком."; exit 1; }
else
  APP="build/Stenograf.app"
  CLI=".build/debug/stenograf"
fi

bold() { printf "\033[1m%s\033[0m\n" "$1"; }

bold "== 1/6. Homebrew-зависимости (whisper.cpp, node для codex)"
command -v brew >/dev/null || { echo "Сначала поставь Homebrew: https://brew.sh"; exit 1; }
command -v whisper-cli >/dev/null || brew install whisper-cpp
command -v npm >/dev/null || brew install node

bold "== 2/6. Модель Whisper (один раз, ~500 МБ, с докачкой при обрывах)"
MODEL_DIR="$HOME/.cache/whisper"
MODEL="$MODEL_DIR/ggml-medium-q5_0.bin"
mkdir -p "$MODEL_DIR"
if [ ! -s "$MODEL" ] || [ "$(wc -c < "$MODEL" | tr -d ' ')" != "539212467" ]; then
  URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium-q5_0.bin"
  partial="$MODEL.download"
  if [ ! -s "$partial" ] || [ "$(wc -c < "$partial" | tr -d ' ')" != "539212467" ]; then
    curl --fail --location --continue-at - --retry 3 --connect-timeout 20 --max-time 540 \
      -o "$partial" "$URL" || { echo "Модель Whisper не скачалась. Запусти установку ещё раз, чтобы продолжить."; exit 1; }
  fi
  [ "$(wc -c < "$partial" | tr -d ' ')" = "539212467" ] || { echo "Размер модели Whisper не совпал. Удали $partial и повтори установку."; exit 1; }
  mv -f "$partial" "$MODEL"
else
  echo "  модель уже на месте"
fi

bold "== 3/6. Codex CLI — мост к подписке ChatGPT (~/.stenograf/cli)"
CODEX_BIN="$HOME/.stenograf/cli/bin/codex"
if [ ! -x "$CODEX_BIN" ]; then
  mkdir -p "$HOME/.stenograf/cli"
  ARCH=$(uname -m)
  if [ "$ARCH" = "arm64" ]; then ALIAS="@openai/codex-darwin-arm64@npm:@openai/codex@latest-darwin-arm64"
  else ALIAS="@openai/codex-darwin-x64@npm:@openai/codex@latest-darwin-x64"; fi
  for i in 1 2 3; do
    npm install -g --prefix "$HOME/.stenograf/cli" @openai/codex "$ALIAS" && break
    echo "  npm попытка $i не прошла, пробую снова…"; sleep 5
  done
  [ -x "$CODEX_BIN" ] || { echo "Не удалось установить Codex CLI. Повтори установку."; exit 1; }
else
  echo "  codex уже установлен"
fi

if [ "$PREBUILT" = "--prebuilt" ]; then
  bold "== 4/6. Готовое приложение найдено"
else
  bold "== 4/6. Сборка Стенографа"
  swift build
  bash scripts/make-app.sh
fi

bold "== 5/6. Нейроголос Piper (озвучка ответов — человеческий голос вместо системного)"
PIPER_DIR="$HOME/.stenograf/tts"
if [ ! -x "$PIPER_DIR/bin/piper" ]; then
  if command -v python3 >/dev/null && python3 -m venv "$PIPER_DIR"; then
    "$PIPER_DIR/bin/pip" install -q piper-tts || true
  fi
fi
if [ -x "$PIPER_DIR/bin/piper" ]; then
  VOICES="$HOME/.stenograf/voices"
  mkdir -p "$VOICES"
  for f in ru_RU-dmitri-medium.onnx ru_RU-dmitri-medium.onnx.json; do
    if [ ! -s "$VOICES/$f" ]; then
      if curl --fail --silent --show-error --location --retry 2 --connect-timeout 20 --max-time 180 \
          -o "$VOICES/$f.download" "https://huggingface.co/rhasspy/piper-voices/resolve/main/ru/ru_RU/dmitri/medium/$f"; then
        mv -f "$VOICES/$f.download" "$VOICES/$f"
      else
        echo "  голос Piper не скачался — останется системный голос"
        break
      fi
    fi
  done
else
  echo "  Piper не установлен — останется системный голос"
fi

bold "== 6/6. Вход в ChatGPT (подписка Plus/Pro)"
"$CLI" config
"$CLI" login

bold "Готово! Открой $APP"
