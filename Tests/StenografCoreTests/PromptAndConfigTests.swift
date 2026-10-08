import XCTest
@testable import StenografCore

final class PromptAndConfigTests: XCTestCase {
    func testProtocolPromptHasPromiseSectionsAndNoHallucinationRule() {
        let prompt = PromptTemplate.meetingProtocol.systemPrompt()
        XCTAssertTrue(prompt.contains("Обязательства"), "должен быть раздел обязательств")
        XCTAssertTrue(prompt.contains("Кто"), "таблица: Кто")
        XCTAssertTrue(prompt.contains("Срок"), "таблица: Срок")
        XCTAssertTrue(prompt.contains("не выдумывай") || prompt.contains("Ничего не выдумывай"), "запрет галлюцинаций")
        XCTAssertTrue(prompt.contains("Участники"))
        XCTAssertTrue(prompt.contains("Следующие шаги"))
        XCTAssertTrue(prompt.contains("Суть разговора"), "первой секцией — выжимка сути")
        XCTAssertTrue(prompt.range(of: "Суть разговора").map { $0.lowerBound < prompt.range(of: "Участники")!.lowerBound } ?? false,
                      "выжимка должна идти раньше участников")
        // отдельный шаблон выжимки
        XCTAssertTrue(PromptTemplate.summary.systemPrompt().contains("выжимка") || PromptTemplate.summary.systemPrompt().contains("суть"))
    }

    func testAllTemplatesHaveBuiltInPrompt() {
        for template in PromptTemplate.allCases {
            XCTAssertFalse(template.systemPrompt().isEmpty, "пустой промпт: \(template.rawValue)")
        }
    }

    func testConfigRoundTripAndSecretPermissions() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("stenograf-tests-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("config.json")
        var cfg = AppConfig.makeDefault()
        cfg.defaultBrain = "glm"
        cfg.brains["test"] = BrainConfig(kind: .openai, baseURL: "https://example.com/v1", apiKey: "secret-123", model: "m1")
        try cfg.save(fileURL: url)

        let loaded = try AppConfig.load(fileURL: url)
        XCTAssertEqual(loaded.defaultBrain, "glm")
        XCTAssertEqual(loaded.brains["test"]?.apiKey, "secret-123")

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.uint16Value ?? 0, 0o600, "конфиг с ключами должен быть 600")

        // brain(named:) — дефолт и явное имя
        let (name1, _) = try loaded.brain(named: nil)
        XCTAssertEqual(name1, "glm")
        let (name2, _) = try loaded.brain(named: "test")
        XCTAssertEqual(name2, "test")

        // нет мозгов — понятная ошибка
        XCTAssertThrowsError(try AppConfig().brain(named: nil))
    }

    func testMeetingStoreRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("stenograf-store-\(UUID().uuidString)")
        let store = MeetingStore(root: root)
        var meeting = try store.create(title: "Тест")

        let result = WhisperCLI.Result(text: "привет мир", segments: [
            .init(start: 0, end: 1.5, text: "привет"),
            .init(start: 1.5, end: 3.0, text: "мир"),
        ])
        try store.writeTranscript(result, to: &meeting)
        let readBack = try store.readTranscript(meeting)
        XCTAssertTrue(readBack.contains("[00:00] привет"), "транскрипт должен содержать таймкоды: \(readBack)")

        let url = try store.writeSummary("# Протокол", template: .meetingProtocol, brain: "glm", to: meeting)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let all = store.listAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.title, "Тест")
        try? FileManager.default.removeItem(at: root)
    }
}
