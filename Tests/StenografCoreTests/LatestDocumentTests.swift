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

    func testCorrectionRetiresOldReportFromDetailsAndSearch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = MeetingStore(root: root)
        defer { try? FileManager.default.removeItem(at: root) }
        var meeting = try store.create()
        try store.writeTranscript(.init(text: "Ошибочный четверг", segments: []), to: &meeting)
        let oldReport = try store.writeSummary("Срок четверг", template: .meetingProtocol, brain: "old", to: meeting)
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: oldReport.path)
        XCTAssertNotNil(store.latestDocument(meeting: meeting, prefix: "protocol"))
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-5)], ofItemAtPath: oldReport.path)
        try store.correctTranscript("Срок пятница", for: meeting)
        XCTAssertNil(store.latestDocument(meeting: meeting, prefix: "protocol"))
        XCTAssertTrue(MeetingSearch.search(store: store, query: "четверг").isEmpty)
        XCTAssertEqual(try store.readTranscript(meeting), "Срок пятница")
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldReport.path))
        XCTAssertEqual(
            try String(contentsOf: store.dir(for: meeting).appendingPathComponent("transcript-original.md"), encoding: .utf8),
            "Ошибочный четверг"
        )
        let fresh = try store.writeSummary("Срок пятница", template: .meetingProtocol, brain: "new", to: meeting)
        XCTAssertEqual(store.latestDocument(meeting: meeting, prefix: "protocol")?.resolvingSymlinksInPath(), fresh.resolvingSymlinksInPath())
    }
}
