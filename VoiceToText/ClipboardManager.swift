import Foundation
import AppKit
import CoreGraphics

class ClipboardManager {
    static let shared = ClipboardManager()

    private init() {}

    func copyToClipboard(_ text: String) {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func pasteFromClipboard() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let cmdVDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true)
            cmdVDown?.flags = .maskCommand
            cmdVDown?.post(tap: .cghidEventTap)

            let cmdVUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false)
            cmdVUp?.flags = .maskCommand
            cmdVUp?.post(tap: .cghidEventTap)
        }
    }

    func copyAndPaste(_ text: String) {
        copyToClipboard(text)
        pasteFromClipboard()
    }
}
