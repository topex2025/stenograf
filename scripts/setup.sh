#!/bin/bash
# Стенограф — установка «с нуля» на чистый Mac (macOS 13+, Apple Silicon или Intel).
# Ставит: whisper.cpp + модель + Codex CLI (мост к подписке ChatGPT), собирает приложение.
# В конце предлагает войти в ChatGPT. Всё локально, без ключей.
set -euo pipefail
cd "$(dirname "$0")/.."

bold() { printf "\033[1m%s\033[0m\n" "$1"; }

bold "== 1/5. Homebrew-зависимости (whisper.cpp, node для codex)"
command -v brew >/dev/null || { echo "Сначала поставь Homebrew: https://brew.sh"; exit 1; }
command -v whisper-cli >/dev/null || brew install whisper-cpp
command -v npm >/dev/null || brew install node

bold "== 2/5. Модель Whisper (один раз, ~500 МБ, с докачкой при обрывах)"
MODEL_DIR="$HOME/.cache/whisper"
MODEL="$MODEL_DIR/ggml-medium-q5_0.bin"
mkdir -p "$MODEL_DIR"
if [ ! -f "$MODEL" ]; then
  URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium-q5_0.bin"
  for i in $(seq 1 60); do
    curl -L -C - --connect-timeout 20 --max-time 540 -o "$MODEL" "$URL" && break
    echo "  попытка $i оборвалась — докачиваю…"; sleep 3
  done
else
  echo "  модель уже на месте"
fi

bold "== 3/5. Codex CLI — мост к подписке ChatGPT (~/.stenograf/cli)"
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
else
  echo "  codex уже установлен"
fi

bold "== 4/6. Сборка Стенографа"
swift build
./scripts/make-app.sh

bold "== 5/6. Нейроголос Piper (озвучка ответов — человеческий голос вместо системного)"
if [ ! -x "$HOME/.stenograf/tts/bin/piper" ]; then
  python3 -m venv "$HOME/.stenograf/tts"
  "$HOME/.stenograf/tts/bin/pip" install -q piper-tts || echo "  (не вышло — останется системный голос)"
fi
VOICES="$HOME/.stenograf/voices"
mkdir -p "$VOICES"
if [ ! -s "$VOICES/ru_RU-dmitri-medium.onnx" ]; then
  for f in ru_RU-dmitri-medium.onnx ru_RU-dmitri-medium.onnx.json; do
    for i in $(seq 1 40); do
      curl -sL -C - --connect-timeout 20 --max-time 300 -o "$VOICES/$f" \
        "https://huggingface.co/rhasspy/piper-voices/resolve/main/ru/ru_RU/dmitri/medium/$f" && break
      sleep 3
    done
  done
fi

bold "== 6/6. Вход в ChatGPT (подписка Plus/Pro)"
.build/debug/stenograf login

bold "Готово! Приложение: build/Stenograf.app · проверка: .build/debug/stenograf config"
