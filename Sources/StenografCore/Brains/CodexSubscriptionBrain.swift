import Darwin
import Foundation

/// Мозг через ПОДПИСКУ ChatGPT: гоняет официальный Codex CLI (`codex exec`),
/// который сам разбирается с OAuth-токенами из ~/.codex/auth.json, их обновлением
/// и лимитами подписки (Plus/Pro). Никаких API-ключей не нужно.
/// Паттерн переиспользования подписочного логина — тот же, что у OpenClaw.
public struct CodexSubscriptionBrain: BrainProvider {
    let cliPath: String
    let model: String?
    let timeout: TimeInterval

    public init(cliPath: String, model: String? = nil, timeout: TimeInterval = 600) {
        self.cliPath = cliPath
        self.model = (model ?? "").isEmpty ? nil : model
        self.timeout = timeout
    }

    /// Ищет codex в типичных местах (GUI-приложение не наследует PATH из шелла).
    public static func resolveCliPath(configured: String? = nil) -> String {
        let home = NSHomeDirectory()
        let candidates = [
            NSString(string: configured ?? "").expandingTildeInPath,
            "\(home)/.stenograf/cli/bin/codex", // наша пользовательская установка npm
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex",
        ] + processEnvironment()["PATH", default: ""].split(separator: ":").map { "\($0)/codex" }
        for path in candidates where path.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return "codex"
    }

    /// Есть ли подписочный логин ChatGPT (~/.codex/auth.json в режиме chatgpt).
    /// authPath параметр — для тестов состояний; по умолчанию живой файл.
    public static func loginStatus(authPath: String? = nil) -> (loggedIn: Bool, detail: String) {
        let path = authPath ?? NSString(string: "~/.codex/auth.json").expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return (false, "нет входа ChatGPT — нужна команда stenograf login")
        }
        let mode = json["auth_mode"] as? String ?? "?"
        let hasTokens = (json["tokens"] as? [String: Any])?["access_token"] != nil
        if mode == "chatgpt" && hasTokens {
            return (true, "вход через подписку ChatGPT активен")
        }
        if let key = json["OPENAI_API_KEY"] as? String, !key.isEmpty {
            return (true, "найден API-ключ в ~/.codex/auth.json (режим api-key)")
        }
        return (false, "auth_mode=\(mode), токенов нет — нужен stenograf login")
    }

    /// Окружение для запуска codex: GUI-приложения из Dock/Finder не наследуют
    /// PATH терминала, а codex — node-скрипт (#!/usr/bin/env node). Дописываем
    /// типичные пути node сами, откуда бы приложение ни запустили.
    public static func processEnvironment() -> [String: String] {
        processEnvironment(inheriting: ProcessInfo.processInfo.environment)
    }

    static func processEnvironment(inheriting environment: [String: String]) -> [String: String] {
        var env = environment
        let required = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/usr/bin",
            "/bin",
            NSHomeDirectory() + "/.stenograf/cli/bin",
        ]
        let inherited = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        let path = (inherited + required).filter { seen.insert($0).inserted }
        env["PATH"] = path.joined(separator: ":")
        return env
    }

    public func complete(system: String, user: String) async throws -> String {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: cliPath) else {
            throw StenografError.missingFile("\(cliPath) (brew install --cask codex)")
        }

        let outDir = fm.temporaryDirectory
            .appendingPathComponent("stenograf-codex-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: outDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: outDir) }
        let outFile = outDir.appendingPathComponent("last-message.txt")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        var args = ["exec", "--skip-git-repo-check", "-s", "read-only", "-o", outFile.path]
        if let model {
            args += ["-m", model]
        }
        process.arguments = args + ["-"]
        process.environment = Self.processEnvironment()
        process.currentDirectoryURL = outDir

        // Files avoid pipe backpressure and the OS limit on individual arguments.
        let input = outDir.appendingPathComponent("prompt.txt")
        let diagnostics = outDir.appendingPathComponent("stderr.txt")
        try "\(system)\n\n===\n\n\(user)".write(to: input, atomically: true, encoding: .utf8)
        try Data().write(to: diagnostics)
        let stdin = try FileHandle(forReadingFrom: input)
        let stderr = try FileHandle(forWritingTo: diagnostics)
        defer { try? stdin.close(); try? stderr.close() }
        process.standardInput = stdin
        process.standardError = stderr
        process.standardOutput = FileHandle.nullDevice

        let deadline = timeout
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result {
                    let exited = DispatchSemaphore(value: 0)
                    process.terminationHandler = { _ in exited.signal() }
                    try process.run()
                    guard exited.wait(timeout: .now() + deadline) == .success else {
                        if process.isRunning { process.terminate() }
                        if exited.wait(timeout: .now() + 2) == .timedOut && process.isRunning {
                            kill(process.processIdentifier, SIGKILL)
                        }
                        process.waitUntilExit()
                        throw StenografError.badBrainResponse("превышен таймаут \(Int(deadline)) c — попробуй ещё раз")
                    }
                })
            }
        }

        func errorText(limit: Int) -> String {
            guard let handle = try? FileHandle(forReadingFrom: diagnostics) else { return "" }
            defer { try? handle.close() }
            let data = (try? handle.read(upToCount: limit)) ?? Data()
            return String(decoding: data, as: UTF8.self)
        }

        guard process.terminationStatus == 0 else {
            let errText = errorText(limit: 8192)
            // лимит подписки — самая частая «не-ошибка»: переводим на человеческий
            if errText.lowercased().contains("usage limit") {
                let until = errText.range(of: #"try again at[^.]*"#, options: .regularExpression)
                    .map { String(errText[$0]) } ?? "позже"
                throw StenografError.badBrainResponse(
                    "лимит подписки ChatGPT исчерпан — выжимка/протокол пройдут после сброса квоты (\(until)). Аудио и транскрипт сохранены, ничего не потеряно."
                )
            }
            throw StenografError.badBrainResponse("codex exec упал (код \(process.terminationStatus)): \(errText)")
        }
        guard let text = try? String(contentsOf: outFile, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw StenografError.badBrainResponse("codex exec не дал ответ: \(errorText(limit: 500))")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension BrainProvider where Self == CodexSubscriptionBrain {}
