import SwiftUI

struct LLMSettingsView: View {
    @AppStorage(LLMSettingsStore.Keys.isPostProcessingEnabled) private var isPostProcessingEnabled = false
    @AppStorage(LLMSettingsStore.Keys.tone) private var tone: String = PostProcessingTone.cleanOnly.rawValue
    @AppStorage(LLMSettingsStore.Keys.baseURL) private var baseURL = ""
    @AppStorage(LLMSettingsStore.Keys.model) private var model = ""

    @State private var apiKeyInput = ""
    @State private var hasStoredAPIKey = false
    @State private var statusMessage = "No API key saved in Keychain."

    private let keychainStore = KeychainStore.shared

    var body: some View {
        Form {
            Section("LLM Post-Processing") {
                Toggle("Enable post-processing", isOn: $isPostProcessingEnabled)
                Picker("Tone", selection: $tone) {
                    ForEach(PostProcessingTone.allCases) { t in
                        Text(t.displayName).tag(t.rawValue)
                    }
                }
                .disabled(!isPostProcessingEnabled)
                Text("When enabled, transcribed text is sent to your configured LLM endpoint before paste.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Endpoint") {
                TextField("Base URL", text: $baseURL)
                    .textFieldStyle(.roundedBorder)
                TextField("Model", text: $model)
                    .textFieldStyle(.roundedBorder)
            }

            Section("API Key") {
                SecureField("API Key", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Save API Key", action: saveAPIKey)
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Delete API Key", action: deleteAPIKey)
                        .disabled(!hasStoredAPIKey)
                }

                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 560)
        .onAppear(perform: loadAPIKeyState)
    }

    private func loadAPIKeyState() {
        do {
            let storedKey = try keychainStore.loadAPIKey()
            hasStoredAPIKey = storedKey != nil
            statusMessage = storedKey == nil
                ? "No API key saved in Keychain."
                : "API key is saved in Keychain."
        } catch {
            hasStoredAPIKey = false
            statusMessage = error.localizedDescription
        }
    }

    private func saveAPIKey() {
        do {
            try keychainStore.saveAPIKey(apiKeyInput)
            apiKeyInput = ""
            hasStoredAPIKey = true
            statusMessage = "API key saved in Keychain."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func deleteAPIKey() {
        do {
            try keychainStore.deleteAPIKey()
            hasStoredAPIKey = false
            statusMessage = "API key deleted from Keychain."
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

#Preview {
    LLMSettingsView()
}
