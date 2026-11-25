import Foundation
import AppKit
import CoreText
import QuartzCore

/// Экспорт в PDF без сторонних зависимостей: CoreText-пагинация A4.
/// Три вида документов: выжимка/протокол (из MarkdownBlock) и транскрипт.
public enum PDFExporter {
    // Фирменные цвета как в приложении
    static let red = NSColor(calibratedRed: 1.00, green: 0.23, blue: 0.31, alpha: 1)
    static let ink = NSColor(calibratedWhite: 0.07, alpha: 1)
    static let gray = NSColor(calibratedWhite: 0.45, alpha: 1)

    static let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4
    static let inset: CGFloat = 48

    // MARK: - Публичные точки входа

    /// PDF выжимки/протокола: шапка + блоки (секции, списки, таблица обязательств).
    public static func exportDocument(title: String, subtitle: String, markdown: String) -> Data {
        let text = NSMutableAttributedString()
        appendHeader(title: title, subtitle: subtitle, to: text)
        appendBlocks(MarkdownBlock.parse(markdown), to: text)
        return render(text)
    }

    /// Полный отчёт одним файлом: выжимка + протокол.
    public static func exportFullReport(title: String, subtitle: String,
                                        summaryMarkdown: String, protocolMarkdown: String) -> Data {
        let text = NSMutableAttributedString()
        appendHeader(title: title, subtitle: subtitle, to: text)
        text.append(attributed("ВЫЖИМКА\n", font: headerFont, color: ink))
        appendBlocks(MarkdownBlock.parse(summaryMarkdown), to: text)
        appendBreak(to: text)
        appendBreak(to: text)
        text.append(attributed("ПРОТОКОЛ ВСТРЕЧИ\n", font: headerFont, color: ink))
        appendBlocks(MarkdownBlock.parse(protocolMarkdown), to: text)
        return render(text)
    }

    /// PDF транскрипта: строки «[мм:сс] реплика».
    public static func exportTranscript(title: String, subtitle: String, transcript: String) -> Data {
        let text = NSMutableAttributedString()
        appendHeader(title: title, subtitle: subtitle, to: text)
        for rawLine in transcript.components(separatedBy: .newlines) {
            guard !rawLine.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            if let close = rawLine.firstIndex(of: "]"), rawLine.hasPrefix("[") {
                let tc = String(rawLine[rawLine.index(after: rawLine.startIndex)..<close])
                let body = String(rawLine[rawLine.index(after: close)...]).trimmingCharacters(in: .whitespaces)
                text.append(attributed(tc + "  ", font: monoTime, color: gray))
                text.append(attributed(body.isEmpty ? "…" : body, font: bodyFont, color: ink))
            } else {
                text.append(attributed(rawLine, font: bodyFont, color: ink))
            }
            appendBreak(to: text)
        }
        return render(text)
    }

    // MARK: - Шрифты

