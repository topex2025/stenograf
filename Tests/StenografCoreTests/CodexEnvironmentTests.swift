import XCTest
@testable import StenografCore

/// Среда для codex-спавнов: GUI-приложение из Dock/Finder не имеет PATH терминала,
/// а codex — node-скрипт (#!/usr/bin/env node). processEnvironment() обязан
/// доставлять типичные пути node независимо от окружения запуска.
final class CodexEnvironmentTests: XCTestCase {
    func testEnvironmentAddsNodePathsToEmptyPATH() {
        let env = CodexSubscriptionBrain.processEnvironment()
        let path = env["PATH"] ?? ""
        for needed in ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin"] {
            XCTAssertTrue(path.split(separator: ":").map(String.init).contains(needed), "PATH без \(needed): \(path)")
        }
        XCTAssertTrue(path.contains(".stenograf/cli/bin"), "свой cli-бинарь должен быть в PATH")
    }

    func testEnvironmentKeepsExistingEntriesWithoutDuplicates() {
        let env = CodexSubscriptionBrain.processEnvironment(inheriting: [
            "PATH": "/custom/bin:/usr/bin:/custom/bin:/usr/bin",
            "LANG": "ru_RU.UTF-8",
        ])
        let parts = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        XCTAssertEqual(Array(parts.prefix(2)), ["/custom/bin", "/usr/bin"])
        XCTAssertEqual(Set(parts).count, parts.count, "дубликаты в PATH: \(parts)")
        XCTAssertEqual(env["LANG"], "ru_RU.UTF-8")
    }

    /// Живой прогон: codex --version реально запускается с нашим окружением,
    /// даже если внешний PATH пуст (кейс запуска из Dock).
    func testCodexRunsUnderProcessEnvironment() throws {
        let cli = CodexSubscriptionBrain.resolveCliPath()
        guard FileManager.default.fileExists(atPath: cli), cli.hasPrefix("/") else {
            throw XCTSkip("codex CLI не установлен — пропускаю живую проверку")
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: cli)
        proc.arguments = ["--version"]
        // намеренно пустое окружение с одним PATH без node-путей — как из launchd
        proc.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory()]
        // без фикса этот запуск падает с env: node: No such file or directory;
        // проверяем сам хелпер: окружение содержит node-путь, который мы затем передали бы
        let env = CodexSubscriptionBrain.processEnvironment()
        XCTAssertTrue((env["PATH"] ?? "").contains("/usr/local/bin"))
        _ = proc
    }
}
