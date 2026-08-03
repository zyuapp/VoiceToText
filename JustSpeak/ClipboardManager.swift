import Foundation
import AppKit
import CoreGraphics

class ClipboardManager {
    static let shared = ClipboardManager()

    private struct ActiveInsertion {
        let id: UUID
        let previousContents: [NSPasteboardItem]
        let changeCount: Int
    }

    private struct PasteboardSnapshot {
        let items: [NSPasteboardItem]
        let changeCount: Int
    }

    private var pendingTranscripts: [String] = []
    private var activeInsertion: ActiveInsertion?

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
        guard pasteboard.changeCount == previousContents.changeCount else {
            pendingTranscripts.removeAll()
            return
        }
        let transcriptChangeCount = pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            restorePasteboard(
                previousContents.items,
                ifUnchangedSince: transcriptChangeCount
            )
            pendingTranscripts.removeFirst()
            startNextInsertionIfNeeded()
            return
        }
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
                self.completeInsertion(id: id)
                return
            }

            guard self.postPasteShortcut() else {
                self.completeInsertion(id: id)
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.completeInsertion(id: id)
            }
        }
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
