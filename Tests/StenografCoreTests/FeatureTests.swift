import XCTest
@testable import StenografCore

private struct StubBrain: BrainProvider {
    let answer: String
    func complete(system: String, user: String) async throws -> String { answer }
}

final class FeatureTests: XCTestCase {
    private func makeStore() throws -> (MeetingStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("stenograf-feat-\(UUID().uuidString)", isDirectory: true)
        return (MeetingStore(root: root), root)
    }

    // MARK: - Поиск по встречам

    func testSearchFindsTranscriptAndSummary() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        var a = try store.create(title: "Смета с подрядчиком")
        try store.writeTranscript(
            WhisperCLI.Result(text: "Иванов обещает подготовить смету к пятнице", segments: [], detectedLanguage: "ru"),
            to: &a
        )
        let b = try store.create(title: "Созвон по поставщикам")
        _ = try store.writeSummary("Петров берёт на себя звонок поставщику", template: .meetingProtocol, brain: "chatgpt", to: b)

        // одно слово, транскрипт, регистронезависимо
        XCTAssertEqual(MeetingSearch.search(store: store, query: "СМЕТА").count, 1)
        XCTAssertEqual(MeetingSearch.search(store: store, query: "смета").first?.meetingID, a.id)
        XCTAssertEqual(MeetingSearch.search(store: store, query: "смета").first?.source, "транскрипт")
        XCTAssertTrue(MeetingSearch.search(store: store, query: "смета").first?.snippet.contains("смету") ?? false)

        // слово из резюме другой встречи
        let supplier = MeetingSearch.search(store: store, query: "поставщик")
        XCTAssertEqual(supplier.count, 1)
        XCTAssertEqual(supplier.first?.meetingID, b.id)

        // несколько слов = И, в одной строке транскрипта
        XCTAssertEqual(MeetingSearch.search(store: store, query: "иванов смета").count, 1)

        // И-семантика: слова из разных встреч → пусто
        XCTAssertTrue(MeetingSearch.search(store: store, query: "иванов поставщик").isEmpty)

        // ё = е
        var c = try store.create(title: "Ёжик")
        try store.writeTranscript(
            WhisperCLI.Result(text: "Ёлка и ежик встретились", segments: [], detectedLanguage: nil),
            to: &c
        )
        XCTAssertEqual(MeetingSearch.search(store: store, query: "ежик").count, 1)

        // мусорный запрос и пустой
        XCTAssertTrue(MeetingSearch.search(store: store, query: "глобальнаячушь").isEmpty)
        XCTAssertTrue(MeetingSearch.search(store: store, query: "   ").isEmpty)
    }

    // MARK: - Пайплайн автопротокола (вторая половина — резюме)

    func testPipelineSummarizeWritesProtocolFile() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        var meeting = try store.create(title: "Тест пайплайна")
        try store.writeTranscript(
            WhisperCLI.Result(text: "Обсудили поставку. Иванов обещал привезти образцы.", segments: [], detectedLanguage: nil),
            to: &meeting
        )

        let result = try await Pipeline.summarize(
            transcript: "Обсудили поставку.",
            meeting: meeting,
            store: store,
            brain: StubBrain(answer: "## Обязательства\nИванов — образцы"),
            brainName: "chatgpt"
        )
        XCTAssertEqual(result.text, "## Обязательства\nИванов — образцы")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))
        XCTAssertEqual(try String(contentsOf: result.url, encoding: .utf8), result.text)
    }

    // MARK: - Конфиг: автодетект языка и автопротокол по умолчанию

    func testConfigDefaultsAutoLanguageAndAutoProtocol() throws {
        // новый дефолт — авто-язык
        XCTAssertEqual(WhisperConfig().language, "auto")

        // старый конфиг без autoProtocol → true (обратная совместимость)
        let old = #"{"whisper":{"cliPath":"/x","modelPath":"/y","language":"ru"},"brains":{}}"#
        let decoded = try JSONDecoder().decode(AppConfig.self, from: Data(old.utf8))
        XCTAssertTrue(decoded.autoProtocol)
        XCTAssertEqual(decoded.whisper.language, "ru") // явное значение сохраняется

        // явный false читается
        let off = #"{"autoProtocol":false}"#
        XCTAssertFalse(try JSONDecoder().decode(AppConfig.self, from: Data(off.utf8)).autoProtocol)

        // makeDefault включает и то и другое
        let def = AppConfig.makeDefault()
        XCTAssertTrue(def.autoProtocol)
        XCTAssertEqual(def.whisper.language, "auto")
    }
}
