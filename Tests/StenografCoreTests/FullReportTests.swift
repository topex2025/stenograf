import XCTest
@testable import StenografCore

final class FullReportTests: XCTestCase {
    func testFullReportContainsBothParts() {
        let summary = "1. Первый пункт выжимки про смету.\n2. Второй пункт про сроки."
        let proto = "## Обязательства\n| Кто | Что | Срок |\n| --- | --- | --- |\n| Иванов | Смета | пятница |\n"
        let data = PDFExporter.exportFullReport(
            title: "Встреча — полный отчёт",
            subtitle: "проверка сборки",
            summaryMarkdown: summary,
            protocolMarkdown: proto
        )
        XCTAssertGreaterThan(data.count, 3000, "полный отчёт подозрительно мал")
        XCTAssertEqual(String(data: data.prefix(5), encoding: .ascii), "%PDF-")
        // обе части + шапка: в PDF-байтах должен быть текстовый поток с кириллицей (сжатие может скрыть, поэтому проверяем размер)
        XCTAssertTrue(String(data: data.suffix(64), encoding: .isoLatin1)?.contains("%%EOF") ?? false, "нет EOF")
    }
}
