import XCTest
@testable import StenografCore

/// latestDocument — «есть ли уже готовая выжимка/протокол»: кнопка не должна
/// перегенерировать существующее.
final class LatestDocumentTests: XCTestCase {
    func testFindsLatestByKind() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("stenograf-latest-\(UUID().uuidString)", isDirectory: true)
        let store = MeetingStore(root: root)
        defer { try? FileManager.default.removeItem(at: root) }

        let meeting = try store.create(title: "Проверка")
        // пока ничего нет
        XCTAssertNil(store.latestDocument(meeting: meeting, prefix: "summary"))
        XCTAssertNil(store.latestDocument(meeting: meeting, prefix: "protocol"))

        // протокол есть, выжимки нет
        _ = try store.writeSummary("# П", template: .meetingProtocol, brain: "test", to: meeting)
        XCTAssertNotNil(store.latestDocument(meeting: meeting, prefix: "protocol"))
        XCTAssertNil(store.latestDocument(meeting: meeting, prefix: "summary"))

        // появилась выжимка → находится; свежесть по метке, а не по алфавиту мозга
        _ = try store.writeSummary("Выжимка", template: .summary, brain: "zzz", to: meeting)
        let latest = try XCTUnwrap(store.latestDocument(meeting: meeting, prefix: "summary"))
        XCTAssertTrue(latest.lastPathComponent.hasPrefix("summary-zzz"), "ожидали свежую выжимку: \(latest.lastPathComponent)")
    }
}
