# Архитектура Stenograf

```
┌───────────────────────────  Mac (всё локально)  ───────────────────────────┐
│                                                                             │
│  [Микрофон]──► AudioRecorder ──► audio.wav (16k mono)                       │
│                                     │                                       │
│                                     ▼                                       │
│                             WhisperCLI (whisper.cpp, сабпроцесс)            │
│                                     │                                       │
│                       transcript.md + transcript.json (сегменты)            │
│                                     │                                       │
│                                     ▼                                       │
│      MeetingStore (~/Library/Application Support/Stenograf/meetings)        │
│                                     │                                       │
│                                     ▼                                       │
│                          Brains (протокол BrainProvider)                    │
│        ┌───────────────┬────────────────────┬───────────────┐               │
│        ▼               ▼                    ▼               ▼               │
│  OpenAI-compat   Anthropic-compat        Ollama      [M2] Codex/Claude     │
│  /chat/compl.    /v1/messages            /api/chat    подписочный OAuth    │
│  (OpenAI API,    (GLM Coding Plan,       (локально)                       │
│   OpenRouter)     Anthropic API)                                           │
│        │               │                    │                              │
│        └───────────────┴───────── summaries/*.md (протокол, резюме)        │
│                                                                              │
│  UI: CLI `stenograf`  +  MenuBarExtra-приложение (SwiftUI)                  │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Модули (SwiftPM)

- **StenografCore** (библиотека)
  - `Models.swift` — Meeting, AppConfig, BrainConfig.
  - `Brains/` — протокол `BrainProvider` + три реализации и промпт-шаблоны.
  - `Transcribe/WhisperCLI.swift` — обёртка сабпроцесса whisper-cli (txt + json сегменты).
  - `Record/AudioRecorder.swift` — AVAudioRecorder → wav 16k mono.
  - `Store/MeetingStore.swift` — файловое хранилище встреч.
- **stenograf** (CLI): record / transcribe / summarize / config.
- **StenografApp** (menu-bar, M1).

## Контракты

`BrainProvider.complete(system:String, user:String) async throws -> String` — единственный метод; шаблоны промптов живут в Core и переопределяются файлами в `~/.stenograf/prompts/`.

## Приватность
Аудио не покидает Mac (Whisper локальный). Наружу уходит только текст транскрипта в явно выбранный пользователем мозг. Никакой телеметрии.
