import XCTest
@testable import StenografCore

final class PDFExportTests: XCTestCase {
    private func tmpWrite(_ data: Data, _ name: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try! data.write(to: url)
        return url
    }

    func testDocumentPDFWithCyrillicAndTable() {
        let md = """
        ## Суть разговора
        Обсудили смету и сроки поставки.

        ## Обязательства
        | Кто | Что пообещал | Кому | Срок |
        | --- | --- | --- | --- |
        | Иванов | Подготовить смету | Заказчику | к пятнице |

        ## Следующие шаги
        1. Позвонить поставщику
        - проверить документы
        """
        let data = PDFExporter.exportDocument(
            title: "Встреча 4 — проверка PDF",
            subtitle: "22 нояб. 2026 г., 10:00 · 1200 сек",
            markdown: md
        )
        let url = tmpWrite(data, "stenograf-doc-test.pdf")
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertGreaterThan(data.count, 2000, "PDF подозрительно мал: \(data.count)")
        let head = String(data: data.prefix(5), encoding: .ascii)
        XCTAssertEqual(head, "%PDF-", "нет PDF-магии: \(head ?? "?")")
        // страницы: больше одной страницы быть может, минимум одна ends
        XCTAssertTrue(String(data: data.suffix(64), encoding: .isoLatin1)?.contains("%%EOF") ?? false, "нет EOF-маркера")
    }

    func testTranscriptPDFWithTimecodes() {
        let transcript = """
        [00:00] Первый тезис встречи
        [00:19] Иванов обещает подготовить смету к пятнице
        [01:04] Петров берёт на себя звонок поставщику
        """
        let data = PDFExporter.exportTranscript(
            title: "Транскрипт — Встреча 4",
            subtitle: "проверка таймкодов",
            transcript: transcript
        )
        XCTAssertGreaterThan(data.count, 1500)
        XCTAssertEqual(String(data: data.prefix(5), encoding: .ascii), "%PDF-")
    }

    func testLongDocumentPaginates() {
        // длинный текст → PDF должен разрастись (много страниц), не зависнуть
        let para = String(repeating: "Обсуждение поставки деталей и комплектующих продолжается. ", count: 200)
        let data = PDFExporter.exportDocument(title: "Длинная встреча", subtitle: "тест пагинации", markdown: para)
        let url = tmpWrite(data, "stenograf-long-test.pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertGreaterThan(data.count, 20_000, "пагинация не отработала: \(data.count)")
    }
}
