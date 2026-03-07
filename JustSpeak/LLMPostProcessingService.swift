import Foundation

enum LLMPostProcessingError: Error {
    case missingConfiguration
    case invalidBaseURL
    case missingAPIKey
    case requestFailed(String)
    case invalidResponse
    case serverError(String)
    case emptyResult
}

extension LLMPostProcessingError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Set Base URL and model in Settings to use LLM post-processing."
        case .invalidBaseURL:
            return "Base URL is invalid. Update it in Settings."
        case .missingAPIKey:
            return "API key is missing. Add it in Settings."
        case .requestFailed(let message):
            return "LLM request failed: \(message)"
        case .invalidResponse:
            return "LLM response was invalid."
        case .serverError(let message):
            return "LLM server returned an error: \(message)"
        case .emptyResult:
            return "LLM returned an empty result."
        }
    }
}

class LLMPostProcessingService {
    static let shared = LLMPostProcessingService()

    private let settingsStore: LLMSettingsStore
    private let keychainStore: KeychainStore
    private let timeout: TimeInterval = 10

    init(
        settingsStore: LLMSettingsStore = .shared,
        keychainStore: KeychainStore = .shared
    ) {
        self.settingsStore = settingsStore
        self.keychainStore = keychainStore
    }

    func postProcess(_ text: String) async throws -> String {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            return text
        }

        let configuration = settingsStore.configuration
        guard configuration.hasEndpointConfiguration else {
            throw LLMPostProcessingError.missingConfiguration
        }

        guard let baseURL = URL(string: configuration.normalizedBaseURL) else {
            throw LLMPostProcessingError.invalidBaseURL
        }

        guard let apiKey = try keychainStore.loadAPIKey(), !apiKey.isEmpty else {
            throw LLMPostProcessingError.missingAPIKey
        }

        let endpoint = chatCompletionEndpoint(from: baseURL)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            ChatCompletionRequest(
                model: configuration.normalizedModel,
                messages: [
                    ChatCompletionMessage(role: "system", content: systemPrompt),
                    ChatCompletionMessage(role: "user", content: input)
                ],
                temperature: 0.2,
                stream: false
            )
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try validate(response: response, data: data)

            let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            let rawOutput = decoded.choices.first?.message.content ?? ""
            let output = rawOutput.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            guard !output.isEmpty else {
                throw LLMPostProcessingError.emptyResult
            }

            return output
        } catch let error as LLMPostProcessingError {
            throw error
        } catch {
            throw LLMPostProcessingError.requestFailed(error.localizedDescription)
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMPostProcessingError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw LLMPostProcessingError.serverError(parseServerError(data: data))
        }
    }

    private func parseServerError(data: Data) -> String {
        if let errorEnvelope = try? JSONDecoder().decode(ServerErrorEnvelope.self, from: data) {
            return errorEnvelope.error.message
        }

        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text
        }

        return "Unknown server error"
    }

    private var systemPrompt: String {
        settingsStore.tone.systemPrompt
    }

    private func chatCompletionEndpoint(from baseURL: URL) -> URL {
        var endpoint = baseURL
        let normalizedPath = baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if normalizedPath == "v1" {
            endpoint.append(path: "chat/completions")
        } else {
            endpoint.append(path: "v1/chat/completions")
        }

        return endpoint
    }
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatCompletionMessage]
    let temperature: Double
    let stream: Bool
}

private struct ChatCompletionMessage: Codable {
    let role: String
    let content: String
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        let message: ChatCompletionMessage
    }

    let choices: [Choice]
}

private struct ServerErrorEnvelope: Decodable {
    struct ErrorPayload: Decodable {
        let message: String
    }

    let error: ErrorPayload
}
