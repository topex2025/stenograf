import XCTest
@testable import StenografCore

final class AnswerEngineTests: XCTestCase {
    func testGatherContextFindsRelevantMeeting() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("stenograf-ans-\(UUID().uuidString)", isDirectory: true)
        let store = MeetingStore(root: root)
        defer { try? FileManager.default.removeItem(at: root) }

        var a = try store.create(title: "Смета с подрядчиком")
        try store.writeTranscript(
            WhisperCLI.Result(text: "Иванов обещает подготовить смету к пятнице", segments: [], detectedLanguage: "ru"),
            to: &a
        )
        var b = try store.create(title: "Отпуск")
        try store.writeTranscript(
            WhisperCLI.Result(text: "Бронируем билеты на море в июле", segments: [], detectedLanguage: nil),
            to: &b
        )

        // вопрос про смету → контекст содержит первую встречу, не вторую
        let result = AnswerEngine.gatherContext(question: "что с сметой", store: store)
        XCTAssertTrue(result.context.contains("смету"), "контекст должен содержать транскрипт про смету")
        XCTAssertTrue(result.context.contains("Смета с подрядчиком"))
        XCTAssertFalse(result.context.contains("море"), "нерелевантная встреча не должна попасть")
        XCTAssertEqual(result.usedTitles.count, 1)

        // ничего релевантного → пустой контекст
        let none = AnswerEngine.gatherContext(question: "записаться на йогу", store: store)
        XCTAssertTrue(none.context.isEmpty)
        XCTAssertTrue(AnswerEngine.systemPrompt(hasContext: false).contains("не нашлось"))
        XCTAssertTrue(AnswerEngine.systemPrompt(hasContext: true).contains("не выдумывай"))
        XCTAssertFalse(AnswerEngine.userMessage(question: "q", context: "").isEmpty)
    }
}
