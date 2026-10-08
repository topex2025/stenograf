import Foundation
import StenografCore

// CLI без внешних зависимостей: stenograf <команда> [аргументы]
// Команды: record | transcribe | summarize | config | help

let args = Array(CommandLine.arguments.dropFirst())
let command = args.first ?? "help"

func printHelp() {
    print("""
    Стенограф — память переговоров на твоём Mac.

    Команды:
      record [--title Название] [--seconds N]   Записать встречу; после стопа — автопротокол
                                                 (транскрипция + протокол, отключается в конфиге)
      transcribe <id|путь.wav>                  Транскрибировать (локальный whisper.cpp, авто-язык)
      summarize <id|путь.md|-> [--brain ИМЯ] [--template protocol|summary|next-steps|custom] [--ask "вопрос"]
                                                 Отправить транскрипт в «мозг»
      search "слова из встречи"                 Поиск по транскриптам и протоколам всех встреч
      login                                     Войти в подписку ChatGPT (браузер, без ключей)
      config                                    Показать конфиг и статус входа
      help                                      Эта справка

    Конфиг: ~/.stenograf/config.json  (мозги: OpenAI-совместимый, Anthropic-совместимый, Ollama)
    """)
}

func loadOrCreateConfig() throws -> AppConfig {
    if !FileManager.default.fileExists(atPath: AppConfig.configURL.path) {
        let cfg = AppConfig.makeDefault()
        try cfg.save()
        FileHandle.standardError.write("Создан конфиг-заготовка: \(AppConfig.configURL.path)\nЗаполни ключ и модель — см. README.\n".data(using: .utf8)!)
    }
    return try AppConfig.load()
}

func resolveMeeting(_ arg: String, store: MeetingStore) throws -> (Meeting, MeetingStore) {
    // Это UUID существующей встречи?
    if let id = UUID(uuidString: arg), let m = store.listAll().first(where: { $0.id == id }) {
        return (m, store)
    }
    // Или путь к транскрипту/аудио?
    if FileManager.default.fileExists(atPath: arg) {
        var m = try store.create(title: (arg as NSString).lastPathComponent)
        if arg.hasSuffix(".wav") {
            let audioURL = store.audioURL(for: m)
            try? FileManager.default.removeItem(at: audioURL)
            try FileManager.default.copyItem(atPath: arg, toPath: audioURL.path)
            m.audioFile = "audio.wav"
            try store.saveMeta(&m)
        } else {
            let text = try String(contentsOfFile: arg, encoding: .utf8)
            try text.write(to: store.transcriptURL(for: m), atomically: true, encoding: .utf8)
            m.transcriptFile = "transcript.md"
            try store.saveMeta(&m)
        }
        return (m, store)
    }
    throw StenografError.missingFile(arg)
}

func asyncRun(_ body: @escaping @Sendable () async throws -> Void) -> Never {
    let sem = DispatchSemaphore(value: 0)
    Task {
        defer { sem.signal() }
        do { try await body() }
        catch { FileHandle.standardError.write("Ошибка: \(error.localizedDescription)\n".data(using: .utf8)!); exit(1) }
    }
    sem.wait()
    exit(0)
}

switch command {
case "help", "--help", "-h":
    printHelp()

case "search":
    let query = args.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespaces)
    guard !query.isEmpty else {
        print("Использование: stenograf search \"слова из встречи\"")
        exit(1)
    }
    let hits = MeetingSearch.search(store: MeetingStore.default, query: query)
    if hits.isEmpty {
        print("Ничего не нашлось по «\(query)».")
    } else {
        print("Нашёл \(hits.count) \(hits.count == 1 ? "встречу" : "встреч") по «\(query)»:\n")
        for (n, hit) in hits.enumerated() {
            print("\(n + 1). \(hit.title) — \(hit.date.formatted(date: .abbreviated, time: .shortened)) [\(hit.source), совпадений: \(hit.score)]")
            print("   \(hit.snippet)")
            print("   ID: \(hit.meetingID.uuidString)\n")
        }
    }

