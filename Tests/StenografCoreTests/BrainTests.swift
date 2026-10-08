import XCTest
@testable import StenografCore

/// Mock-транспорт: перехватывает запрос, отдаёт заготовленный ответ.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            let bufSize = 16384
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
            while stream.hasBytesAvailable {
                let n = stream.read(buf, maxLength: bufSize)
                if n <= 0 { break }
                data.append(buf, count: n)
            }
            buf.deallocate()
            stream.close()
            Self.lastBody = data
        } else {
            Self.lastBody = request.httpBody
        }
        do {
            let (response, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: cfg)
    }

    static func ok(_ url: URL, _ json: String) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
    }
}

final class BrainTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        MockURLProtocol.lastRequest = nil
        MockURLProtocol.lastBody = nil
        super.tearDown()
    }

    func testOpenAICompatibleRequestAndParsing() async throws {
        let config = BrainConfig(kind: .openai, baseURL: "https://api.openai.com/v1", apiKey: "sk-test", model: "gpt-test")
        MockURLProtocol.handler = { req in
            MockURLProtocol.ok(req.url!, #"{"choices":[{"message":{"role":"assistant","content":"ПРОТОКОЛ ОК"}}]}"#)
        }
        let brain = OpenAICompatibleBrain(config: config, urlSession: MockURLProtocol.makeSession())
        let answer = try await brain.complete(system: "sys", user: "usr")

        XCTAssertEqual(answer, "ПРОТОКОЛ ОК")
        let req = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(req.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")

        let body = try XCTUnwrap(MockURLProtocol.lastBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "gpt-test")
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages.first?["role"], "system")
        XCTAssertEqual(messages.first?["content"], "sys")
    }

    func testAnthropicRequestAndParsing() async throws {
        let config = BrainConfig(kind: .anthropic, baseURL: "https://open.bigmodel.cn/api/anthropic", apiKey: "glm-key", model: "glm-test")
        MockURLProtocol.handler = { req in
            MockURLProtocol.ok(req.url!, #"{"content":[{"type":"text","text":"РЕЗЮМЕ ОК"}]}"#)
        }
        let brain = AnthropicBrain(config: config, urlSession: MockURLProtocol.makeSession())
        let answer = try await brain.complete(system: "sys", user: "usr")

        XCTAssertEqual(answer, "РЕЗЮМЕ ОК")
        let req = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(req.url?.absoluteString, "https://open.bigmodel.cn/api/anthropic/v1/messages")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-api-key"), "glm-key")
        XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")

        let body = try XCTUnwrap(MockURLProtocol.lastBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "glm-test")
        XCTAssertEqual(json["system"] as? String, "sys")
    }

    func testOllamaRequestAndParsing() async throws {
        let config = BrainConfig(kind: .ollama, baseURL: "http://localhost:11434", model: "qwen3:14b")
        MockURLProtocol.handler = { req in
            MockURLProtocol.ok(req.url!, #"{"message":{"content":"ЛОКАЛЬНО ОК"}}"#)
        }
        let brain = OllamaBrain(config: config, urlSession: MockURLProtocol.makeSession())
        let answer = try await brain.complete(system: "sys", user: "usr")

        XCTAssertEqual(answer, "ЛОКАЛЬНО ОК")
        let req = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(req.url?.absoluteString, "http://localhost:11434/api/chat")
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))
    }

    func testHTTPErrorSurfacesMessage() async throws {
        let config = BrainConfig(kind: .openai, baseURL: "https://api.openai.com/v1", apiKey: "k", model: "m")
        MockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
             Data(#"{"error":{"message":"bad key"}}"#.utf8))
        }
        let brain = OpenAICompatibleBrain(config: config, urlSession: MockURLProtocol.makeSession())
        do {
            _ = try await brain.complete(system: "s", user: "u")
            XCTFail("ожидали ошибку")
        } catch let error as StenografError {
            guard case .badBrainResponse(let detail) = error else { return XCTFail("не тот тип: \(error)") }
            XCTAssertTrue(detail.contains("401"), "в сообщении должен быть код: \(detail)")
        }
    }

    func testFactorySelectsKind() {
        XCTAssertTrue(BrainFactory.make(BrainConfig(kind: .openai, baseURL: "https://x", model: "m")) is OpenAICompatibleBrain)
        XCTAssertTrue(BrainFactory.make(BrainConfig(kind: .anthropic, baseURL: "https://x", model: "m")) is AnthropicBrain)
        XCTAssertTrue(BrainFactory.make(BrainConfig(kind: .ollama, baseURL: "https://x", model: "m")) is OllamaBrain)
    }
}
