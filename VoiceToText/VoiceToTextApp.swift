//
//  VoiceToTextApp.swift
//  VoiceToText
//
//  Created by Zhuocheng Yu on 11/10/25.
//

import SwiftUI
import AppKit
import UserNotifications

@main
struct VoiceToTextApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let audioRecorder = AudioRecorder()
    private let hotkeyManager = HotkeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestNotificationPermission()
        setupStatusItem()
        setupMenus()
        setupHotkeyManager()
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Voice to Text")
            button.image?.isTemplate = true
        }
    }

    private func setupMenus() {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Test Recording (5s)", action: #selector(testRecording), keyEquivalent: "t"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc private func testRecording() {
        guard audioRecorder.startRecording() else {
            showNotification(title: "Recording Failed", body: "Could not start recording")
            return
        }

        scheduleRecordingStop()
    }

    private func scheduleRecordingStop() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.stopAndNotify()
        }
    }

    private func stopAndNotify() {
        guard let recordingURL = audioRecorder.stopRecording() else {
            showNotification(title: "Recording Failed", body: "Could not save recording")
            return
        }

        let message = "Recording saved to: \(recordingURL.path)"
        print(message)
        showNotification(title: "Recording Complete", body: message)
    }

    private func showNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Notification error: \(error)")
            }
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func setupHotkeyManager() {
        hotkeyManager.onKeyDown = { [weak self] in
            self?.handleHotkeyDown()
        }

        hotkeyManager.onKeyUp = { [weak self] in
            self?.handleHotkeyUp()
        }

        if hotkeyManager.start() {
            print("Hotkey listener started (Right Command)")
        } else {
            showNotification(
                title: "Permission Required",
                body: "Please grant Accessibility permission in System Settings > Privacy & Security"
            )
        }
    }

    private func handleHotkeyDown() {
        updateStatusIcon(recording: true)

        guard audioRecorder.startRecording() else {
            showNotification(title: "Recording Failed", body: "Could not start recording")
            updateStatusIcon(recording: false)
            return
        }

        print("Recording started via hotkey")
    }

    private func handleHotkeyUp() {
        updateStatusIcon(recording: false)

        guard let recordingURL = audioRecorder.stopRecording() else {
            showNotification(title: "Recording Failed", body: "Could not save recording")
            return
        }

        let message = "Recording saved to: \(recordingURL.path)"
        print(message)
        showNotification(title: "Recording Complete", body: message)
    }

    private func updateStatusIcon(recording: Bool) {
        guard let button = statusItem?.button else { return }

        if recording {
            button.image = NSImage(systemSymbolName: "mic.fill.badge.plus", accessibilityDescription: "Recording")
            button.image?.isTemplate = true
        } else {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Voice to Text")
            button.image?.isTemplate = true
        }
    }
}