case "login":
    // Вход в подписку ChatGPT через официальный codex login: откроется браузер.
    // Кто уже вошёл — не заставляем перелогиниваться (кроме --force).
    let already = CodexSubscriptionBrain.loginStatus()
    if already.loggedIn && !args.contains("--force") {
        print("Вход уже активен: \(already.detail). Перезайти: stenograf login --force")
        exit(0)
    }
    let cli = CodexSubscriptionBrain.resolveCliPath()
    guard FileManager.default.fileExists(atPath: cli) else {
        FileHandle.standardError.write("Codex CLI не найден. Сначала: scripts/setup.sh или npm install -g --prefix ~/.stenograf/cli @openai/codex\n".data(using: .utf8)!)
        exit(1)
    }
    print("Открываю браузер для входа в ChatGPT (подписка Plus/Pro)…")
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: cli)
    proc.arguments = ["login"]
    proc.standardInput = nil
    proc.standardOutput = FileHandle.standardOutput
    proc.standardError = FileHandle.standardError
    try? proc.run()
    proc.waitUntilExit()
    let status = CodexSubscriptionBrain.loginStatus()
    print("Статус: \(status.detail)")
    if status.loggedIn { print("Готово — мозг «chatgpt» активен.") }
    else { exit(1) }

case "config":
    do {
        _ = try loadOrCreateConfig()
        let cfg = try AppConfig.load()
        print("Конфиг: \(AppConfig.configURL.path)")
        print("Whisper: cli=\(cfg.whisper.cliPath) model=\(cfg.whisper.modelPath) lang=\(cfg.whisper.language)")
        let (loggedIn, detail) = CodexSubscriptionBrain.loginStatus()
        print("ChatGPT-подписка: \(loggedIn ? "активна" : "НЕ активна") — \(detail)")
        if cfg.brains.isEmpty {
            print("Мозги: не настроены")
        } else {
            print("Мозги: \(cfg.brains.keys.sorted().joined(separator: ", "))  (по умолчанию: \(cfg.defaultBrain ?? "нет"))")
            for (name, b) in cfg.brains.sorted(by: { $0.key < $1.key }) {
                let keyState: String
                switch b.kind {
                case .codex: keyState = loggedIn ? "вход активен" : "нужен stenograf login"
                default: keyState = (b.apiKey == nil || b.apiKey!.hasPrefix("ВСТАВЬ")) ? "ключ НЕ заполнен" : "ключ ок"
                }
                print("  - \(name): \(b.kind.rawValue) \(b.baseURL.isEmpty ? "" : "@ \(b.baseURL)") model=\(b.model.isEmpty ? "(стандартный)" : b.model) [\(keyState)]")
            }
        }
        print("Встречи: \(MeetingStore.default.root.path)")
    } catch {
        FileHandle.standardError.write("Ошибка: \(error.localizedDescription)\n".data(using: .utf8)!)
        exit(1)
    }

case "record":
    var title = "Встреча"
    var seconds: Int?
    var i = 1
    while i < args.count {
        switch args[i] {
        case "--title": title = args[i + 1]; i += 2
        case "--seconds": seconds = Int(args[i + 1]); i += 2
        default: i += 1
        }
    }
    do {
        let cfg = try loadOrCreateConfig()
        let store = MeetingStore.default
        var meeting = try store.create(title: title)
        let recorder = AudioRecorder()
        let path = store.audioURL(for: meeting).path
        try recorder.start(to: path)
        meeting.audioFile = "audio.wav"
        try store.saveMeta(&meeting)
        print("Пишу: \(title) → \(path)")
        if let seconds {
            Thread.sleep(forTimeInterval: TimeInterval(seconds))
        } else {
            print("Нажми Enter чтобы остановить…")
            _ = readLine()
        }
        let duration = recorder.stop()
        meeting.durationSeconds = duration
        try store.saveMeta(&meeting)
        print("Записано \(Int(duration ?? 0)) сек. ID: \(meeting.id.uuidString)")
        if cfg.autoProtocol {
            let meetingFinal = meeting
            let brainName0 = cfg.defaultBrain
            asyncRun {
                let (brainName, brainCfg) = try cfg.brain(named: brainName0)
                print("Автопротокол: транскрибирую локально (язык: авто)…")
                let result = try await Pipeline.autoProcess(
                    meeting: meetingFinal,
                    store: store,
                    whisper: WhisperCLI(whisper: cfg.whisper),
                    brain: BrainFactory.make(brainCfg),
                    brainName: brainName
                )
                let lang = result.detectedLanguage.map { " [язык: \($0)]" } ?? ""
                print("Транскрипт готов\(lang), \(result.transcript.count) знаков")
                print("\n--- ПРОТОКОЛ ---\n\(result.summary)\n----------------")
                print("Сохранено: \(result.summaryURL.path)")
            }
        } else {
            print("Дальше: stenograf transcribe \(meeting.id.uuidString)")
        }
    } catch {
        FileHandle.standardError.write("Ошибка записи: \(error.localizedDescription)\n".data(using: .utf8)!)
        exit(1)
    }

