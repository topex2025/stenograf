import XCTest
@testable import StenografCore

/// E2E на реальной машине: синтезируем русскую речь (say, голос Milena),
/// конвертируем в wav 16k моно (afconvert), гоняем через реальный whisper-cli.
/// Пропускается, если инструментов/модели нет (например, в CI).
final class TranscribeE2ETests: XCTestCase {
    func testRussianSpeechTranscribedLocally() throws {
        let fm = FileManager.default
        let whisperPath = "/opt/homebrew/bin/whisper-cli"
        let modelPath = NSString(string: "~/.cache/whisper/ggml-medium-q5_0.bin").expandingTildeInPath
        guard fm.fileExists(atPath: whisperPath), fm.fileExists(atPath: modelPath) else {
            throw XCTSkip("нет whisper-cli или модели — E2E пропущен")
        }

        let tmp = fm.temporaryDirectory.appendingPathComponent("stenograf-e2e-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let aiff = tmp.appendingPathComponent("sample.aiff").path
        let wav = tmp.appendingPathComponent("sample.wav").path
        let phrase = "Стенограф записывает встречу и готовит протокол."

        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", "Milena", "-o", aiff, phrase]
        try say.run(); say.waitUntilExit()
        XCTAssertEqual(say.terminationStatus, 0, "say не смог синтезировать речь")

        let conv = Process()
        conv.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        conv.arguments = ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", aiff, wav]
        try conv.run(); conv.waitUntilExit()
        XCTAssertEqual(conv.terminationStatus, 0, "afconvert не сконвертировал")

        let whisper = WhisperCLI(cliPath: whisperPath, modelPath: modelPath, language: "ru")
        let result = try whisper.transcribe(audioFile: wav)

        XCTAssertFalse(result.text.isEmpty, "пустой транскрипт")
        let lowered = result.text.lowercased()
        XCTAssertTrue(
            lowered.contains("стенограф") || lowered.contains("записывает") || lowered.contains("протокол"),
            "транскрипт не узнал опорные слова, получил: \(result.text)"
        )
        XCTAssertFalse(result.segments.isEmpty, "нет сегментов с таймкодами")
    }
}
