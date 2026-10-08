import XCTest
@testable import StenografCore

/// Все состояния входа новичка/юзера — на временных файлах, живой ~/.codex не трогаем.
final class LoginStatusTests: XCTestCase {
    private func tmpAuth(_ content: String?) -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("stenograf-login-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("auth.json").path
        if let content { try! content.write(toFile: path, atomically: true, encoding: .utf8) }
        return path
    }

    func testFreshUserNoFile() {
        // новичок: файла нет
        let status = CodexSubscriptionBrain.loginStatus(authPath: tmpAuth(nil))
        XCTAssertFalse(status.loggedIn)
        XCTAssertTrue(status.detail.contains("stenograf login"), "подсказка о входе: \(status.detail)")
    }

    func testChatGPTSubscriptionMode() {
        // вошедший по подписке
        let json = #"{"auth_mode":"chatgpt","tokens":{"access_token":"x","refresh_token":"y","account_id":"z"},"last_refresh":"2026-10-08"}"#
        let status = CodexSubscriptionBrain.loginStatus(authPath: tmpAuth(json))
        XCTAssertTrue(status.loggedIn)
        XCTAssertTrue(status.detail.contains("активен"))
    }

    func testApiKeyMode() {
        let json = #"{"OPENAI_API_KEY":"sk-..."}"#
        let status = CodexSubscriptionBrain.loginStatus(authPath: tmpAuth(json))
        XCTAssertTrue(status.loggedIn)
        XCTAssertTrue(status.detail.contains("api-key"))
    }

    func testBrokenEmptyTokens() {
        // файл есть, толку нет
        let json = #"{"auth_mode":"chatgpt","tokens":{}}"#
        let status = CodexSubscriptionBrain.loginStatus(authPath: tmpAuth(json))
        XCTAssertFalse(status.loggedIn)
    }

    func testGarbageFile() {
        let status = CodexSubscriptionBrain.loginStatus(authPath: tmpAuth("не json вообще"))
        XCTAssertFalse(status.loggedIn)
    }
}
