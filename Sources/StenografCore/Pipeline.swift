import Foundation

/// Автопротокол: после остановки записи сам гоняет цепочку
/// транскрипция (локально) → протокол (мозг). Используется и CLI, и приложением.
public enum Pipeline {
    public struct AutoResult: Sendable {
        public let transcript: String
        public let summary: String
        public let detectedLanguage: String?
        public let summaryURL: URL
    }

    /// Полная цепочка: аудио встречи → транскрипт → протокол.
    public static func autoProcess(
        meeting: Meeting,
        store: MeetingStore,
        whisper: WhisperCLI,
        brain: any BrainProvider,
        brainName: String,
        template: PromptTemplate = .meetingProtocol
    ) async throws -> AutoResult {
        let audioPath = store.audioURL(for: meeting).path

        // whisper синхронный — уводим с кооперативного пула
        let whisperResult = try await Task.detached(priority: .userInitiated) {
            try whisper.transcribe(audioFile: audioPath)
        }.value

        var updated = meeting
        try store.writeTranscript(whisperResult, to: &updated)

        let summary = try await summarize(
            transcript: whisperResult.text,
            meeting: updated,
            store: store,
            brain: brain,
            brainName: brainName,
            template: template
        )
        return AutoResult(
            transcript: whisperResult.text,
            summary: summary.text,
            detectedLanguage: whisperResult.detectedLanguage,
            summaryURL: summary.url
        )
    }

    /// Вторая половина цепочки отдельно (когда транскрипт уже есть).
    @discardableResult
    public static func summarize(
        transcript: String,
        meeting: Meeting,
        store: MeetingStore,
        brain: any BrainProvider,
        brainName: String,
        template: PromptTemplate = .meetingProtocol
    ) async throws -> (text: String, url: URL) {
        let answer = try await brain.complete(
            system: template.systemPrompt(),
            user: "Транскрипт встречи:\n\n\(transcript)"
        )
        let url = try store.writeSummary(answer, template: template, brain: brainName, to: meeting)
        return (answer, url)
    }
}
