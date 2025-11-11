import Foundation
import CoreGraphics
import ApplicationServices

class HotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var permissionCheckTimer: Timer?

    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?
    var onCancelRequested: (() -> Void)?
    var onPermissionGranted: (() -> Void)?

    private let targetKeyCode: CGKeyCode = 54
    private let escapeKeyCode: CGKeyCode = 53
    private var isTargetKeyPressed = false
    private var hasPromptedForPermission = false
    private var isRunning = false

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

    deinit {
        cleanup()
        stopPermissionPolling()
    }
}

extension HotkeyManager {
    private func checkAccessibilityPermission() -> Bool {
        let trusted = AXIsProcessTrusted()

        if !trusted && !hasPromptedForPermission {
            hasPromptedForPermission = true
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            return false
        }

        return trusted
    }

    private func setupEventTap() -> Bool {
        let eventMask = (1 << CGEventType.flagsChanged.rawValue) |
                       (1 << CGEventType.keyDown.rawValue) |
                       (1 << CGEventType.tapDisabledByTimeout.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }

                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    print("⚠️ Event tap was disabled by system (type: \(type.rawValue)), re-enabling...")
                    if let tap = manager.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                        print("✓ Event tap re-enabled successfully")
                    }
                    return Unmanaged.passUnretained(event)
                }

                manager.handleEvent(type: type, event: event)

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
        print("✅ Hotkey manager started successfully (Right Command key)")
        print("📝 Listening for flagsChanged events...")
        return true
    }

    private func handleEvent(type: CGEventType, event: CGEvent) {
        if type == .flagsChanged {
            handleFlagsChanged(event: event)
        } else if type == .keyDown {
            handleKeyDown(event: event)
        }
    }

    private func handleFlagsChanged(event: CGEvent) {
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        print("DEBUG: FlagsChanged event detected")
        print("  Keycode: \(keycode) (target: \(targetKeyCode))")
        print("  Flags raw: \(flags.rawValue)")
        print("  Command: \(flags.contains(.maskCommand))")
        print("  Option: \(flags.contains(.maskAlternate))")
        print("  Control: \(flags.contains(.maskControl))")
        print("  Shift: \(flags.contains(.maskShift))")

        guard keycode == targetKeyCode else { return }

        let commandPressed = flags.contains(.maskCommand)
        print("✓ Right Command key detected - pressed: \(commandPressed)")

        if commandPressed && !isTargetKeyPressed {
            isTargetKeyPressed = true
            print("▶ Right Command DOWN - starting recording")
            DispatchQueue.main.async { [weak self] in
                self?.onKeyDown?()
            }
        } else if !commandPressed && isTargetKeyPressed {
            isTargetKeyPressed = false
            print("■ Right Command UP - stopping recording")
            DispatchQueue.main.async { [weak self] in
                self?.onKeyUp?()
            }
        }
    }

    private func handleKeyDown(event: CGEvent) {
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)

        guard keycode == escapeKeyCode && isTargetKeyPressed else { return }

        print("⎋ Escape key pressed while recording - cancelling")
        DispatchQueue.main.async { [weak self] in
            self?.onCancelRequested?()
        }
    }

    private func cleanup() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }

        isRunning = false
        print("Hotkey manager stopped")
    }

    private func startPermissionPolling() {
        stopPermissionPolling()

        print("🔄 Polling for Accessibility permission (every 2 seconds)...")
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkAndStartIfPermissionGranted()
        }
    }

    private func stopPermissionPolling() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
    }

    @objc private func checkAndStartIfPermissionGranted() {
        guard !isRunning else { return }

        if AXIsProcessTrusted() {
            print("✅ Accessibility permission granted! Starting hotkey manager...")
            stopPermissionPolling()

            if setupEventTap() {
                onPermissionGranted?()
            }
        }
    }
}
