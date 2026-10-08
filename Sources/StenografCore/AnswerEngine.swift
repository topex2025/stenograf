import Foundation

/// Ответы на вопросы по встречам: находит релевантные встречи (наш поиск с морфологией)
/// и собирает их транскрипты в контекст для мозга.
public enum AnswerEngine {
    /// Контекст под вопрос: топ-N встреч по релевантности, транскрипты с ограничением длины.
    /// Возвращает текст контекста и список заголовков использованных встреч.
    @discardableResult
    public static func gatherContext(
        question: String,
        store: MeetingStore,
        maxMeetings: Int = 4,
        maxCharsPerMeeting: Int = 6000
    ) -> (context: String, usedTitles: [String]) {
        let hits = MeetingSearch.search(store: store, query: question, limit: maxMeetings, requireAllWords: false)
        guard !hits.isEmpty else { return ("", []) }

        var blocks: [String] = []
        var titles: [String] = []
        for hit in hits {
            guard let meeting = store.listAll().first(where: { $0.id == hit.meetingID }) else { continue }
            guard let transcript = try? store.readTranscript(meeting), !transcript.isEmpty else { continue }
            let trimmed = transcript.count > maxCharsPerMeeting
                ? String(transcript.prefix(maxCharsPerMeeting)) + " …[обрезано]"
                : transcript
            let date = meeting.createdAt.formatted(date: .abbreviated, time: .shortened)
            blocks.append("=== Встреча: \(meeting.title) (\(date)) ===\n\(trimmed)")
            titles.append("\(meeting.title) (\(date))")
        }
        return (blocks.joined(separator: "\n\n"), titles)
    }

    /// Системный промпт для ответа на вопрос по встречам.
    public static func systemPrompt(hasContext: Bool) -> String {
        if hasContext {
            return """
            Ты — ассистент по протоколам встреч. Пользователь задаёт вопрос о прошлых встречах.
            Ниже — транскрипты релевантных встреч. Отвечай на вопрос ТОЛЬКО на основе этих транскриптов.
            Отвечай кратко и по делу, на языке вопроса. Указывай, с какой встречи факт, если встреч несколько.
            Если в транскриптах нет ответа — честно скажи, что этого в записях нет. Ничего не выдумывай.
            """
        }
        return """
        Ты — ассистент по протоколам встреч. Подходящих записей не нашлось.
        Скажи об этом одним коротким предложением на языке вопроса и предложи записать встречу.
        """
    }

    public static func userMessage(question: String, context: String) -> String {
        context.isEmpty
            ? "Вопрос: \(question)"
            : "Транскрипты встреч:\n\n\(context)\n\nВопрос: \(question)"
    }
}
