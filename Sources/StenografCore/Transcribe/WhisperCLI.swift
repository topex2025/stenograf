import Foundation

/// Обёртка над системным whisper-cli (whisper.cpp, Homebrew).
/// Возвращает текст и сегменты с таймкодами. Аудио остаётся на машине.
public struct WhisperCLI: Sendable {
    public struct Segment: Codable, Sendable {
        public let start: Double
        public let end: Double
        public let text: String
    }

    public struct Result: Sendable {
        public let text: String
        public let segments: [Segment]
        /// Язык, определённый whisper при language=auto (например "ru"). nil — если не отдал.
        public let detectedLanguage: String?

        public init(text: String, segments: [Segment], detectedLanguage: String? = nil) {
            self.text = text
            self.segments = segments
            self.detectedLanguage = detectedLanguage
        }
    }

    let cliPath: String
    let modelPath: String
    let language: String

    public init(whisper: WhisperConfig) {
        self.init(cliPath: whisper.cliPath, modelPath: whisper.modelPath, language: whisper.language)
    }

    public init(cliPath: String, modelPath: String, language: String = "ru") {
        self.cliPath = cliPath
        self.modelPath = modelPath
        self.language = language
    }

    /// Прогоняет wav через whisper-cli. Выходные файлы пишет во временный каталог.
    public func transcribe(audioFile: String) throws -> Result {
        let fm = FileManager.default
        guard fm.fileExists(atPath: audioFile) else { throw StenografError.missingFile(audioFile) }
        guard fm.fileExists(atPath: cliPath) else { throw StenografError.missingFile("\(cliPath) (brew install whisper-cpp)") }
        guard fm.fileExists(atPath: modelPath) else { throw StenografError.missingFile(modelPath) }

        let outDir = fm.temporaryDirectory
            .appendingPathComponent("stenograf-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: outDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: outDir) }
        let outBase = outDir.appendingPathComponent("out").path

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = [
            "-m", modelPath,
            "-f", audioFile,
            "-l", language,
            "-otxt", "-oj",
            "-of", outBase,
            "-np",
            "-t", "8",
        ]
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData.prefix(1000), encoding: .utf8) ?? ""
            throw StenografError.whisperFailed(process.terminationStatus, errText)
        }

        let txtPath = outBase + ".txt"
        guard let text = try? String(contentsOfFile: txtPath, encoding: .utf8) else {
            throw StenografError.whisperFailed(0, "whisper-cli не создал \(txtPath)")
        }

        var segments: [Segment] = []
        var detectedLanguage: String?
        if let jsonData = fm.contents(atPath: outBase + ".json"),
           let parsed = try? JSONDecoder().decode(WhisperJSON.self, from: jsonData) {
            segments = parsed.transcription.map {
                Segment(start: $0.offsets.from / 1000.0, end: $0.offsets.to / 1000.0, text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            detectedLanguage = parsed.language
        }
        return Result(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            segments: segments,
            detectedLanguage: detectedLanguage
        )
    }

    fileprivate struct WhisperJSON: Codable {
        let transcription: [Entry]
        let language: String?
        struct Entry: Codable {
            let offsets: Offsets
            let text: String
            struct Offsets: Codable { let from: Double; let to: Double }
        }
    }
}
