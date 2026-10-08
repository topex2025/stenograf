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
            configured ?? "",
            "\(home)/.stenograf/cli/bin/codex", // наша пользовательская установка npm
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex",
        ].filter { !$0.isEmpty }
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return path
        }
        return "codex" // последний шанс: вдруг PATH всё же есть
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

    public func complete(system: String, user: String) async throws -> String {
        let fm = FileManager.default
        guard fm.fileExists(atPath: cliPath) || cliPath == "codex" else {
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
        args.append("\(system)\n\n===\n\n\(user)")
        process.arguments = args
        process.currentDirectoryURL = outDir
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        // codex exec бывает долгим (лимиты подписки, очереди) — таймаут обязателен.
        try await withTimeout(seconds: timeout) { [process] in
            try process.run()
            process.waitUntilExit()
        }

        guard process.terminationStatus == 0 else {
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData.prefix(1500), encoding: .utf8) ?? ""
            throw StenografError.badBrainResponse("codex exec упал (код \(process.terminationStatus)): \(errText)")
        }
        guard let text = try? String(contentsOf: outFile, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            throw StenografError.badBrainResponse("codex exec не дал ответ: \(String(data: errData.prefix(500), encoding: .utf8) ?? "?")")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension BrainProvider where Self == CodexSubscriptionBrain {}

/// Простой таймаут вокруг синхронного кода.
func withTimeout<T: Sendable>(seconds: TimeInterval, _ body: @escaping @Sendable () throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try body() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw StenografError.badBrainResponse("превышен таймаут \(Int(seconds)) c — попробуй ещё раз")
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
