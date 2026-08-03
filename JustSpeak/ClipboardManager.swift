import Foundation
import AppKit
import CoreGraphics

class ClipboardManager {
    static let shared = ClipboardManager()

    private struct ActiveInsertion {
        let id: UUID
        let previousContents: [NSPasteboardItem]
        let changeCount: Int
        var pastePosted = false
    }

    private struct PasteboardSnapshot {
        let items: [NSPasteboardItem]
        let changeCount: Int
    }

    private var pendingTranscripts: [String] = []
    private var activeInsertion: ActiveInsertion?
    private var activeProvider: TranscriptPasteboardProvider?

    private init() {}

    func copyAndPaste(_ text: String) {
        guard !text.isEmpty else { return }

        pendingTranscripts.append(text)
        startNextInsertionIfNeeded()
    }

    private func startNextInsertionIfNeeded() {
        guard activeInsertion == nil,
              let text = pendingTranscripts.first else { return }

        let pasteboard = NSPasteboard.general
        guard let previousContents = copyPasteboardItems(from: pasteboard) else {
            pendingTranscripts.removeAll()
            return
        }
        let insertionID = UUID()
        let provider = TranscriptPasteboardProvider(text: text) { [weak self] in
            DispatchQueue.main.async {
                self?.handleDataRequest(id: insertionID)
            }
        }
        let item = NSPasteboardItem()
        guard item.setDataProvider(provider, forTypes: [.string]) else {
            pendingTranscripts.removeFirst()
            startNextInsertionIfNeeded()
            return
        }

        guard pasteboard.changeCount == previousContents.changeCount else {
            pendingTranscripts.removeAll()
            return
        }
        let transcriptChangeCount = pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            restorePasteboard(
                previousContents.items,
                ifUnchangedSince: transcriptChangeCount
            )
            pendingTranscripts.removeFirst()
            startNextInsertionIfNeeded()
            return
        }
        guard pasteboard.changeCount == transcriptChangeCount else {
            pendingTranscripts.removeAll()
            return
        }

        activeProvider = provider
        activeInsertion = ActiveInsertion(
            id: insertionID,
            previousContents: previousContents.items,
            changeCount: transcriptChangeCount
        )
        schedulePaste(id: insertionID)
    }

    private func schedulePaste(id: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self,
                  let insertion = self.activeInsertion,
                  insertion.id == id else { return }
            guard NSPasteboard.general.changeCount == insertion.changeCount else {
                self.retryInsertion(id: id)
                return
            }

            self.activeInsertion?.pastePosted = true
            guard self.postPasteShortcut() else {
                self.completeInsertion(id: id)
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.completeInsertion(id: id)
            }
        }
    }

    private func handleDataRequest(id: UUID) {
        guard let insertion = activeInsertion,
              insertion.id == id,
              insertion.pastePosted else { return }
        completeInsertion(id: id)
    }

    private func retryInsertion(id: UUID) {
        guard activeInsertion?.id == id else { return }

        activeInsertion = nil
        activeProvider = nil
        startNextInsertionIfNeeded()
    }

    private func completeInsertion(id: UUID) {
        guard let insertion = activeInsertion,
              insertion.id == id else { return }

        let stillOwnsPasteboard = NSPasteboard.general.changeCount == insertion.changeCount
        if stillOwnsPasteboard {
            restorePasteboard(
                insertion.previousContents,
                ifUnchangedSince: insertion.changeCount
            )
        }

        activeInsertion = nil
        activeProvider = nil
        pendingTranscripts.removeFirst()

        if stillOwnsPasteboard {
            startNextInsertionIfNeeded()
        } else {
            pendingTranscripts.removeAll()
        }
    }

    private func copyPasteboardItems(from pasteboard: NSPasteboard) -> PasteboardSnapshot? {
        let changeCount = pasteboard.changeCount
        let items = pasteboard.pasteboardItems ?? []
        var copies: [NSPasteboardItem] = []

        for item in items {
            let copy = NSPasteboardItem()

            for type in item.types {
                guard let data = item.data(forType: type),
                      copy.setData(data, forType: type) else { return nil }
            }

            copies.append(copy)
        }

        guard pasteboard.changeCount == changeCount else { return nil }
        return PasteboardSnapshot(items: copies, changeCount: changeCount)
    }

    private func postPasteShortcut() -> Bool {
        guard let cmdVDown = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0x09,
            keyDown: true
        ), let cmdVUp = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0x09,
            keyDown: false
        ) else {
            return false
        }

        cmdVDown.flags = .maskCommand
        cmdVDown.post(tap: .cghidEventTap)

        cmdVUp.flags = .maskCommand
        cmdVUp.post(tap: .cghidEventTap)
        return true
    }

    private func restorePasteboard(
        _ items: [NSPasteboardItem],
        ifUnchangedSince changeCount: Int
    ) {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount == changeCount else { return }

        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
}

private final class TranscriptPasteboardProvider: NSObject, NSPasteboardItemDataProvider {
    private let text: String
    private let completion: () -> Void
    private var isProvidingData = false

    init(text: String, completion: @escaping () -> Void) {
        self.text = text
        self.completion = completion
    }

    func pasteboard(
        _ pasteboard: NSPasteboard?,
        item: NSPasteboardItem,
        provideDataForType type: NSPasteboard.PasteboardType
    ) {
        isProvidingData = true
        item.setString(text, forType: type)
        isProvidingData = false
        completion()
    }

    func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {
        guard !isProvidingData else { return }
        completion()
    }
}
