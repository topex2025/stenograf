import Foundation

/// Единственный контракт «мозга»: система + пользовательский запрос → текст.
/// Реализации: OpenAICompatibleBrain, AnthropicBrain, OllamaBrain.
public protocol BrainProvider: Sendable {
    func complete(system: String, user: String) async throws -> String
}

/// Собирает провайдер из конфига. Инъекция URLSession — для тестов.
public enum BrainFactory {
    public static func make(_ config: BrainConfig, urlSession: URLSession = .shared) -> any BrainProvider {
        switch config.kind {
        case .codex:
            CodexSubscriptionBrain(
                cliPath: CodexSubscriptionBrain.resolveCliPath(configured: config.cliPath),
                model: config.model.isEmpty ? nil : config.model
            )
        case .openai: OpenAICompatibleBrain(config: config, urlSession: urlSession)
        case .anthropic: AnthropicBrain(config: config, urlSession: urlSession)
        case .ollama: OllamaBrain(config: config, urlSession: urlSession)
        }
    }
}

// MARK: - Промпт-шаблоны

public enum PromptTemplate: String, CaseIterable, Sendable {
    case meetingProtocol = "protocol"
    case summary = "summary"
    case nextSteps = "next-steps"
    case custom = "custom"

    public var title: String {
        switch self {
        case .meetingProtocol: "Протокол встречи"
        case .summary: "Краткое резюме"
        case .nextSteps: "Следующие шаги"
        case .custom: "Свой запрос"
        }
    }

    public func systemPrompt() -> String {
        // Пользователь может переопределить шаблон файлом ~/.stenograf/prompts/<id>.md
        if let override = Self.loadOverride(rawValue) { return override }
        return Self.builtIn[self] ?? Self.builtIn[.summary]!
    }

    private static func loadOverride(_ id: String) -> String? {
        let url = AppConfig.promptsDir.appendingPathComponent("\(id).md")
        guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else { return nil }
        return text
    }

    static let builtIn: [PromptTemplate: String] = [
        .meetingProtocol: """
        Ты — профессиональный секретарь совещаний. Тебе даётся транскрипт встречи на любом языке.
        Верни ответ в Markdown строго со следующими разделами, в этом порядке:

        ## Суть разговора
        (выжимка: 3–6 пунктов самой сути диалога простым языком — что происходило, к чему пришли, что осталось открытым)

        ## Участники
        (кого удалось определить по контексту; иначе «не определены»)

        ## О чём договорились
        (решения, зафиксированные в разговоре)

        ## Обязательства
        Таблица: | Кто | Что пообещал | Кому | Срок |
        Если срок не прозвучал — пиши «срок не указан». Если обязательств нет — напиши «обязательств нет».

        ## Следующие шаги
        (нумерованный список)

        Правила: используй ТОЛЬКО факты из транскрипта. Ничего не выдумывай и не домысливай.
        Если что-то неясно — пиши «не указано». Пиши на языке транскрипта.
        """,
        .summary: """
        Ты — ассистент по встречам. Сделай выжимку транскрипта на языке транскрипта.
        Формат: 3–7 пунктов — самая суть диалога простым языком: что происходило,
        о чём договорились, что осталось открытым. Без канцелярита, по делу.
        Только факты из транскрипта, без домыслов. Markdown, нумерованный список.
        """,
        .nextSteps: """
        Ты — ассистент по встречам. Из транскрипта выдай ТОЛЬКО список действий:
        1) что нужно сделать, 2) кто ответственным указан в разговоре (если указан), 3) срок (если прозвучал).
        Ничего не выдумывай. Markdown, нумерованный список.
        """,
        .custom: """
        Ты — ассистент по встречам. Отвечай на языке транскрипта, кратко, только на основе текста.
        """,
    ]
}
