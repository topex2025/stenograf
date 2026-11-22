import Foundation

/// Разбор markdown-протокола в блоки — для вёрстки в приложении и экспорта в PDF.
public enum MarkdownBlock: Identifiable {
    case header(String)
    case bullet(String)
    case ordered(Int, String)
    case table([[String]])
    case para(String)

    public var id: String {
        switch self {
        case .header(let s): "h:\(s)"
        case .bullet(let s): "b:\(s)"
        case .ordered(let n, let s): "o:\(n):\(s)"
        case .table(let rows): "t:\(rows.map { $0.joined(separator: "|") }.joined(separator: "\n"))"
        case .para(let s): "p:\(s)"
        }
    }

    public static func parse(_ md: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var tableBuffer: [[String]] = []

        func flushTable() {
            guard !tableBuffer.isEmpty else { return }
            blocks.append(.table(tableBuffer))
            tableBuffer = []
        }

        for rawLine in md.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flushTable(); continue }
            if line.hasPrefix("## ") { flushTable(); blocks.append(.header(String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces))); continue }
            if line.hasPrefix("# ") { flushTable(); blocks.append(.header(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))); continue }
            if line.hasPrefix("|") {
                let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                if cells.allSatisfy({ $0.isEmpty || $0.allSatisfy { $0 == "-" || $0 == ":" || $0.isWhitespace } }) { continue } // разделитель
                tableBuffer.append(cells)
                continue
            }
            flushTable()
            if line.hasPrefix("- ") || line.hasPrefix("* ") { blocks.append(.bullet(String(line.dropFirst(2)))); continue }
            let digits = line.prefix(while: { $0.isNumber })
            if !digits.isEmpty, let n = Int(digits), line.dropFirst(digits.count).hasPrefix(". ") {
                blocks.append(.ordered(n, String(line.dropFirst(digits.count + 2))))
                continue
            }
            blocks.append(.para(line))
        }
        flushTable()
        return blocks
    }
}