case "transcribe":
    guard args.count > 1 else {
        print("Использование: stenograf transcribe <id|путь.wav>")
        exit(1)
    }
    do {
        let cfg = try loadOrCreateConfig()
        let store = MeetingStore.default
        var meeting: Meeting
        var wavPath: String
        if let id = UUID(uuidString: args[1]), let m = store.listAll().first(where: { $0.id == id }) {
            meeting = m
            wavPath = store.audioURL(for: meeting).path
        } else if FileManager.default.fileExists(atPath: args[1]) {
            meeting = try store.create(title: (args[1] as NSString).lastPathComponent)
            wavPath = args[1]
            meeting.audioFile = "audio.wav"
            try store.saveMeta(&meeting)
        } else {
            throw StenografError.missingFile(args[1])
        }
        print("Транскрибирую (локально, \(cfg.whisper.language))…")
        let whisper = WhisperCLI(whisper: cfg.whisper)
        let result = try whisper.transcribe(audioFile: wavPath)
        try store.writeTranscript(result, to: &meeting)
        print("Транскрипт (\(result.text.count) знаков, \(result.segments.count) сегментов): \(store.transcriptURL(for: meeting).path)")
        print("\n---\n\(result.text.prefix(500))\n---")
        print("Дальше: stenograf summarize \(meeting.id.uuidString)")
    } catch {
        FileHandle.standardError.write("Ошибка: \(error.localizedDescription)\n".data(using: .utf8)!)
        exit(1)
    }

case "summarize":
    var meetingArg: String?
    var brainName: String?
    var template = PromptTemplate.meetingProtocol
    var question: String?
    var i = 1
    while i < args.count {
        switch args[i] {
        case "--brain": brainName = args[i + 1]; i += 2
        case "--template": template = PromptTemplate(rawValue: args[i + 1]) ?? .meetingProtocol; i += 2
        case "--ask": question = args[i + 1]; i += 2
        default: meetingArg = args[i]; i += 1
        }
    }
    guard let meetingArg else {
        print("Использование: stenograf summarize <id|путь.md> [--brain ИМЯ] [--template ...] [--ask \"вопрос\"]")
        exit(1)
    }
    let brainArg = brainName
    let templateArg = template
    let questionArg = question
    let meetingArgFinal = meetingArg
    asyncRun {
        let cfg = try loadOrCreateConfig()
        let store = MeetingStore.default
        let (meeting, _) = try resolveMeeting(meetingArgFinal, store: store)
        let transcript = try store.readTranscript(meeting)
        let (brainName, brainCfg) = try cfg.brain(named: brainArg)
        let brain = BrainFactory.make(brainCfg)

        let user: String
        if let questionArg {
            user = "Транскрипт встречи:\n\n\(transcript)\n\nВопрос: \(questionArg)"
        } else {
            user = "Транскрипт встречи:\n\n\(transcript)"
        }
        print("Спрашиваю «\(brainName)» (\(templateArg.title))…")
        let answer = try await brain.complete(system: templateArg.systemPrompt(), user: user)
        let url = try store.writeSummary(answer, template: templateArg, brain: brainName, to: meeting)
        print("\n\(answer)\n")
        print("Сохранено: \(url.path)")
    }

default:
    print("Неизвестная команда: \(command)\n")
    printHelp()
    exit(1)
}
