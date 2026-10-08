import Foundation

/// Локальный Ollama (/api/chat). Ключ не нужен, данные остаются на машине.
public struct OllamaBrain: BrainProvider {
    let config: BrainConfig
    let urlSession: URLSession

    public init(config: BrainConfig, urlSession: URLSession = .shared) {
        self.config = config
        self.urlSession = urlSession
    }

    struct requestBody: Codable {
        struct Message: Codable { let role: String; let content: String }
        let model: String
        let messages: [Message]
        let stream: Bool
    }

    struct responseBody: Codable {
        struct Message: Codable { let content: String? }
        let message: Message?
        let error: String?
    }

    public func complete(system: String, user: String) async throws -> String {
        guard let url = URL(string: config.baseURL.trimmingCharacters(in: .whitespaces).appending("/api/chat")) else {
            throw StenografError.badBrainResponse("некорректный baseURL: \(config.baseURL)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            requestBody(
                model: config.model,
                messages: [
                    .init(role: "system", content: system),
                    .init(role: "user", content: user),
                ],
                stream: false
            )
        )
        let (data, httpResponse) = try await urlSession.data(for: request)
        let status = (httpResponse as? HTTPURLResponse)?.statusCode ?? 0
        let decoded = try? JSONDecoder().decode(responseBody.self, from: data)
        if status != 200 {
            throw StenografError.badBrainResponse("HTTP \(status): \(decoded?.error ?? String(data: data.prefix(300), encoding: .utf8) ?? "?")")
        }
        guard let text = decoded?.message?.content, !text.isEmpty else {
            throw StenografError.badBrainResponse("пустой ответ (HTTP \(status))")
        }
        return text
    }
}
