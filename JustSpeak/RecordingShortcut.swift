import Combine
import CoreGraphics
import Foundation

struct RecordingShortcut: Codable, Equatable {
    enum Kind: String, Codable {
        case modifierOnly
        case key
        case functionKey
    }

    let keyCode: CGKeyCode
    let modifierFlagsRawValue: UInt64
    let keyLabel: String
    let kind: Kind

    static let defaultShortcut = modifierOnly(keyCode: 54)
    static let escapeKeyCode: CGKeyCode = 53
    static let deleteKeyCodes: Set<CGKeyCode> = [51, 117]
    static let supportedModifierFlags: CGEventFlags = [
        .maskControl,
        .maskAlternate,
        .maskShift,
        .maskCommand
    ]

    var modifierFlags: CGEventFlags {
        CGEventFlags(rawValue: modifierFlagsRawValue)
            .intersection(Self.supportedModifierFlags)
    }

    var displayName: String {
        switch kind {
        case .modifierOnly:
            return Self.modifierDescriptor(for: keyCode)?.displayName ?? keyLabel
        case .key, .functionKey:
            return Self.modifierSymbols(for: modifierFlags) + keyLabel
        }
    }

    var isSupported: Bool {
        switch kind {
        case .modifierOnly:
            return Self.modifierDescriptor(for: keyCode) != nil && modifierFlags.isEmpty
        case .key:
            return Self.validationMessage(
                keyCode: keyCode,
                modifiers: modifierFlags,
                allowsUnmodifiedKey: false
            ) == nil && !keyLabel.isEmpty
        case .functionKey:
            return keyCode != Self.escapeKeyCode
                && modifierFlags.isEmpty
                && !keyLabel.isEmpty
        }
    }

    func matches(modifiers eventFlags: CGEventFlags) -> Bool {
        eventFlags.intersection(Self.supportedModifierFlags) == modifierFlags
    }

    static func modifierOnly(keyCode: CGKeyCode) -> RecordingShortcut {
        let label = modifierDescriptor(for: keyCode)?.displayName ?? "Modifier"
        return RecordingShortcut(
            keyCode: keyCode,
            modifierFlagsRawValue: 0,
            keyLabel: label,
            kind: .modifierOnly
        )
    }

    static func key(
        keyCode: CGKeyCode,
        modifiers: CGEventFlags,
        keyLabel: String,
        isFunctionKey: Bool
    ) -> RecordingShortcut {
        let sanitizedModifiers = modifiers.intersection(supportedModifierFlags)
        let kind: Kind = if sanitizedModifiers.isEmpty && isFunctionKey {
            .functionKey
        } else {
            .key
        }

        return RecordingShortcut(
            keyCode: keyCode,
            modifierFlagsRawValue: sanitizedModifiers.rawValue,
            keyLabel: keyLabel,
            kind: kind
        )
    }

    static func isModifierKey(_ keyCode: CGKeyCode) -> Bool {
        modifierDescriptor(for: keyCode) != nil
    }

    static func isModifierPressed(
        keyCode: CGKeyCode,
        eventFlags: CGEventFlags
    ) -> Bool {
        guard let descriptor = modifierDescriptor(for: keyCode) else { return false }

        let deviceFlags = eventFlags.rawValue & allDeviceModifierMasks
        if deviceFlags != 0 {
            return eventFlags.rawValue & descriptor.deviceFlagMask != 0
        }

        return eventFlags.contains(descriptor.aggregateFlag)
    }

    static func validationMessage(
        keyCode: CGKeyCode,
        modifiers: CGEventFlags,
        allowsUnmodifiedKey: Bool
    ) -> String? {
        let sanitizedModifiers = modifiers.intersection(supportedModifierFlags)

        if keyCode == escapeKeyCode {
            return "Escape is reserved for cancelling a recording."
        }

        if sanitizedModifiers.isEmpty && !allowsUnmodifiedKey {
            return "Add a modifier, or choose a function key."
        }

        return conflictMessage(keyCode: keyCode, modifiers: sanitizedModifiers)
    }
}

@MainActor
final class RecordingShortcutStore: ObservableObject {
    @Published private(set) var shortcut: RecordingShortcut

