import SwiftUI
import AVFoundation
import StenografCore

// MARK: - Плеер записи встречи

@MainActor
final class PlayerModel: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var available = false

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func load(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        duration = player?.duration ?? 0
        available = player != nil && duration > 0
    }

    func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            timer?.invalidate()
        } else {
            player.play()
            isPlaying = true
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let p = self.player else { return }
                    self.currentTime = p.currentTime
                    if !p.isPlaying {
                        self.isPlaying = false
                        self.currentTime = 0
                        p.currentTime = 0
                        self.timer?.invalidate()
                    }
                }
            }
        }
    }

    func seek(to time: Double) {
        player?.currentTime = time
        currentTime = time
    }

    func stop() {
        player?.stop()
        timer?.invalidate()
        isPlaying = false
    }
}

struct AudioPlayerBar: View {
    @ObservedObject var player: PlayerModel

    var body: some View {
        HStack(spacing: 12) {
            Button {
                player.toggle()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(LinearGradient(colors: [Color.stenoRed, .orange], startPoint: .top, endPoint: .bottom))
            }
            .buttonStyle(.plain)
            VStack(spacing: 3) {
                Slider(
                    value: Binding(
                        get: { player.currentTime },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...max(player.duration, 0.1)
                )
                HStack {
                    Text(mmss(player.currentTime)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    Spacer()
                    Text(mmss(player.duration)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private func mmss(_ t: Double) -> String {
        String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

@main
struct StenografApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Стенограф", systemImage: model.isRecording ? "record.circle" : "waveform") {
            MenuBarView()
                .environmentObject(model)
        }
        WindowGroup {
            MeetingsWindow()
                .environmentObject(model)
        }
        .windowResizability(.contentSize)
    }
}

/// Открывает окно встреч при запуске (MenuBarExtra-первое приложение само его не показывает).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if NSApp.windows.first(where: { $0.canBecomeMain && $0.frame.height > 100 }) == nil {
                NSApp.sendAction(Selector(("newWindowForTab:")), to: nil, from: nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var isRecording = false
    @Published var lastMessage = ""
    @Published var meetings: [Meeting] = []
    @Published var busy = false
    @Published var searchText = ""
    /// Встреча, чей текст показываем в окне-детали.
    @Published var selectedMeeting: Meeting?

    private let recorder = AudioRecorder()
    private let store = MeetingStore.default
    private var currentMeeting: Meeting?
    var config: AppConfig?

    init() { reload() }

    func reload() {
        meetings = store.listAll()
        config = try? AppConfig.load()
    }

    var hasConfig: Bool { config != nil }

    func chatGPTStatus() -> (loggedIn: Bool, detail: String) {
        CodexSubscriptionBrain.loginStatus()
    }

    func loginChatGPT() {
        let current = CodexSubscriptionBrain.loginStatus()
        if current.loggedIn {
            lastMessage = current.detail
            return
        }
        let cli = CodexSubscriptionBrain.resolveCliPath()
        guard FileManager.default.fileExists(atPath: cli) else {
            lastMessage = "Codex CLI не найден: brew install --cask codex"
            return
        }
        lastMessage = "Открыл браузер для входа в ChatGPT…"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: cli)
        proc.arguments = ["login"]
        try? proc.run()
        proc.waitUntilExit()
        let status = CodexSubscriptionBrain.loginStatus()
        lastMessage = status.detail
    }

    func toggleRecording() {
        if isRecording {
            let duration = recorder.stop()
            if var m = currentMeeting {
                m.durationSeconds = duration
                try? store.saveMeta(&m)
            }
            isRecording = false
            reload()
            if let meeting = currentMeeting, config?.autoProtocol ?? true {
                autoProcess(meeting: meeting)
            } else {
                lastMessage = L10n.tf(.recordStopped, Int(duration ?? 0))
            }
        } else {
            do {
                var meeting = try store.create(title: "Встреча \(meetings.count + 1)")
                try recorder.start(to: store.audioURL(for: meeting).path)
                meeting.audioFile = "audio.wav"
                try store.saveMeta(&meeting)
                currentMeeting = meeting
                isRecording = true
                searchText = "" // чтобы новая встреча не спряталась за фильтром
                lastMessage = L10n.t(.recordingMsg)
            } catch {
                lastMessage = "Не удалось начать запись: \(error.localizedDescription)"
            }
        }
    }

    /// Автопротокол: транскрипция локально → протокол мозгом по умолчанию.
    private func autoProcess(meeting: Meeting) {
        busy = true
        lastMessage = L10n.t(.autoTranscribing)
        let store = self.store
        Task.detached {
            do {
                let cfg = try AppConfig.load()
                let (brainName, brainCfg) = try cfg.brain(named: nil)
                let result = try await Pipeline.autoProcess(
                    meeting: meeting,
                    store: store,
                    whisper: WhisperCLI(whisper: cfg.whisper),
                    brain: BrainFactory.make(brainCfg),
                    brainName: brainName
                )
                await MainActor.run {
                    let lang = result.detectedLanguage.map { ", язык \($0)" } ?? ""
                    self.lastMessage = L10n.tf(.autoDoneFmt, lang, result.transcript.count)
                    self.busy = false
                    self.reload()
                    // сразу показываем текст — пользователь его ждёт
                    if let fresh = self.meetings.first(where: { $0.id == meeting.id }) {
                        self.selectedMeeting = fresh
                    }
                }
            } catch {
                await MainActor.run {
                    self.lastMessage = L10n.tf(.autoFailedFmt, error.localizedDescription)
                    self.busy = false
                }
            }
        }
    }

    func search(_ query: String) -> [SearchHit] {
        MeetingSearch.search(store: store, query: query)
    }

    func openTranscript(_ hit: SearchHit) {
        if let meeting = meetings.first(where: { $0.id == hit.meetingID }) {
            selectedMeeting = meeting
        }
    }

    /// Аудио встречи, если файл существует.
    func audioURL(for meeting: Meeting) -> URL? {
        let u = store.audioURL(for: meeting)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    /// Тексты встречи для окна-детали: транскрипт + все протоколы (свежие сверху).
    func detailTexts(for meeting: Meeting) -> (transcript: String?, protocols: [(name: String, text: String)]) {
        let transcript = try? store.readTranscript(meeting)
        var protocols: [(String, String)] = []
        if let files = try? FileManager.default.contentsOfDirectory(at: store.summariesDir(for: meeting), includingPropertiesForKeys: nil) {
            for f in files.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) where f.pathExtension == "md" {
                if let text = try? String(contentsOf: f, encoding: .utf8) {
                    protocols.append((f.deletingPathExtension().lastPathComponent, text))
                }
            }
        }
        return (transcript, protocols)
    }

    func transcribe(_ meeting: Meeting) {
        busy = true
        lastMessage = "Транскрибирую локально…"
        let store = self.store
        var m = meeting
        Task.detached {
            do {
                let cfg = try AppConfig.load()
                let result = try WhisperCLI(whisper: cfg.whisper).transcribe(audioFile: store.audioURL(for: m).path)
                try store.writeTranscript(result, to: &m)
                await MainActor.run {
                    self.lastMessage = "Транскрипт готов: \(result.text.count) знаков"
                    self.busy = false
                    self.reload()
                }
            } catch {
                await MainActor.run {
                    self.lastMessage = "Ошибка транскрипции: \(error.localizedDescription)"
                    self.busy = false
                }
            }
        }
    }

    func summarize(_ meeting: Meeting, template: PromptTemplate = .meetingProtocol) {
        busy = true
        lastMessage = "Спрашиваю мозг…"
        let store = self.store
        Task.detached {
            do {
                let cfg = try AppConfig.load()
                let transcript = try store.readTranscript(meeting)
                let (name, brainCfg) = try cfg.brain(named: nil)
                let brain = BrainFactory.make(brainCfg)
                let answer = try await brain.complete(
                    system: template.systemPrompt(),
                    user: "Транскрипт встречи:\n\n\(transcript)"
                )
                _ = try store.writeSummary(answer, template: template, brain: name, to: meeting)
                await MainActor.run {
                    self.lastMessage = "Резюме сохранено"
                    self.busy = false
                }
            } catch {
                await MainActor.run {
                    self.lastMessage = "Ошибка мозгов: \(error.localizedDescription)"
                    self.busy = false
                }
            }
        }
    }

    func openFolder() {
        NSWorkspace.shared.open(store.root)
    }
}

struct MenuBarView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.lastMessage.isEmpty {
                Text(model.lastMessage).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(model.isRecording ? L10n.t(.stopRecord) : L10n.t(.recordStart)) {
                model.toggleRecording()
            }
            .keyboardShortcut("r")
            Divider()
            if model.meetings.isEmpty {
                Text("Встреч пока нет").font(.caption)
            }
            ForEach(model.meetings.prefix(5)) { meeting in
                MeetingRow(meeting: meeting)
            }
            Divider()
            let chatGPT = model.chatGPTStatus()
            if chatGPT.loggedIn {
                Label(L10n.t(.chatgptActive), systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            } else {
                Button(L10n.t(.loginButton)) { model.loginChatGPT() }
                    .font(.caption)
                Text(chatGPT.detail).font(.caption2).foregroundStyle(.secondary)
            }
            Divider()
            Button(L10n.t(.openFolder)) { model.openFolder() }
            Button(L10n.t(.quit)) { NSApplication.shared.terminate(nil) }
        }
        .buttonStyle(.plain)
        .padding(8)
        .frame(minWidth: 280)
        .onAppear { model.reload() }
    }
}

struct SearchHitRow: View {
    let hit: SearchHit

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(hit.title).font(.headline)
                Spacer()
                Text("\(hit.date.formatted(date: .abbreviated, time: .shortened)) · \(hit.source) · ×\(hit.score)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text(hit.snippet)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(.vertical, 3)
    }
}

struct MeetingRow: View {
    @EnvironmentObject var model: AppModel
    let meeting: Meeting

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title).font(.headline)
                Text(meeting.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if meeting.transcriptFile == nil {
                Button(L10n.t(.transcribeButton)) { model.transcribe(meeting) }
                    .font(.caption).disabled(model.busy)
            } else {
                HStack(spacing: 6) {
                    Button(L10n.t(.summaryButton)) { model.summarize(meeting, template: .summary) }
                        .font(.caption).disabled(model.busy)
                    Button(L10n.t(.protocolButton)) { model.summarize(meeting) }
                        .font(.caption).disabled(model.busy)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct MeetingsWindow: View {
    @EnvironmentObject var model: AppModel
    @State private var showAsk = false

    var body: some View {
        VStack(spacing: 0) {
            // Шапка: название + статус подписки + кнопка записи
            HStack(spacing: 12) {
                Image(systemName: model.isRecording ? "record.circle" : "waveform")
                    .font(.title2)
                    .foregroundStyle(model.isRecording ? .red : .accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Стенограф").font(.title2.bold())
                    Text(L10n.t(.tagline))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showAsk = true
                } label: {
                    Label(L10n.t(.askButton), systemImage: "text.bubble")
                }
                .buttonStyle(.bordered)
                let chatGPT = model.chatGPTStatus()
                Label(
                    chatGPT.loggedIn ? L10n.t(.chatgptActive) : L10n.t(.chatgptNeedsLogin),
                    systemImage: chatGPT.loggedIn ? "checkmark.circle.fill" : "exclamationmark.circle"
                )
                .font(.caption)
                .foregroundStyle(chatGPT.loggedIn ? .green : .orange)
                Button(model.isRecording ? L10n.t(.stopRecord) : L10n.t(.recordStart)) {
                    model.toggleRecording()
                }
                .keyboardShortcut("r")
                .tint(model.isRecording ? .red : .accentColor)
                .buttonStyle(.borderedProminent)
            }
            .padding(12)

            Divider()

            // Поиск по всем встречам (транскрипты + протоколы)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L10n.t(.searchPlaceholder), text: $model.searchText)
                    .textFieldStyle(.plain)
                if !model.searchText.isEmpty {
                    Button("✕") { model.searchText = "" }.buttonStyle(.link).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            Divider()

            if !model.lastMessage.isEmpty {
                Text(model.lastMessage)
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 6)
            }

            if !model.searchText.isEmpty {
                let hits = model.search(model.searchText)
                if hits.isEmpty {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
                        Text(L10n.tf(.noResultsFmt, model.searchText)).font(.headline)
                        Text(L10n.t(.searchHint)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    List(hits) { hit in
                        SearchHitRow(hit: hit)
                            .contentShape(Rectangle())
                            .onTapGesture { model.openTranscript(hit) }
                    }
                    .listStyle(.inset)
                }
            } else if model.meetings.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "mic.badge.xmark").font(.largeTitle).foregroundStyle(.secondary)
                    Text(L10n.t(.emptyTitle)).font(.headline)
                    Text(L10n.t(.emptyBody))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                List(model.meetings) { meeting in
                    MeetingRow(meeting: meeting)
                        .contentShape(Rectangle())
                        .onTapGesture { model.selectedMeeting = meeting }
                }
                .listStyle(.inset)
            }
            Divider()
            HStack {
                Text(L10n.tf(.footerFmt, model.config?.defaultBrain ?? "—"))
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.t(.openFolder)) { model.openFolder() }
                    .font(.caption).buttonStyle(.link)
            }
            .padding(8)
        }
        .frame(minWidth: 560, minHeight: 380)
        .sheet(isPresented: $showAsk) {
            QuestionSheet()
        }
        .sheet(item: $model.selectedMeeting) { meeting in
            MeetingDetailSheet(meeting: meeting)
                .environmentObject(model)
        }
        .onAppear { model.reload() }
    }
}

// MARK: - Вёрстка протокола и транскрипта

extension Color {
    static let stenoRed = Color(red: 1.00, green: 0.23, blue: 0.31)   // #FF3B4E
    static let stenoInk = Color(red: 0.04, green: 0.06, blue: 0.10)   // чернильный
}

/// Разбор markdown-протокола в блоки для красивой вёрстки.
enum MarkdownBlock: Identifiable {
    case header(String)
    case bullet(String)
    case ordered(Int, String)
    case table([[String]])
    case para(String)

    var id: String {
        switch self {
        case .header(let s): "h:\(s)"
        case .bullet(let s): "b:\(s)"
        case .ordered(let n, let s): "o:\(n):\(s)"
        case .table(let rows): "t:\(rows.map { $0.joined(separator: "|") }.joined(separator: "\n"))"
        case .para(let s): "p:\(s)"
        }
    }

    static func parse(_ md: String) -> [MarkdownBlock] {
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

/// Протокол, свёрстанный как документ: секции с акцентной полосой, таблица обязательств.
struct ProtocolDocument: View {
    let markdown: String

    var body: some View {
        let blocks = MarkdownBlock.parse(markdown)
        return VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .header(let title):
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(LinearGradient(colors: [Color.stenoRed, .orange], startPoint: .top, endPoint: .bottom))
                            .frame(width: 5, height: 18)
                        Text(title)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .textSelection(.enabled)
                        Spacer()
                    }
                case .bullet(let text):
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(Color.stenoRed).frame(width: 6, height: 6).padding(.top, 7)
                        Text(text)
                            .font(.system(size: 14.5))
                            .lineSpacing(3)
                            .textSelection(.enabled)
                    }
                case .ordered(let n, let text):
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(n)")
                            .font(.footnote.bold())
                            .foregroundStyle(.white)
                            .frame(width: 21, height: 21)
                            .background(Circle().fill(Color.stenoRed))
                        Text(text)
                            .font(.system(size: 14.5))
                            .lineSpacing(3)
                            .textSelection(.enabled)
                    }
                case .table(let rows):
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, cells in
                            HStack(spacing: 8) {
                                ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                                    Text(cell)
                                        .font(rowIndex == 0 ? .system(size: 12.5, weight: .bold) : .system(size: 14))
                                        .foregroundStyle(rowIndex == 0 ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 9)
                                        .padding(.horizontal, 8)
                                }
                            }
                            .background(
                                rowIndex == 0
                                    ? AnyShapeStyle(Color.stenoInk)
                                    : AnyShapeStyle(rowIndex.isMultiple(of: 2) ? Color.primary.opacity(0.04) : Color.clear)
                            )
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
                case .para(let text):
                    Text(text)
                        .font(.system(size: 14.5))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Транскрипт: таймкод-чип + реплика.
struct TranscriptView: View {
    let transcript: String

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 10) {
                    Text(line.timecode)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Capsule().fill(.secondary.opacity(0.85)))
                        .frame(minWidth: 46, alignment: .center)
                    Text(line.text)
                        .font(.system(size: 14.5, design: .rounded))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lines: [(timecode: String, text: String)] {
        transcript.components(separatedBy: .newlines).map { raw in
            // формат "[mm:ss] текст"
            if let close = raw.firstIndex(of: "]"), raw.hasPrefix("["), close > raw.startIndex {
                let tc = String(raw[raw.index(after: raw.startIndex)..<close])
                let rest = String(raw[raw.index(after: close)...]).trimmingCharacters(in: .whitespaces)
                return (tc, rest.isEmpty ? "…" : rest)
            }
            return ("—", raw)
        }
    }
}

/// Окно текста встречи: плеер записи, транскрипт и протоколы как документ.
struct MeetingDetailSheet: View {
    @EnvironmentObject var model: AppModel
    let meeting: Meeting
    @StateObject private var player = PlayerModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(LinearGradient(colors: [Color.stenoRed, .orange], startPoint: .top, endPoint: .bottom))
                VStack(alignment: .leading, spacing: 3) {
                    Text(meeting.title).font(.system(.title3, design: .rounded).bold())
                    HStack(spacing: 6) {
                        Chip(text: meeting.createdAt.formatted(date: .abbreviated, time: .shortened))
                        if let d = meeting.durationSeconds { Chip(text: "\(Int(d)) \(L10n.t(.secondsShort))") }
                    }
                }
                Spacer()
                CopyButton(text: allText, label: L10n.t(.copyAll))
                Button(L10n.t(.done)) { player.stop(); model.selectedMeeting = nil }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
            Divider()
            // Плеер: прослушать запись
            if let audioURL = model.audioURL(for: meeting) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t(.listenTitle))
                        .font(.system(size: 11, weight: .heavy))
                        .kerning(1.5)
                        .foregroundStyle(.secondary)
                    AudioPlayerBar(player: player)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .onAppear { player.load(url: audioURL) }
                .onDisappear { player.stop() }
                Divider()
            }
            let texts = model.detailTexts(for: meeting)
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if let transcript = texts.transcript, !transcript.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(L10n.t(.transcriptTitle))
                                .font(.system(size: 11, weight: .heavy))
                                .kerning(1.5)
                                .foregroundStyle(.secondary)
                            TranscriptView(transcript: transcript)
                                .padding(16)
                                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    if texts.protocols.isEmpty {
                        Label(L10n.t(.noProtocol), systemImage: "doc.badge.plus")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(texts.protocols, id: \.name) { proto in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(proto.name.hasPrefix("summary") ? L10n.t(.summaryTitle) : L10n.t(.protocolTitle))
                                    .font(.system(size: 11, weight: .heavy))
                                    .kerning(1.5)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                CopyButton(text: proto.text, label: L10n.t(.copy))
                            }
                            ProtocolDocument(markdown: proto.text)
                        }
                    }
                }
                .padding(26)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 700, idealWidth: 760, minHeight: 540, idealHeight: 640)
    }

    private var allText: String {
        let texts = model.detailTexts(for: meeting)
        var parts: [String] = []
        if let t = texts.transcript { parts.append("ТРАНСКРИПТ\n\n\(t)") }
        for p in texts.protocols { parts.append("ПРОТОКОЛ\n\n\(p.text)") }
        return parts.joined(separator: "\n\n———\n\n")
    }
}

