import AVFoundation

/// Запись с микрофона в wav 16 кГц моно — нативный вход whisper.cpp.
/// Использование: start() → ... → stop() (файл дозаписывается на stop).
public final class AudioRecorder: NSObject, AVAudioRecorderDelegate, @unchecked Sendable {
    private var recorder: AVAudioRecorder?
    private var startedAt: Date?
    public private(set) var outputFile: String?

    public func start(to path: String) throws {
        guard recorder == nil else { return }
        // На macOS разрешение запрашивает система при первом старте записи;
        // при отказе AVAudioRecorder.record() вернёт false — обрабатываем ниже.
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let r = try AVAudioRecorder(url: url, settings: settings)
        r.delegate = self
        guard r.record() else {
            throw StenografError.missingFile("не удалось начать запись (микрофон занят или нет доступа)")
        }
        recorder = r
        startedAt = Date()
        outputFile = path
    }

    /// Останавливает запись, возвращает длительность в секундах.
    @discardableResult
    public func stop() -> Double? {
        defer { recorder = nil }
        recorder?.stop()
        let duration = startedAt.map { Date().timeIntervalSince($0) }
        startedAt = nil
        return duration
    }

    public var isRecording: Bool { recorder?.isRecording ?? false }
}
