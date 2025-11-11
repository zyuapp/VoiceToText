import Foundation
import CoreGraphics
import ApplicationServices

class HotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    private let targetKeyCode: CGKeyCode = 54
    private var isTargetKeyPressed = false

    func start() -> Bool {
        guard checkAccessibilityPermission() else {
            print("Accessibility permission not granted")
            return false
        }

        return setupEventTap()
    }

    func stop() {
        cleanup()
    }

    deinit {
        cleanup()
    }
}

extension HotkeyManager {
    private func checkAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func setupEventTap() -> Bool {
        let eventMask = (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }

                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                manager.handleEvent(type: type, event: event)

                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("Failed to create event tap")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("Hotkey manager started successfully")
        return true
    }

    private func handleEvent(type: CGEventType, event: CGEvent) {
        guard type == .flagsChanged else { return }

        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        print("FlagsChanged event - keycode: \(keycode), flags: \(flags.rawValue), command: \(flags.contains(.maskCommand))")

        guard keycode == targetKeyCode else { return }

        let commandPressed = flags.contains(.maskCommand)

        if commandPressed && !isTargetKeyPressed {
            isTargetKeyPressed = true
            print("Right Command pressed - starting recording")
            DispatchQueue.main.async { [weak self] in
                self?.onKeyDown?()
            }
        } else if !commandPressed && isTargetKeyPressed {
            isTargetKeyPressed = false
            print("Right Command released - stopping recording")
            DispatchQueue.main.async { [weak self] in
                self?.onKeyUp?()
            }
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

        print("Hotkey manager stopped")
    }
}