    private static let defaultsKey = "recordingShortcut"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        shortcut = Self.loadShortcut(from: defaults)
    }

    func setShortcut(_ shortcut: RecordingShortcut) {
        guard shortcut.isSupported else { return }

        self.shortcut = shortcut
        persist(shortcut)
    }

    func restoreDefault() {
        setShortcut(.defaultShortcut)
    }
}

private extension RecordingShortcut {
    struct ModifierDescriptor {
        let keyCode: CGKeyCode
        let displayName: String
        let aggregateFlag: CGEventFlags
        let deviceFlagMask: UInt64
    }

    enum KeyCode {
        static let v: CGKeyCode = 9
        static let q: CGKeyCode = 12
        static let tab: CGKeyCode = 48
        static let space: CGKeyCode = 49
    }

    static let modifierDescriptors: [ModifierDescriptor] = [
        ModifierDescriptor(
            keyCode: 59,
            displayName: "Left ⌃",
            aggregateFlag: .maskControl,
            deviceFlagMask: 0x00000001
        ),
        ModifierDescriptor(
            keyCode: 62,
            displayName: "Right ⌃",
            aggregateFlag: .maskControl,
            deviceFlagMask: 0x00002000
        ),
        ModifierDescriptor(
            keyCode: 58,
            displayName: "Left ⌥",
            aggregateFlag: .maskAlternate,
            deviceFlagMask: 0x00000020
        ),
        ModifierDescriptor(
            keyCode: 61,
            displayName: "Right ⌥",
            aggregateFlag: .maskAlternate,
            deviceFlagMask: 0x00000040
        ),
        ModifierDescriptor(
            keyCode: 56,
            displayName: "Left ⇧",
            aggregateFlag: .maskShift,
            deviceFlagMask: 0x00000002
        ),
        ModifierDescriptor(
            keyCode: 60,
            displayName: "Right ⇧",
            aggregateFlag: .maskShift,
            deviceFlagMask: 0x00000004
        ),
        ModifierDescriptor(
            keyCode: 55,
            displayName: "Left ⌘",
            aggregateFlag: .maskCommand,
            deviceFlagMask: 0x00000008
        ),
        ModifierDescriptor(
            keyCode: 54,
            displayName: "Right ⌘",
            aggregateFlag: .maskCommand,
            deviceFlagMask: 0x00000010
        )
    ]

    static let allDeviceModifierMasks = modifierDescriptors.reduce(UInt64.zero) {
        $0 | $1.deviceFlagMask
    }

    static func modifierDescriptor(for keyCode: CGKeyCode) -> ModifierDescriptor? {
        modifierDescriptors.first { $0.keyCode == keyCode }
    }

    static func modifierSymbols(for flags: CGEventFlags) -> String {
        var symbols = ""

        if flags.contains(.maskControl) {
            symbols += "⌃"
        }
        if flags.contains(.maskAlternate) {
            symbols += "⌥"
        }
        if flags.contains(.maskShift) {
            symbols += "⇧"
        }
        if flags.contains(.maskCommand) {
            symbols += "⌘"
        }

        return symbols
    }

    static func conflictMessage(
        keyCode: CGKeyCode,
        modifiers: CGEventFlags
    ) -> String? {
        let command: CGEventFlags = .maskCommand
        let control: CGEventFlags = .maskControl

        if keyCode == KeyCode.space && modifiers == command {
            return "⌘ Space is used by Spotlight."
        }
        if keyCode == KeyCode.tab && modifiers == command {
            return "⌘ Tab is used by the app switcher."
        }
        if keyCode == KeyCode.space && modifiers == control {
            return "⌃ Space is commonly used to switch input sources."
        }
        if keyCode == KeyCode.q && modifiers == command {
            return "⌘ Q is used to quit the current app."
        }
        if keyCode == KeyCode.v && modifiers == command {
            return "⌘ V is required for pasting transcriptions."
        }
        if keyCode == KeyCode.q && modifiers == [control, command] {
            return "⌃⌘Q is used to lock the screen."
        }

        return nil
    }
}

private extension RecordingShortcutStore {
    static func loadShortcut(from defaults: UserDefaults) -> RecordingShortcut {
        guard let data = defaults.data(forKey: defaultsKey),
              let shortcut = try? JSONDecoder().decode(RecordingShortcut.self, from: data),
              shortcut.isSupported else {
            return .defaultShortcut
        }

        return shortcut
    }

    func persist(_ shortcut: RecordingShortcut) {
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
