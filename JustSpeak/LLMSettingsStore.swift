import Foundation

enum PostProcessingTone: String, CaseIterable, Identifiable {
    case cleanOnly
    case professional
    case casual
    case concise

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cleanOnly: return "Clean Only"
        case .professional: return "Professional"
        case .casual: return "Casual"
        case .concise: return "Concise"
        }
    }

    var systemPrompt: String {
        let toneInstruction: String = switch self {
        case .cleanOnly: "Keep meaning unchanged."
        case .professional: "Rewrite the text in a polished, formal tone suitable for emails and documents."
        case .casual: "Rewrite the text in a relaxed, conversational tone suitable for chats."
        case .concise: "Trim filler words and tighten the text while preserving meaning."
        }
        return "You are a dictation post-processor. \(toneInstruction) Fix punctuation, capitalization, and minor ASR artifacts. Return only the final text."
    }
}

struct LLMConfiguration {
    let isPostProcessingEnabled: Bool
    let baseURL: String
    let model: String

    var normalizedBaseURL: String {
        baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedModel: String {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasEndpointConfiguration: Bool {
        !normalizedBaseURL.isEmpty && !normalizedModel.isEmpty
    }
}

class LLMSettingsStore {
    static let shared = LLMSettingsStore()

    enum Keys {
        static let isPostProcessingEnabled = "llmPostProcessingEnabled"
        static let baseURL = "llmBaseURL"
        static let model = "llmModel"
        static let tone = "llmTone"
    }

    private let defaults = UserDefaults.standard

    var isPostProcessingEnabled: Bool {
        get { defaults.bool(forKey: Keys.isPostProcessingEnabled) }
        set { defaults.set(newValue, forKey: Keys.isPostProcessingEnabled) }
    }

    var baseURL: String {
        get { defaults.string(forKey: Keys.baseURL) ?? "" }
        set { defaults.set(newValue, forKey: Keys.baseURL) }
    }

    var model: String {
        get { defaults.string(forKey: Keys.model) ?? "" }
        set { defaults.set(newValue, forKey: Keys.model) }
    }

    var tone: PostProcessingTone {
        get {
            guard let raw = defaults.string(forKey: Keys.tone),
                  let value = PostProcessingTone(rawValue: raw) else {
                return .cleanOnly
            }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.tone) }
    }

    var configuration: LLMConfiguration {
        LLMConfiguration(
            isPostProcessingEnabled: isPostProcessingEnabled,
            baseURL: baseURL,
            model: model
        )
    }
}
