# Стенограф 🎙️

**EN:** Stenograf is an open-source meeting memory for Mac: record a meeting, transcribe **locally** (whisper.cpp, ~100 languages auto-detected), and get a protocol with action items — powered by **your existing ChatGPT subscription** (official Codex sign-in, no API keys). Also: instant summary, Q&A over all your meetings (voice or text), neural voice answers (Piper), full-text search with Russian morphology. No Stenograf subscription or telemetry. Cloud providers receive transcript text to generate reports. UI: Russian / English / Español.

**Открытая память переговоров для Mac.** Записывает встречу, транскрибирует **локально** (whisper.cpp) и делает протокол «кто → что → кому → срок» через **вашу подписку ChatGPT** — вход вашим логином, без API-ключей. У Стенографа нет своей подписки и телеметрии. Для отчёта через ChatGPT текст встречи передаётся на обработку.

> Позиционирование: бесплатная альтернатива Granola/PLAUD для тех, у кого уже есть ChatGPT (или GLM/Claude/Ollama — на выбор).

## Как работает вход через ChatGPT (без ключей)

Стенограф использует официальный Codex CLI и **ваш подписочный вход** — тот же механизм «Sign in with ChatGPT», что у [OpenClaw](https://docs.openclaw.ai/concepts/oauth):

1. Заходите один раз: `stenograf login` → браузер → логин ChatGPT (Plus/Pro).
2. Токен подписки живёт в `~/.codex/auth.json`, обновляется сам. Стенограф его только переиспользует.
3. Суммаризация гоняется через `codex exec` — официальную программу OpenAI, все лимиты и правила вашей подписки соблюдаются автоматически.

## Что умеет (v0.2)

- ⏺ Запись встречи с микрофона (окно приложения, меню-бар или CLI)
- ⚡ **Автопротокол**: остановил запись — Стенограф сам транскрибирует и делает протокол (отключается в конфиге `autoProtocol`)
- 🌐 **Автодетект языка** (~100 языков Whisper): язык определяется сам, показывается в итоге
- 🖥 Транскрипция **на вашем Mac** (whisper.cpp) — аудио никуда не уходит
- 🔍 **Поиск по всем встречам** — по транскриптам и протоколам, понимает русские окончания («смета» найдёт «смету»), в окне приложения и из CLI
- 🧠 Резюме через «мозг» на выбор:
  - **ChatGPT по подписке** (главный, без ключей — вход вашим логином)
  - **OpenAI-совместимый** — OpenAI API, OpenRouter, vLLM, LM Studio
  - **Anthropic-совместимый** — Anthropic API, **GLM Coding Plan** (Z.ai)
  - **Ollama** — локально и бесплатно (`ollama pull qwen3:14b`)
- 📋 Шаблоны: «Протокол встречи» (участники / решения / обязательства кто-что-кому-срок / следующие шаги), краткое резюме, следующие шаги, свой вопрос (`--ask`)
- 💾 Всё хранится файлами: `~/Library/Application Support/Stenograf/meetings/<id>/`

## Установка

**[Скачать приложение для Mac](https://github.com/topex2025/stenograf/releases/latest).** Архив с суффиксом `-macos-universal.zip` подходит для Apple Silicon и Intel. Распакуйте его целиком и следуйте файлу «Установка.txt». Homebrew нужен для установки Whisper и Codex CLI. Для готового приложения Swift не нужен.

Сборка не нотарифицирована Apple. Если macOS покажет предупреждение при открытии, см. [инструкцию Apple](https://support.apple.com/en-us/102445).

### Сборка из исходников

Сборка из исходников требует macOS 13+, [Homebrew](https://brew.sh) и Swift 6.0 или новее. Скрипт скачивает модель Whisper (около 500 МБ), ставит Codex CLI, собирает приложение и предлагает войти в ChatGPT.

```bash
git clone https://github.com/topex2025/stenograf.git
cd stenograf
./scripts/setup.sh
open build/Stenograf.app
```

Для входа через ChatGPT API-ключ не нужен. Настройки модели находятся в `~/.stenograf/config.json`. Примеры ниже нужны только при выборе других поставщиков.

### Пример: GLM Coding Plan (Z.ai)

Anthropic-совместимый эндпоинт Coding Plan и название модели — см. [доку ZCode/Z.ai](https://zcode.z.ai) (раздел Connect with an API Key). Пример блока конфига:

```json
"glm": {
  "kind": "anthropic",
  "baseURL": "https://open.bigmodel.cn/api/anthropic",
  "apiKey": "ВАШ_КЛЮЧ_CODING_PLAN",
  "model": "glm-4.7"
}
```

> ⚠️ Coding Plan формально предназначен для coding-инструментов; использование в Стенографе — на вашей ответственности. Anthropic-совместимый протокол стандартный, так что этот же блок работает и с обычным ключом Anthropic API.

### Пример: OpenAI

```json
"openai": {
  "kind": "openai",
  "baseURL": "https://api.openai.com/v1",
  "apiKey": "sk-...",
  "model": "gpt-5.2"
}
```

### Пример: локальный Ollama (бесплатно, офлайн)

```bash
brew install ollama && ollama pull qwen3:14b
```
```json
"local": { "kind": "ollama", "baseURL": "http://localhost:11434", "model": "qwen3:14b" }
```

## Использование

```bash
# 1) записать встречу (стоп по Enter) — дальше всё само:
#    транскрипт (авто-язык) + протокол через подписку ChatGPT
.build/debug/stenograf record --title "Смета с подрядчиком"

# найти по всем встречам (транскрипты + протоколы, понимает окончания)
.build/debug/stenograf search "иванов обещал"

# вручную, если автопротокол выключен:
.build/debug/stenograf transcribe <ID>
.build/debug/stenograf summarize <ID> --template protocol

# вопрос по встрече
.build/debug/stenograf summarize <ID> --ask "Что обещал Иванов и к какому сроку?"
```

Меню-бар приложение (иконка 🎙 в трее — запись/транскрипция/протокол в один клик):

```bash
scripts/make-app.sh && open build/Stenograf.app
```

Если Whisper ошибся в имени, сумме или сроке, откройте карточку встречи, нажмите **Исправить текст**, сохраните правку и сформируйте **Отчёт** заново. Исходное распознавание остаётся в папке встречи, а старый отчёт скрывается из карточки и поиска.

## Приватность и принципы

1. Аудио обрабатывается Whisper на Mac. Записи и транскрипты хранятся локально.
2. При выборе облачной модели текст передаётся для подготовки отчёта. С локальной моделью Ollama отчёт можно сформировать на том же Mac.
3. Стенограф ничего не продаёт, не телеметрирует и не требует аккаунт.
4. Продаются (в будущем, Pro) только фичи — никогда доступ к моделям.

## Разработка

```bash
scripts/verify.sh   # build + тесты + CLI-смоук
```

Структура: `Sources/StenografCore` (мозги, whisper, запись, хранилище) · `Sources/stenograf` (CLI) · `Sources/StenografApp` (меню-бар) · `Tests` (unit + E2E). Архитектура — в `docs/ARCHITECTURE.md`.

## Дорожная карта

- M1: полноценное окно встречи, история, шаблоны из UI
- M2: вход через **подписку** — Codex OAuth («Sign in with ChatGPT») и повторное использование логина Claude Code (паттерн [OpenClaw](https://docs.openclaw.ai/concepts/oauth)); чат с транскриптом; системный звук (Zoom/Meet) через ScreenCaptureKit
- M3 (Pro): трекер обещаний → задачи, коннекторы CRM, профили голосов, поиск по всем встречам

## Сообщество / Community

Проект открыт к доработке: Issues, Pull Request, идеи — приветствуются.

- [CONTRIBUTING.md](CONTRIBUTING.md) — быстрый старт контрибьютора, правила проекта, структура кода
- [CHANGELOG.md](CHANGELOG.md) — история версий
- CI: каждый PR автоматически собирается и гоняет тесты на macOS-раннере GitHub Actions
- Главные желанные фичи: диаризация «кто говорит», системный звук Zoom/Meet, новые языки интерфейса, Windows/Linux-порт UI-слоя (ядро Core переносимо)

## Лицензия

MIT — см. [LICENSE](LICENSE).