struct Chip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(Color.primary.opacity(0.07)))
    }
}

// MARK: - Озвучка ответов: нейроголос Piper (если установлен), иначе системный say. Прерывается кнопкой.

@MainActor
final class Speaker: ObservableObject {
    @Published var isSpeaking = false
    private var procs: [Process] = []
    /// Номер текущей озвучки: сброс флага разрешён только её владельцу
    /// (защита от гонки «ответ закончился, а флаг не сбросился»).
    private var generation = 0

    static let piperBin = NSHomeDirectory() + "/.stenograf/tts/bin/piper"
    static let piperModel = NSHomeDirectory() + "/.stenograf/voices/ru_RU-dmitri-medium.onnx"
    static var piperAvailable: Bool {
        FileManager.default.fileExists(atPath: piperBin) && FileManager.default.fileExists(atPath: piperModel)
    }

    private static func fallbackVoice() -> String {
        if let configured = (try? AppConfig.load())?.ttsVoice, !configured.isEmpty { return configured }
        switch L10n.language {
        case .ru: return "Milena" // единственный русский на чистой системе; добавляются в настройках macOS
        case .en: return "Samantha"
        case .es: return "Monica"
        }
    }

    func speak(_ text: String) {
        stop()
        generation += 1
        let gen = generation
        // страховка: озвучка физически не может длиться дольше 3 минут
        DispatchQueue.main.asyncAfter(deadline: .now() + 180) { [weak self] in
            if self?.generation == gen {
                self?.isSpeaking = false
                self?.procs = []
            }
        }
        let clean = text
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "|", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let chunk = String(clean.prefix(1500))

        if Speaker.piperAvailable {
            let wav = FileManager.default.temporaryDirectory
                .appendingPathComponent("stenograf-tts-\(UUID().uuidString).wav").path
            let piper = Process()
            piper.executableURL = URL(fileURLWithPath: Speaker.piperBin)
            piper.arguments = ["--model", Speaker.piperModel, "--output_file", wav]
            let stdin = Pipe()
            piper.standardInput = stdin
            do { try piper.run() } catch { return }
            stdin.fileHandleForWriting.write((chunk + "\n").data(using: .utf8)!)
            stdin.fileHandleForWriting.closeFile()
            procs = [piper]
            isSpeaking = true
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                piper.waitUntilExit()
                guard piper.terminationStatus == 0, FileManager.default.fileExists(atPath: wav) else {
                    Task { @MainActor in
                        if self?.generation == gen { self?.isSpeaking = false; self?.procs = [] }
                    }
                    return
                }
                let player = Process()
                player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
                player.arguments = [wav]
                Task { @MainActor in if self?.generation == gen { self?.procs = [player] } }
                try? player.run()
                player.waitUntilExit()
                try? FileManager.default.removeItem(atPath: wav)
                Task { @MainActor in
                    if self?.generation == gen {
                        self?.isSpeaking = false
                        self?.procs = []
                    }
                }
            }
        } else {
            let say = Process()
            say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            say.arguments = ["-v", Speaker.fallbackVoice(), chunk]
            do { try say.run() } catch { return }
            procs = [say]
            isSpeaking = true
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                say.waitUntilExit()
                Task { @MainActor in
                    if self?.generation == gen {
                        self?.isSpeaking = false
                        self?.procs = []
                    }
                }
            }
        }
    }

    func stop() {
        generation += 1 // все отложенные сбросы прошлой озвучки теряют силу
        procs.forEach { if $0.isRunning { $0.terminate() } }
        procs = []
        isSpeaking = false
    }
}

