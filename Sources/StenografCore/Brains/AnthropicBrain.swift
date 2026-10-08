import Foundation

/// Anthropic-совместимый /v1/messages: Anthropic API, GLM Coding Plan (см. README).
public struct AnthropicBrain: BrainProvider {
    let config: BrainConfig
    let urlSession: URLSession

    public init(config: BrainConfig, urlSession: URLSession = .shared) {
        self.config = config
        self.urlSession = urlSession
    }

    struct requestBody: Codable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]
        struct Message: Codable { let role: String; let content: String }
    }

    struct responseBody: Codable {
        struct Block: Codable { let type: String; let text: String? }
        let content: [Block]
        let error: APIError?
        struct APIError: Codable { let message: String? }
    }

    public func complete(system: String, user: String) async throws -> String {
        guard let url = URL(string: config.baseURL.trimmingCharacters(in: .whitespaces).appending("/v1/messages")) else {
            throw StenografError.badBrainResponse("некорректный baseURL: \(config.baseURL)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if let key = config.apiKey, !key.isEmpty {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
        }
        request.httpBody = try JSONEncoder().encode(
            requestBody(
                model: config.model,
                max_tokens: config.maxTokens ?? 4096,
                system: system,
                messages: [.init(role: "user", content: user)]
            )
        )
        let (data, httpResponse) = try await urlSession.data(for: request)
        let status = (httpResponse as? HTTPURLResponse)?.statusCode ?? 0
        let decoded = try? JSONDecoder().decode(responseBody.self, from: data)
        if status != 200 {
            throw StenografError.badBrainResponse("HTTP \(status): \(decoded?.error?.message ?? String(data: data.prefix(300), encoding: .utf8) ?? "?")")
        }
        let text = decoded?.content.compactMap(\.text).joined(separator: "\n") ?? ""
        guard !text.isEmpty else {
            throw StenografError.badBrainResponse("пустой ответ (HTTP \(status))")
        }
        return text
    }
}
