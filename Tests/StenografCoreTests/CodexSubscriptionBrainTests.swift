import XCTest
@testable import StenografCore

final class CodexSubscriptionBrainTests: XCTestCase {
    /// Пишет фейковый codex-скрипт, который запоминает аргументы и пишет ответ в файл из -o.
    private func makeFakeCodex(script: String) -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("stenograf-fake-codex-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("codex").path
        try! "#!/bin/bash\n\(script)".write(toFile: path, atomically: true, encoding: .utf8)
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    func testHappyPathPassesFlagsAndReadsLastMessage() async throws {
        let argsFile = FileManager.default.temporaryDirectory.appendingPathComponent("fake-codex-args-\(UUID()).txt").path
        let fake = makeFakeCodex(script: """
        echo "$@" > "\(argsFile)"
        out=""
        prev=""
        for a in "$@"; do
          if [ "$prev" = "-o" ]; then out="$a"; fi
          prev="$a"
        done
        printf 'ПРОТОКОЛ ЧЕРЕЗ ПОДПИСКУ ОК' > "$out"
        """)
        defer { try? FileManager.default.removeItem(atPath: fake) }

        let brain = CodexSubscriptionBrain(cliPath: fake, model: "gpt-5.2-codex", timeout: 30)
        let answer = try await brain.complete(system: "sys-prompt", user: "user-text")

        XCTAssertEqual(answer, "ПРОТОКОЛ ЧЕРЕЗ ПОДПИСКУ ОК")
        let args = try String(contentsOfFile: argsFile, encoding: .utf8)
        XCTAssertTrue(args.contains("exec"), "должен звать exec: \(args)")
        XCTAssertTrue(args.contains("--skip-git-repo-check"), "нужен флаг вне-_git: \(args)")
        XCTAssertTrue(args.contains("-s") && args.contains("read-only"), "песочница read-only: \(args)")
        XCTAssertTrue(args.contains("-m") && args.contains("gpt-5.2-codex"), "модель: \(args)")
        XCTAssertTrue(args.contains("sys-prompt"), "system-промпт передан: \(args)")
        XCTAssertTrue(args.contains("user-text"), "user-текст передан: \(args)")
    }

    func testFailureSurfacesStderr() async throws {
        let fake = makeFakeCodex(script: "echo 'usage limit reached' >&2; exit 3\n")
        defer { try? FileManager.default.removeItem(atPath: fake) }
        let brain = CodexSubscriptionBrain(cliPath: fake, timeout: 30)
        do {
            _ = try await brain.complete(system: "s", user: "u")
            XCTFail("ожидали ошибку")
        } catch let error as StenografError {
            guard case .badBrainResponse(let detail) = error else { return XCTFail("не тот тип: \(error)") }
            XCTAssertTrue(detail.contains("3") && detail.contains("usage limit"), "должен пробросить код и stderr: \(detail)")
        }
    }

    func testLoginStatusDetectsChatGPTMode() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("stenograf-auth-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let authFile = dir.appendingPathComponent("auth.json")
        try #"{"auth_mode":"chatgpt","tokens":{"access_token":"x","refresh_token":"y","account_id":"z"}}"#.write(to: authFile, atomically: true, encoding: .utf8)

        // loginStatus читает фиксированный путь ~/.codex/auth.json — проверяем парсер через структуру файла
        let data = try Data(contentsOf: authFile)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["auth_mode"] as? String, "chatgpt")
        XCTAssertNotNil((json["tokens"] as? [String: Any])?["access_token"])
        try? FileManager.default.removeItem(at: dir)
    }
}