    static var titleFont: NSFont { NSFont.systemFont(ofSize: 21, weight: .bold) }
    static var subtitleFont: NSFont { NSFont.systemFont(ofSize: 11, weight: .regular) }
    static var headerFont: NSFont { NSFont.systemFont(ofSize: 15, weight: .semibold) }
    static var bodyFont: NSFont { NSFont.systemFont(ofSize: 12, weight: .regular) }
    static var tableFont: NSFont { NSFont.systemFont(ofSize: 11, weight: .regular) }
    static var tableHeadFont: NSFont { NSFont.systemFont(ofSize: 11, weight: .bold) }
    static var monoTime: NSFont { NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold) }

    // MARK: - Сборка атрибутов

    static func attributed(_ s: String, font: NSFont, color: NSColor,
                           paragraph: NSParagraphStyle? = nil) -> NSAttributedString {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color,
        ]
        if let paragraph { attrs[.paragraphStyle] = paragraph }
        return NSAttributedString(string: s, attributes: attrs)
    }

    static func appendBreak(to text: NSMutableAttributedString) {
        text.append(attributed("\n", font: NSFont.systemFont(ofSize: 7), color: ink))
    }

    static func appendHeader(title: String, subtitle: String, to text: NSMutableAttributedString) {
        text.append(attributed(title, font: titleFont, color: ink))
        text.append(attributed("\n\(subtitle)\n", font: subtitleFont, color: gray))
        text.append(attributed("――――――――――――――――――――――――――\n", font: NSFont.systemFont(ofSize: 8), color: red))
        appendBreak(to: text)
    }

    static func appendBlocks(_ blocks: [MarkdownBlock], to text: NSMutableAttributedString) {
        for block in blocks {
            switch block {
            case .header(let title):
                appendBreak(to: text)
                text.append(attributed(title.uppercased(), font: headerFont, color: ink))
                text.append(attributed("\n", font: bodyFont, color: ink))
            case .bullet(let s):
                text.append(attributed("•  ", font: bodyFont, color: red))
                text.append(attributed(s, font: bodyFont, color: ink))
                appendBreak(to: text)
            case .ordered(let n, let s):
                text.append(attributed("\(n).  ", font: bodyFont, color: red))
                text.append(attributed(s, font: bodyFont, color: ink))
                appendBreak(to: text)
            case .table(let rows):
                appendTable(rows, to: text)
            case .para(let s):
                text.append(attributed(s, font: bodyFont, color: ink))
                appendBreak(to: text)
            }
        }
    }

    /// Переносим текст внутри каждой ячейки до разметки по колонкам.
    static func appendTable(_ rows: [[String]], to text: NSMutableAttributedString) {
        guard let columns = rows.map(\.count).max(), columns > 0 else { return }
        let usable = pageRect.width - inset * 2
        let fractions: [CGFloat] = columns == 4
            ? [0.16, 0.44, 0.18, 0.22]
            : Array(repeating: 1 / CGFloat(columns), count: columns)
        let widths = fractions.map { $0 * usable }
        var offset: CGFloat = 0
        let para = NSMutableParagraphStyle()
        para.tabStops = widths.dropLast().map { width in
            offset += width
            return NSTextTab(textAlignment: .left, location: offset, options: [:])
        }

        for (rowIndex, cells) in rows.enumerated() {
            let font = rowIndex == 0 ? tableHeadFont : tableFont
            let color = rowIndex == 0 ? red : ink
            let wrapped = widths.enumerated().map { column, width in
                wrapCell(column < cells.count ? cells[column] : "", font: font, width: max(8, width - 10))
            }
            let height = wrapped.map(\.count).max() ?? 0
            for index in 0..<height {
                let line = wrapped.map { index < $0.count ? $0[index] : "" }.joined(separator: "\t")
                text.append(attributed(line + "\n", font: font, color: color, paragraph: para))
            }
            appendBreak(to: text)
        }
    }

    private static func wrapCell(_ text: String, font: NSFont, width: CGFloat) -> [String] {
        guard !text.isEmpty else { return [] }
        let source = text as NSString
        let typesetter = CTTypesetterCreateWithAttributedString(attributed(text, font: font, color: ink))
        var result: [String] = []
        var start = 0
        while start < source.length {
            let suggested = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
            let length = suggested > 0 ? suggested : source.rangeOfComposedCharacterSequence(at: start).length
            let line = source.substring(with: NSRange(location: start, length: length))
            result.append(line.trimmingCharacters(in: .whitespaces))
            start += length
        }
        return result
    }

    // MARK: - Пагинация CoreText → PDF

    static func render(_ attributed: NSAttributedString) -> Data {
        let out = NSMutableData()
        var mediaBox = pageRect
        guard let consumer = CGDataConsumer(data: out as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { return out as Data }
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let textRect = pageRect.insetBy(dx: inset, dy: inset)
        var location = 0
        let total = attributed.length

        while location < total {
            ctx.beginPDFPage(nil)
            let path = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: location, length: 0),
                path, nil
            )
            CTFrameDraw(frame, ctx)
            let visible = CTFrameGetVisibleStringRange(frame)
            if visible.length == 0 { break } // защита от бесконечного цикла
            location += visible.length
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return out as Data
    }
}