// MARK: - Вопрос по встречам (голосом или текстом)

@MainActor
final class QuestionModel: ObservableObject {
    enum Phase: Equatable {
        case idle, recording, recognizing, thinking
        case done(question: String)
        case failed(String)
    }
    @Published var phase: Phase = .idle
    @Published var answer: String = ""
    @Published var sources: [String] = []
    @Published var typedQuestion: String = ""
    @Published var speakAnswers = true
    let speaker = Speaker()

    private let recorder = AudioRecorder()
    private let store = MeetingStore.default
    private var wavURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("stenograf-question-\(UUID().uuidString).wav")

    var statusText: String {
        switch phase {
        case .idle: ""
        case .recording: L10n.t(.listening)
        case .recognizing: L10n.t(.recognizing)
        case .thinking: L10n.t(.thinking)
        case .done(let q): q
        case .failed(let e): e
        }
    }

    func toggleRecording() {
        if phase == .recording {
            recorder.stop()
            phase = .recognizing
            let wav = wavURL
            Task.detached {
                do {
                    let cfg = try AppConfig.load()
                    let result = try WhisperCLI(whisper: cfg.whisper).transcribe(audioFile: wav.path)
                    try? FileManager.default.removeItem(at: wav)
                    let question = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    await MainActor.run {
                        guard !question.isEmpty else {
                            self.phase = .failed("Пустой вопрос — попробуй ещё раз")
                            return
                        }
                        self.typedQuestion = question
                        self.ask(question: question)
                    }
                } catch {
                    await MainActor.run { self.phase = .failed(error.localizedDescription) }
                }
            }
        } else {
            answer = ""
            sources = []
            do {
                try recorder.start(to: wavURL.path)
                phase = .recording
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func askFromTyped() {
        let q = typedQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        ask(question: q)
    }

    private func ask(question: String) {
        phase = .thinking
        let store = self.store
        Task.detached {
            do {
                let cfg = try AppConfig.load()
                let (brainName, brainCfg) = try cfg.brain(named: nil)
                let gathered = AnswerEngine.gatherContext(question: question, store: store)
                let brain = BrainFactory.make(brainCfg)
                let answer = try await brain.complete(
                    system: AnswerEngine.systemPrompt(hasContext: !gathered.context.isEmpty),
                    user: AnswerEngine.userMessage(question: question, context: gathered.context)
                )
                await MainActor.run {
                    self.answer = answer
                    self.sources = gathered.usedTitles
                    self.phase = .done(question: question)
                    if self.speakAnswers {
                        self.speaker.speak(answer)
                    }
                    _ = brainName
                }
            } catch {
                await MainActor.run { self.phase = .failed(error.localizedDescription) }
            }
        }
    }
}

struct QuestionSheet: View {
    @StateObject private var model = QuestionModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "text.bubble.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(LinearGradient(colors: [Color.stenoRed, .orange], startPoint: .top, endPoint: .bottom))
                Text(L10n.t(.askTitle))
                    .font(.system(size: 13, weight: .heavy))
                    .kerning(1.2)
                Spacer()
                if model.speaker.isSpeaking {
                    Button {
                        model.speaker.stop()
                    } label: {
                        Label("Стоп", systemImage: "stop.circle.fill")
                            .font(.callout.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(Color.stenoRed))
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    model.speakAnswers.toggle()
                } label: {
                    Image(systemName: model.speakAnswers ? "speaker.wave.2.fill" : "speaker.slash")
                        .foregroundStyle(model.speakAnswers ? Color.stenoRed : .secondary)
                }
                .buttonStyle(.borderless)
                .help("Озвучивать ответ")
                Button(L10n.t(.done)) { model.speaker.stop(); NSApp.keyWindow?.close() }
            }
            .padding(14)
            Divider()

            // Голосовой ввод
            VStack(spacing: 10) {
                Button {
                    model.toggleRecording()
                } label: {
                    ZStack {
                        Circle()
                            .fill(model.phase == .recording ? Color.stenoRed : Color.stenoInk)
                            .frame(width: 84, height: 84)
                            .shadow(color: model.phase == .recording ? .stenoRed.opacity(0.5) : .clear, radius: 24)
                        Image(systemName: model.phase == .recording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                Text(model.statusText.isEmpty ? "🎤" : model.statusText)
                    .font(.callout)
                    .foregroundStyle(model.phase == .recording ? Color.stenoRed : .secondary)
                    .multilineTextAlignment(.center)
                if case .thinking = model.phase {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.vertical, 18)

            // Текстовый ввод
            HStack(spacing: 8) {
                TextField(L10n.t(.askPlaceholder), text: $model.typedQuestion)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.askFromTyped() }
                Button(L10n.t(.askButton)) { model.askFromTyped() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.phase == .thinking || model.typedQuestion.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 16).padding(.bottom, 12)

            Divider()

            // Ответ
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !model.answer.isEmpty {
                        Text(L10n.t(.answerTitle))
                            .font(.system(size: 11, weight: .heavy))
                            .kerning(1.5)
                            .foregroundStyle(.secondary)
                        ProtocolDocument(markdown: model.answer)
                        if !model.sources.isEmpty {
                            Text(L10n.tf(.sourcesFmt, model.sources.joined(separator: ", ")))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if case .failed(let e) = model.phase {
                        Text(e).font(.callout).foregroundStyle(Color.stenoRed)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 560, idealWidth: 640, minHeight: 480, idealHeight: 560)
    }
}

struct CopyButton: View {
    let text: String
    let label: String

    @State private var copied = false
    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
        } label: {
            Label(copied ? "Скопировано" : label, systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.caption)
        }
        .buttonStyle(.bordered)
    }
}
