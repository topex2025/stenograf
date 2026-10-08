import Foundation

/// Одна встреча: аудио + транскрипт + резюме. Хранится как папка в MeetingStore.
public struct Meeting: Codable, Sendable, Identifiable {
    public var id: UUID
    public var createdAt: Date
    public var title: String
    public var audioFile: String?      // имя файла внутри папки встречи
    public var transcriptFile: String? // transcript.md
    public var durationSeconds: Double?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        title: String = "Встреча",
        audioFile: String? = nil,
        transcriptFile: String? = nil,
        durationSeconds: Double? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.audioFile = audioFile
        self.transcriptFile = transcriptFile
        self.durationSeconds = durationSeconds
    }
}

public enum BrainKind: String, Codable, Sendable {
    case codex        // ПОДПИСКА ChatGPT через официальный Codex CLI — без ключей
    case openai       // OpenAI-совместимый: OpenAI API, OpenRouter, vLLM, LM Studio
    case anthropic    // Anthropic-совместимый: Anthropic API, GLM Coding Plan
    case ollama       // локальный Ollama
}

public struct BrainConfig: Codable, Sendable {
    public var kind: BrainKind
    public var baseURL: String
    public var apiKey: String?
    public var model: String
    public var maxTokens: Int?
    public var cliPath: String?   // для kind == .codex: путь к codex (обычно находится сам)

    public init(kind: BrainKind, baseURL: String = "", apiKey: String? = nil, model: String = "", maxTokens: Int? = 4096, cliPath: String? = nil) {
        self.kind = kind
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
        self.cliPath = cliPath
    }
}

public struct WhisperConfig: Codable, Sendable {
    public var cliPath: String
    public var modelPath: String
    public var language: String   // "auto" (по умолчанию) или конкретный: "ru", "en", ...

    public init(
        cliPath: String = "/opt/homebrew/bin/whisper-cli",
        modelPath: String = NSString(string: "~/.cache/whisper/ggml-medium-q5_0.bin").expandingTildeInPath,
        language: String = "auto"
    ) {
        self.cliPath = cliPath
        self.modelPath = modelPath
        self.language = language
    }
}

public struct AppConfig: Codable, Sendable {
    public var whisper: WhisperConfig
    public var brains: [String: BrainConfig]
    public var defaultBrain: String?
    /// После остановки записи: сам транскрибирует и делает протокол мозгом по умолчанию.
    public var autoProtocol: Bool
    /// Голос озвучки для системного движка say (например «Yuri»); nil — авто по языку.
    /// Нейроголос Piper (если установлен) имеет приоритет над say.
    public var ttsVoice: String?

    public init(
        whisper: WhisperConfig = WhisperConfig(),
        brains: [String: BrainConfig] = [:],
        defaultBrain: String? = nil,
        autoProtocol: Bool = true,
        ttsVoice: String? = nil
    ) {
        self.whisper = whisper
        self.brains = brains
        self.defaultBrain = defaultBrain
        self.autoProtocol = autoProtocol
        self.ttsVoice = ttsVoice
    }

    private enum CodingKeys: String, CodingKey {
        case whisper, brains, defaultBrain, autoProtocol, ttsVoice
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        whisper = try c.decodeIfPresent(WhisperConfig.self, forKey: .whisper) ?? WhisperConfig()
        brains = try c.decodeIfPresent([String: BrainConfig].self, forKey: .brains) ?? [:]
        defaultBrain = try c.decodeIfPresent(String.self, forKey: .defaultBrain)
        autoProtocol = try c.decodeIfPresent(Bool.self, forKey: .autoProtocol) ?? true
        ttsVoice = try c.decodeIfPresent(String.self, forKey: .ttsVoice)
    }

    public static let configURL = URL(fileURLWithPath: NSString(string: "~/.stenograf/config.json").expandingTildeInPath)
    public static let promptsDir = URL(fileURLWithPath: NSString(string: "~/.stenograf/prompts").expandingTildeInPath)

    public static func load(fileURL: URL = configURL) throws -> AppConfig {
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(AppConfig.self, from: data)
    }

    public func save(fileURL: URL = AppConfig.configURL) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: fileURL, options: [.atomic])
        // Конфиг содержит ключи — выставляем права только владельцу.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    /// Дефолтный конфиг: главный мозг — подписка ChatGPT (без ключей),
    /// остальные — опция для продвинутых.
    public static func makeDefault() -> AppConfig {
        AppConfig(
            whisper: WhisperConfig(),
            brains: [
                "chatgpt": BrainConfig(kind: .codex),
                "glm": BrainConfig(
                    kind: .anthropic,
                    baseURL: "https://open.bigmodel.cn/api/anthropic",
                    apiKey: "ВСТАВЬ_КЛЮЧ_CODING_PLAN",
                    model: "glm-4.7"
                ),
                "openai": BrainConfig(
                    kind: .openai,
                    baseURL: "https://api.openai.com/v1",
                    apiKey: "ВСТАВЬ_КЛЮЧ_API",
                    model: "gpt-5.2"
                ),
                "local": BrainConfig(
                    kind: .ollama,
                    baseURL: "http://localhost:11434",
                    model: "qwen3:14b"
                ),
            ],
            defaultBrain: "chatgpt"
        )
    }

    public func brain(named name: String?) throws -> (name: String, config: BrainConfig) {
        let key = name ?? defaultBrain ?? brains.keys.sorted().first
        guard let key, let cfg = brains[key] else {
            throw StenografError.noBrainConfigured
        }
        return (key, cfg)
    }
}

public enum StenografError: LocalizedError {
    case noBrainConfigured
    case badBrainResponse(String)
    case whisperFailed(Int32, String)
    case missingFile(String)

    public var errorDescription: String? {
        switch self {
        case .noBrainConfigured:
            "Не настроен ни один «мозг». Заполни ~/.stenograf/config.json (см. README)."
        case .badBrainResponse(let detail):
            "«Мозг» вернул неожиданный ответ: \(detail)"
        case .whisperFailed(let code, let stderr):
            "whisper-cli упал (код \(code)): \(stderr)"
        case .missingFile(let path):
            "Файл не найден: \(path)"
        }
    }
}
