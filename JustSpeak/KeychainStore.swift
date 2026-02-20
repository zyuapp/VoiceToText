import Foundation
import Security

enum KeychainStoreError: Error {
    case emptyValue
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case invalidData
    case deleteFailed(OSStatus)
}

extension KeychainStoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .emptyValue:
            return "API key cannot be empty."
        case .saveFailed(let status):
            return "Failed to save API key (code \(status))."
        case .loadFailed(let status):
            return "Failed to read API key (code \(status))."
        case .invalidData:
            return "Stored API key data is invalid."
        case .deleteFailed(let status):
            return "Failed to delete API key (code \(status))."
        }
    }
}

class KeychainStore {
    static let shared = KeychainStore()

    private let service = "com.zyu.just-speak"
    private let account = "ollamaCloudAPIKey"

    func saveAPIKey(_ apiKey: String) throws {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw KeychainStoreError.emptyValue
        }

        guard let data = trimmedKey.data(using: .utf8) else {
            throw KeychainStoreError.invalidData
        }

        let baseQuery = keychainQuery()
        SecItemDelete(baseQuery as CFDictionary)

        var attributes = baseQuery
        attributes[kSecValueData as String] = data

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainStoreError.saveFailed(status)
        }
    }

    func loadAPIKey() throws -> String? {
        var query = keychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainStoreError.loadFailed(status)
        }

        guard let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw KeychainStoreError.invalidData
        }

        return key
    }

    func deleteAPIKey() throws {
        let status = SecItemDelete(keychainQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.deleteFailed(status)
        }
    }

    private func keychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
