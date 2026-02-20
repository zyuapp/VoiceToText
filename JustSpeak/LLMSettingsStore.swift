import Foundation

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

    var configuration: LLMConfiguration {
        LLMConfiguration(
            isPostProcessingEnabled: isPostProcessingEnabled,
            baseURL: baseURL,
            model: model
        )
    }
}
