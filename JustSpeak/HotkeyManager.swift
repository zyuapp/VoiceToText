import ApplicationServices
import CoreGraphics
import Foundation

final class HotkeyManager {
    private enum ActivationState {
        case idle
        case recording
        case cancelled
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var permissionCheckTimer: Timer?
    private var shortcut: RecordingShortcut
    private var activationState = ActivationState.idle
    private var suppressedPrimaryKeyCode: CGKeyCode?
    private var shouldSuppressEscapeKeyUp = false
    private var hasPromptedForPermission = false
    private var isRunning = false
    private var isSuspended = false

    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?
    var onCancelRequested: (() -> Void)?
    var onPermissionGranted: (() -> Void)?

    init(shortcut: RecordingShortcut = .defaultShortcut) {
        self.shortcut = shortcut
    }

    func start() -> Bool {
        guard checkAccessibilityPermission() else {
            print("❌ Accessibility permission not granted - will retry when granted")
            startPermissionPolling()
            return false
        }

        return setupEventTap()
    }

    func stop() {
        cleanup()
        stopPermissionPolling()
    }

    func updateShortcut(_ shortcut: RecordingShortcut) {
        invalidateActiveShortcut()
        self.shortcut = shortcut
        print("Recording shortcut updated to \(shortcut.displayName)")
    }

    func setSuspended(_ isSuspended: Bool) {
        guard self.isSuspended != isSuspended else { return }

        if isSuspended {
            invalidateActiveShortcut()
        }

        self.isSuspended = isSuspended
    }

    func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    deinit {
        cleanup()
        stopPermissionPolling()
    }
}

private extension HotkeyManager {
    func checkAccessibilityPermission() -> Bool {
        let trusted = AXIsProcessTrusted()

        if !trusted && !hasPromptedForPermission {
            hasPromptedForPermission = true
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            return false
        }

        return trusted
    }

    func setupEventTap() -> Bool {
        let eventMask = (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.tapDisabledByTimeout.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }

                let manager = Unmanaged<HotkeyManager>
                    .fromOpaque(refcon)
                    .takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    manager.handleDisabledEventTap()
                    return Unmanaged.passUnretained(event)
                }

                if manager.handleEvent(type: type, event: event) {
                    return nil
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("❌ Failed to create event tap - check Accessibility permissions")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        isRunning = true
        print("✅ Hotkey manager started successfully (\(shortcut.displayName))")
        return true
    }

    func handleDisabledEventTap() {
        print("⚠️ Event tap was disabled by macOS; re-enabling")
        invalidateActiveShortcut()

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    func handleEvent(type: CGEventType, event: CGEvent) -> Bool {
        guard !isSuspended else { return false }

        switch type {
        case .flagsChanged:
            return handleFlagsChanged(event)
        case .keyDown:
            return handleKeyDown(event)
        case .keyUp:
            return handleKeyUp(event)
        default:
            return false
        }
    }

    func handleFlagsChanged(_ event: CGEvent) -> Bool {
        if shortcut.kind == .modifierOnly {
            handleModifierShortcut(event)
        } else {
            stopCombinationWhenModifiersAreReleased(event.flags)
        }

        return false
    }

    func handleModifierShortcut(_ event: CGEvent) {
        let keyCode = CGKeyCode(
            event.getIntegerValueField(.keyboardEventKeycode)
        )
        guard keyCode == shortcut.keyCode else { return }

        let isPressed = RecordingShortcut.isModifierPressed(
            keyCode: keyCode,
            eventFlags: event.flags
        )

        switch (activationState, isPressed) {
        case (.idle, true):
            beginRecording()
        case (.recording, false):
            finishRecording()
        case (.cancelled, false):
            activationState = .idle
        default:
            break
        }
    }

    func stopCombinationWhenModifiersAreReleased(_ flags: CGEventFlags) {
        guard activationState == .recording,
              !shortcut.matches(modifiers: flags) else {
            return
        }

        finishRecording()
    }

    func handleKeyDown(_ event: CGEvent) -> Bool {
        let keyCode = CGKeyCode(
            event.getIntegerValueField(.keyboardEventKeycode)
        )

        if keyCode == RecordingShortcut.escapeKeyCode && activationState == .recording {
            cancelRecording()
            shouldSuppressEscapeKeyUp = true
            return true
        }

        guard shortcut.kind != .modifierOnly, keyCode == shortcut.keyCode else {
            return false
        }

        if suppressedPrimaryKeyCode == keyCode {
            return true
        }

        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        guard !isRepeat,
              activationState == .idle,
              shortcut.matches(modifiers: event.flags) else {
            return false
        }

        suppressedPrimaryKeyCode = keyCode
        beginRecording()
        return true
    }

    func handleKeyUp(_ event: CGEvent) -> Bool {
        let keyCode = CGKeyCode(
            event.getIntegerValueField(.keyboardEventKeycode)
        )

        if keyCode == RecordingShortcut.escapeKeyCode && shouldSuppressEscapeKeyUp {
            shouldSuppressEscapeKeyUp = false
            return true
        }

        guard keyCode == suppressedPrimaryKeyCode else { return false }

        suppressedPrimaryKeyCode = nil

        switch activationState {
        case .recording:
            finishRecording()
        case .cancelled:
            activationState = .idle
        case .idle:
            break
        }

        return true
    }

    func beginRecording() {
        activationState = .recording
        print("▶ \(shortcut.displayName) DOWN - starting recording")

        DispatchQueue.main.async { [weak self] in
            self?.onKeyDown?()
        }
    }

    func finishRecording() {
        activationState = .idle
        print("■ \(shortcut.displayName) UP - stopping recording")

        DispatchQueue.main.async { [weak self] in
            self?.onKeyUp?()
        }
    }

    func cancelRecording() {
        activationState = .cancelled
        print("⎋ Escape pressed while recording - cancelling")

        DispatchQueue.main.async { [weak self] in
            self?.onCancelRequested?()
        }
    }

    func cancelActiveRecordingIfNeeded() {
        guard activationState == .recording else { return }
        cancelRecording()
    }

    func invalidateActiveShortcut() {
        cancelActiveRecordingIfNeeded()
        resetActivationState()
    }

    func resetActivationState() {
        activationState = .idle
        suppressedPrimaryKeyCode = nil
        shouldSuppressEscapeKeyUp = false
    }

    func cleanup() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }

        resetActivationState()
        isRunning = false
        print("Hotkey manager stopped")
    }

    func startPermissionPolling() {
        stopPermissionPolling()

        print("🔄 Polling for Accessibility permission (every 2 seconds)...")
        permissionCheckTimer = Timer.scheduledTimer(
            withTimeInterval: 2.0,
            repeats: true
        ) { [weak self] _ in
            self?.checkAndStartIfPermissionGranted()
        }
    }

    func stopPermissionPolling() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
    }

    @objc func checkAndStartIfPermissionGranted() {
        guard !isRunning, AXIsProcessTrusted() else { return }

        print("✅ Accessibility permission granted! Starting hotkey manager...")
        stopPermissionPolling()

        if setupEventTap() {
            onPermissionGranted?()
        }
    }
}
