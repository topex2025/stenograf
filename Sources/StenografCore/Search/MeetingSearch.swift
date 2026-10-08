import Foundation

/// Поиск по всем встречам: транскрипты + резюме/протоколы, локально, без БД.
/// Регистронезависимо, «ё»=«е», несколько слов = И (все слова должны найтись).
public struct SearchHit: Sendable, Identifiable, Hashable {
    public let id: UUID
    public let meetingID: UUID
    public let title: String
    public let date: Date
    /// Строка с первым совпадением и контекстом.
    public let snippet: String
    /// Где нашли: «транскрипт» или имя файла резюме.
    public let source: String
    /// Суммарное число вхождений всех слов.
    public let score: Int
}

public enum MeetingSearch {
    public static func normalize(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "ё", with: "е")
    }

    /// Совпадение слова с учётом русских окончаний: общее начало покрывает
    /// почти всю короткую сторону слова (смета/смету, поставщик/поставщику, обещает/обещал).
    /// Короткие токены (предлоги «к», «по») внутрь длинных слов не матчатся.
    static func tokenMatches(_ token: String, _ word: String) -> Bool {
        if token.count >= 4 && word.count >= 4 {
            if token.contains(word) || word.contains(token) { return true }
        }
        let common = zip(token, word).prefix { $0 == $1 }.count
        let shorter = min(token.count, word.count)
        return shorter >= 4 && common >= shorter - 1
    }

    static func tokenize(_ line: String) -> [String] {
        line.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// Ищет по всем встречам хранилища.
    /// requireAllWords=true — все слова должны найтись (режим поиска в UI);
    /// false — достаточно любого слова, ранжирование по числу совпадений (режим вопросов).
    public static func search(store: MeetingStore, query: String, limit: Int = 50, requireAllWords: Bool = true) -> [SearchHit] {
        let words = normalize(query)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }

        var hits: [SearchHit] = []
        for meeting in store.listAll() {
            let sources = searchableTexts(meeting: meeting, store: store)
            var totalScore = 0
            var best: (snippet: String, source: String)?
            var matchedWords = Set<String>()

            for (source, text) in sources {
                let lines = text.components(separatedBy: .newlines)
                for rawLine in lines {
                    let lineTokens = tokenize(normalize(rawLine))
                    guard !lineTokens.isEmpty else { continue }
                    var lineScore = 0
                    for token in lineTokens {
                        for word in words where tokenMatches(token, word) {
                            lineScore += 1
                            matchedWords.insert(word)
                        }
                    }
                    guard lineScore > 0 else { continue }
                    totalScore += lineScore
                    if best == nil {
                        best = (snippet(raw: rawLine, words: words), source)
                    }
                }
            }

            // И: все слова; ИЛИ: хотя бы одно (для вопросов по встречам)
            let ok = requireAllWords ? matchedWords.count == words.count : totalScore > 0
            if ok {
                hits.append(SearchHit(
                    id: UUID(),
                    meetingID: meeting.id,
                    title: meeting.title,
                    date: meeting.createdAt,
                    snippet: best?.snippet ?? "",
                    source: best?.source ?? "",
                    score: totalScore
                ))
            }
        }
        return Array(hits.sorted { $0.score > $1.score }.prefix(limit))
    }

    /// Обрезает строку до читаемого сниппета вокруг первого совпадения.
    /// Если слово в другой форме (смета vs смету) — берём начало строки.
    static func snippet(raw: String, words: [String]) -> String {
        let lowered = normalize(raw)
        var first: Range<String.Index>? = nil
        for word in words {
            if let r = lowered.range(of: word) {
                if first == nil || r.lowerBound < first!.lowerBound { first = r }
            }
        }
        guard let hit = first else { return String(raw.prefix(140)).trimmingCharacters(in: .whitespaces) }
        let start = lowered.index(hit.lowerBound, offsetBy: -50, limitedBy: lowered.startIndex) ?? lowered.startIndex
        let end = lowered.index(hit.upperBound, offsetBy: 70, limitedBy: lowered.endIndex) ?? lowered.endIndex
        let prefixEllipsis = start > lowered.startIndex ? "…" : ""
        let suffixEllipsis = end < lowered.endIndex ? "…" : ""
        return "\(prefixEllipsis)\(raw[start..<end])\(suffixEllipsis)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func searchableTexts(meeting: Meeting, store: MeetingStore) -> [(source: String, text: String)] {
        var out: [(String, String)] = []
        if let t = try? store.readTranscript(meeting), !t.isEmpty {
            out.append(("транскрипт", t))
        }
        let summariesDir = store.summariesDir(for: meeting)
        if let files = try? FileManager.default.contentsOfDirectory(at: summariesDir, includingPropertiesForKeys: nil) {
            for f in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where f.pathExtension == "md" {
                if let text = try? String(contentsOf: f, encoding: .utf8), !text.isEmpty {
                    out.append((f.deletingPathExtension().lastPathComponent, text))
                }
            }
        }
        return out
    }
}
