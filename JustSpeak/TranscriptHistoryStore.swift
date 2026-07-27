import Foundation

struct TranscriptHistoryEntry: Codable {
    let text: String
    let createdAt: Date
}

final class TranscriptHistoryStore {
    private static let storageKey = "transcriptHistory"
    private static let maximumEntryCount = 10

    private(set) var entries: [TranscriptHistoryEntry]

    init() {
        entries = Self.loadEntries()
    }

    func add(_ text: String) {
        entries.insert(
            TranscriptHistoryEntry(text: text, createdAt: Date()),
            at: 0
        )
        entries = Array(entries.prefix(Self.maximumEntryCount))
        saveEntries()
    }

    func clear() {
        entries.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }

    private static func loadEntries() -> [TranscriptHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([TranscriptHistoryEntry].self, from: data)
        } catch {
            print("Failed to load transcript history: \(error)")
            return []
        }
    }

    private func saveEntries() {
        do {
            let data = try JSONEncoder().encode(entries)
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        } catch {
            print("Failed to save transcript history: \(error)")
        }
    }
}
