import AppKit
import Combine
import CoreGraphics
import SwiftUI

struct ShortcutSettingsView: View {
    @ObservedObject var store: RecordingShortcutStore
    @ObservedObject var captureController: ShortcutCaptureController

    init(
        store: RecordingShortcutStore,
        captureController: ShortcutCaptureController
    ) {
        self.store = store
        self.captureController = captureController
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Recording Shortcut")
                    .font(.title2.weight(.semibold))

                Text("Hold the shortcut to record, then release it to transcribe and paste.")
                    .foregroundStyle(.secondary)
            }

            shortcutField

            message
                .frame(minHeight: 34, alignment: .topLeading)

            HStack {
                Button("Restore Default") {
                    captureController.restoreDefault()
                }
                .disabled(
                    store.shortcut == .defaultShortcut && !captureController.isCapturing
                )

                Spacer()
            }
        }
        .padding(24)
        .frame(width: 420)
        .onDisappear {
            captureController.cancelCapture()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didResignActiveNotification
            )
        ) { _ in
            captureController.cancelCapture()
        }
    }

    private var shortcutField: some View {
        Button {
            if captureController.isCapturing {
                captureController.cancelCapture()
            } else {
                captureController.beginCapture()
            }
        } label: {
            HStack {
                Image(systemName: "keyboard")
                    .foregroundStyle(.secondary)

                Text(
                    captureController.isCapturing
                        ? "Press shortcut…"
                        : store.shortcut.displayName
                )
                    .font(.system(.body, design: .rounded, weight: .medium))

                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    captureController.isCapturing
                        ? Color.accentColor
                        : Color.secondary.opacity(0.25),
                    lineWidth: captureController.isCapturing ? 2 : 1
                )
        }
        .accessibilityLabel("Recording shortcut")
        .accessibilityValue(
            captureController.isCapturing
                ? "Waiting for shortcut"
                : store.shortcut.displayName
        )
    }

    @ViewBuilder
    private var message: some View {
        if let errorMessage = captureController.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
        } else if captureController.isCapturing {
            Text("Press a key combination, or release one modifier to use it alone. Escape cancels; Delete restores the default.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            Text("Click the field to change the shortcut.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

@MainActor
final class ShortcutCaptureController: ObservableObject {
    @Published private(set) var errorMessage: String?
    @Published private(set) var isCapturing = false

    private let store: RecordingShortcutStore
    private var localMonitor: Any?
    private var activeModifierKeyCodes = Set<CGKeyCode>()
    private var modifierSequence = Set<CGKeyCode>()
    private var attemptedNonModifier = false

    init(store: RecordingShortcutStore) {
        self.store = store
    }

    func beginCapture() {
        guard !isCapturing else { return }

        resetPendingKeys()
        errorMessage = nil
        isCapturing = true
        installEventMonitor()
    }

    func cancelCapture() {
        guard isCapturing else { return }

        errorMessage = nil
        finishCapture()
    }

    func restoreDefault() {
        store.restoreDefault()
        errorMessage = nil

        if isCapturing {
            finishCapture()
        }
    }
}

@MainActor
private extension ShortcutCaptureController {
    enum KeyCode {
        static let unsupportedModifiers: Set<CGKeyCode> = [57, 63]
    }

    func installEventMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .flagsChanged]
        ) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyDown:
            handleKeyDown(event)
        case .flagsChanged:
            handleFlagsChanged(event)
        default:
            break
        }

        return nil
    }

    func handleKeyDown(_ event: NSEvent) {
        guard !event.isARepeat else { return }

        let keyCode = event.keyCode
        if keyCode == RecordingShortcut.escapeKeyCode {
            cancelCapture()
            return
        }

        if RecordingShortcut.deleteKeyCodes.contains(keyCode) {
            restoreDefault()
            return
        }

        attemptedNonModifier = true
        let modifiers = eventFlags(for: event)
            .intersection(RecordingShortcut.supportedModifierFlags)
        let functionKeyLabel = functionKeyLabel(for: event.specialKey)

        if let validationMessage = RecordingShortcut.validationMessage(
            keyCode: keyCode,
            modifiers: modifiers,
            allowsUnmodifiedKey: functionKeyLabel != nil
        ) {
            errorMessage = validationMessage
            if modifiers.isEmpty {
                attemptedNonModifier = false
            }
            return
        }

        accept(
            .key(
                keyCode: keyCode,
                modifiers: modifiers,
                keyLabel: functionKeyLabel ?? keyLabel(for: event),
                isFunctionKey: functionKeyLabel != nil
            )
        )
    }

    func handleFlagsChanged(_ event: NSEvent) {
        let keyCode = event.keyCode

        if KeyCode.unsupportedModifiers.contains(keyCode) {
            errorMessage = "Caps Lock and Fn/Globe cannot be used as recording shortcuts."
            return
        }

        guard RecordingShortcut.isModifierKey(keyCode) else { return }

        let isPressed = RecordingShortcut.isModifierPressed(
            keyCode: keyCode,
            eventFlags: eventFlags(for: event)
        )

        if isPressed {
            if activeModifierKeyCodes.isEmpty {
                errorMessage = nil
            }
            activeModifierKeyCodes.insert(keyCode)
            modifierSequence.insert(keyCode)
            return
        }

        activeModifierKeyCodes.remove(keyCode)
        guard activeModifierKeyCodes.isEmpty else { return }

        if !attemptedNonModifier,
           modifierSequence.count == 1,
           let modifierKeyCode = modifierSequence.first {
            accept(.modifierOnly(keyCode: modifierKeyCode))
            return
        }

        if !attemptedNonModifier && modifierSequence.count > 1 {
            errorMessage = "Use one modifier alone, or add a non-modifier key."
        }

        resetPendingKeys()
    }

    func accept(_ shortcut: RecordingShortcut) {
        store.setShortcut(shortcut)
        errorMessage = nil
        finishCapture()
    }

    func finishCapture() {
        removeEventMonitor()
        resetPendingKeys()
        isCapturing = false
    }

    func removeEventMonitor() {
        guard let localMonitor else { return }
        NSEvent.removeMonitor(localMonitor)
        self.localMonitor = nil
    }

    func resetPendingKeys() {
        activeModifierKeyCodes.removeAll()
        modifierSequence.removeAll()
        attemptedNonModifier = false
    }

    func eventFlags(for event: NSEvent) -> CGEventFlags {
        if let cgEvent = event.cgEvent {
            return cgEvent.flags
        }

        return CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
    }

    func functionKeyLabel(for specialKey: NSEvent.SpecialKey?) -> String? {
        guard let specialKey else { return nil }

        let functionKeyIndex = specialKey.rawValue - NSEvent.SpecialKey.f1.rawValue
        let maximumIndex = NSEvent.SpecialKey.f35.rawValue - NSEvent.SpecialKey.f1.rawValue
        guard (0...maximumIndex).contains(functionKeyIndex) else { return nil }

        return "F\(functionKeyIndex + 1)"
    }

    func keyLabel(for event: NSEvent) -> String {
        if let specialKey = event.specialKey,
           let label = navigationKeyLabel(for: specialKey) {
            return label
        }

        switch event.keyCode {
        case 36:
            return "Return"
        case 48:
            return "Tab"
        case 49:
            return "Space"
        case 71:
            return "Clear"
        case 76:
            return "Enter"
        default:
            break
        }

        guard let character = event.charactersIgnoringModifiers?.first,
              !character.isWhitespace else {
            return "Key \(event.keyCode)"
        }

        return String(character).uppercased()
    }

    func navigationKeyLabel(for specialKey: NSEvent.SpecialKey) -> String? {
        if specialKey == .leftArrow { return "←" }
        if specialKey == .rightArrow { return "→" }
        if specialKey == .downArrow { return "↓" }
        if specialKey == .upArrow { return "↑" }
        if specialKey == .home { return "Home" }
        if specialKey == .end { return "End" }
        if specialKey == .pageUp { return "Page Up" }
        if specialKey == .pageDown { return "Page Down" }
        return nil
    }
}
