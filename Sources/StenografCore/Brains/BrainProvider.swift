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
        Ты — секретарь совещаний. Сделай по транскрипту ЕДИНЫЙ ОТЧЁТ по встрече в Markdown.
        Структура строго такая, в этом порядке. Секцию пропускай целиком, если в транскрипте
        ничего для неё нет — не пиши «не указано» ради галочки:

        ## Суть одной фразой
        (1–2 предложения: самое главное про эту встречу)

        ## Выжимка
        (3–6 пунктов: всё, что нужно знать тому, кого на встрече не было)

        ## Решения
        (что окончательно договорили)

        ## Обязательства
        Таблица: | Кто | Что пообещал | Кому | Срок |
        Только реальные обещания. Срок не прозвучал — ставь «—».

        ## Даты
        (все прозвучавшие даты и сроки списком: что когда — включая те, что не привязаны к обязательству)

        ## Деньги
        (все суммы, прозвучавшие на встрече: кто, за что, сколько)

        ## Открытые вопросы
        (что обсудили, но так и не решили)

        ## Участники
        (имя — роль в проекте по контексту разговора)

        ## Следующие шаги
        (нумерованный список ближайших действий)

        Правила: используй ТОЛЬКО факты из транскрипта, ничего не выдумывай и не домысливай.
        Пиши на языке транскрипта, простым деловым языком, без канцелярита.
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
