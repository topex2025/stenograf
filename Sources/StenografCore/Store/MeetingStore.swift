import Foundation

/// Файловое хранилище встреч:
/// ~/Library/Application Support/Stenograf/meetings/<uuid>/{meta.json, audio.wav, transcript.md, summaries/*.md}
public struct MeetingStore: Sendable {
    public let root: URL

    public static let `default` = MeetingStore()

    public init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.root = base.appendingPathComponent("Stenograf/meetings", isDirectory: true)
        }
    }

    public func dir(for meeting: Meeting) -> URL {
        root.appendingPathComponent(meeting.id.uuidString, isDirectory: true)
    }

    @discardableResult
    public func create(title: String = "Встреча") throws -> Meeting {
        var meeting = Meeting(title: title)
        let folder = dir(for: meeting)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try saveMeta(&meeting)
        return meeting
    }

    public func saveMeta(_ meeting: inout Meeting) throws {
        let data = try JSONEncoder().encode(meeting)
        try data.write(to: dir(for: meeting).appendingPathComponent("meta.json"), options: [.atomic])
    }

    public func audioURL(for meeting: Meeting) -> URL {
        dir(for: meeting).appendingPathComponent("audio.wav")
    }

    public func transcriptURL(for meeting: Meeting) -> URL {
        dir(for: meeting).appendingPathComponent("transcript.md")
    }

    public func summariesDir(for meeting: Meeting) -> URL {
        dir(for: meeting).appendingPathComponent("summaries", isDirectory: true)
    }

    /// Записать транскрипт: markdown-текст + метаданные в meta.json.
    public func writeTranscript(_ result: WhisperCLI.Result, to meeting: inout Meeting) throws {
        let md = result.segments.isEmpty
            ? result.text
            : result.segments.map { seg in
                String(format: "[%02d:%02d] %@", Int(seg.start) / 60, Int(seg.start) % 60, seg.text)
              }.joined(separator: "\n")
        try md.write(to: transcriptURL(for: meeting), atomically: true, encoding: .utf8)
        meeting.transcriptFile = "transcript.md"
        try saveMeta(&meeting)
    }

    /// Записать резюме от мозга: summaries/<шаблон>-<время>.md
    @discardableResult
    public func writeSummary(_ text: String, template: PromptTemplate, brain: String, to meeting: Meeting) throws -> URL {
        let dir = summariesDir(for: meeting)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = dir.appendingPathComponent("\(template.rawValue)-\(brain)-\(stamp).md")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Сохраняет исправления и оставляет исходное распознавание рядом с записью.
    public func correctTranscript(_ text: String, for meeting: Meeting) throws {
        let url = transcriptURL(for: meeting)
        let original = dir(for: meeting).appendingPathComponent("transcript-original.md")
        if !FileManager.default.fileExists(atPath: original.path) {
            try FileManager.default.copyItem(at: url, to: original)
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Выдаёт документы, созданные по текущей версии транскрипта.
    func currentDocuments(for meeting: Meeting) -> [URL] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        let transcriptDate = try? transcriptURL(for: meeting).resourceValues(forKeys: keys).contentModificationDate
        let files = (try? FileManager.default.contentsOfDirectory(
            at: summariesDir(for: meeting), includingPropertiesForKeys: Array(keys)
        )) ?? []
        return files.filter { file in
            guard file.pathExtension == "md" else { return false }
            guard let transcriptDate else { return true }
            guard let reportDate = try? file.resourceValues(forKeys: keys).contentModificationDate else { return false }
            return reportDate >= transcriptDate
        }
    }

    public func latestDocument(meeting: Meeting, prefix: String) -> URL? {
        currentDocuments(for: meeting)
            .filter { $0.lastPathComponent.hasPrefix(prefix + "-") }
            .max { lhs, rhs in
                let keys: Set<URLResourceKey> = [.contentModificationDateKey]
                let left = (try? lhs.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
                return left == right ? lhs.lastPathComponent < rhs.lastPathComponent : left < right
            }
    }

    public func readTranscript(_ meeting: Meeting) throws -> String {
        try String(contentsOf: transcriptURL(for: meeting), encoding: .utf8)
    }

    public func listAll() -> [Meeting] {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        return folders
            .compactMap { folder -> Meeting? in
                guard let data = try? Data(contentsOf: folder.appendingPathComponent("meta.json")) else { return nil }
                return try? JSONDecoder().decode(Meeting.self, from: data)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }
}
