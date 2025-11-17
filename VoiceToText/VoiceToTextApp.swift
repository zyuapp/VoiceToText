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
    private let transcriptionService = TranscriptionService.shared
    private let clipboardManager = ClipboardManager.shared
    private var recordingStartTime: Date?
    private var downloadProgressMenuItem: NSMenuItem?
    private var accessibilityMenuItem: NSMenuItem?
    private static let selectedDeviceKey = "selectedAudioInputDevice"

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestNotificationPermission()
        setupStatusItem()
        setupMenus()
        setupHotkeyManager()
        setupTranscriptionService()
        restoreSelectedDevice()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        updateAccessibilityMenuItem()
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

        accessibilityMenuItem = createAccessibilityMenuItem()
        menu.addItem(accessibilityMenuItem!)

        let audioInputItem = NSMenuItem(title: "Audio Input", action: nil, keyEquivalent: "")
        audioInputItem.submenu = createAudioInputSubmenu()
        menu.addItem(audioInputItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    private func createAudioInputSubmenu() -> NSMenu {
        let submenu = NSMenu()
        let devices = AudioRecorder.getAvailableInputDevices()
        let currentDeviceID = AudioRecorder.getCurrentInputDeviceID()
        let savedDeviceID = UserDefaults.standard.object(forKey: Self.selectedDeviceKey) as? UInt32

        let defaultItem = NSMenuItem(
            title: "System Default",
            action: #selector(selectAudioDevice(_:)),
            keyEquivalent: ""
        )
        defaultItem.tag = 0
        defaultItem.target = self
        defaultItem.state = savedDeviceID == nil ? .on : .off
        submenu.addItem(defaultItem)

        if !devices.isEmpty {
            submenu.addItem(NSMenuItem.separator())
        }

        for device in devices {
            let item = NSMenuItem(
                title: device.name,
                action: #selector(selectAudioDevice(_:)),
                keyEquivalent: ""
            )
            item.tag = Int(device.id)
            item.target = self

            let isSelected = if let savedID = savedDeviceID {
                device.id == savedID
            } else {
                device.id == currentDeviceID
            }

            item.state = isSelected ? .on : .off
            submenu.addItem(item)
        }

        return submenu
    }

    @objc private func selectAudioDevice(_ sender: NSMenuItem) {
        guard let menu = statusItem?.menu,
              let audioInputItem = menu.items.first(where: { $0.title == "Audio Input" }),
              let submenu = audioInputItem.submenu else { return }

        for item in submenu.items {
            item.state = .off
        }

        sender.state = .on

        if sender.tag == 0 {
            UserDefaults.standard.removeObject(forKey: Self.selectedDeviceKey)
            audioRecorder.setInputDevice(id: nil)
            print("Audio input set to system default")
        } else {
            let deviceID = UInt32(sender.tag)
            UserDefaults.standard.set(deviceID, forKey: Self.selectedDeviceKey)
            audioRecorder.setInputDevice(id: deviceID)
            print("Audio input set to: \(sender.title)")
        }
    }

    private func restoreSelectedDevice() {
        if let savedDeviceID = UserDefaults.standard.object(forKey: Self.selectedDeviceKey) as? UInt32 {
            audioRecorder.setInputDevice(id: savedDeviceID)
            print("Restored audio input device: \(savedDeviceID)")
        }
    }

    private func updateDownloadProgress(_ progress: Double) {
        guard let menu = statusItem?.menu else { return }

        let progressText = String(format: "Downloading model: %.1f%%", progress * 100)

        if let menuItem = downloadProgressMenuItem {
            menuItem.title = progressText
        } else {
            let menuItem = NSMenuItem(title: progressText, action: nil, keyEquivalent: "")
            menuItem.isEnabled = false
            menu.insertItem(menuItem, at: 0)
            downloadProgressMenuItem = menuItem
        }
    }

    private func removeDownloadProgress() {
        guard let menuItem = downloadProgressMenuItem else { return }
        statusItem?.menu?.removeItem(menuItem)
        downloadProgressMenuItem = nil
    }

    private func createAccessibilityMenuItem() -> NSMenuItem {
        let hasPermission = hotkeyManager.hasAccessibilityPermission()
        let title = hasPermission ? "Accessibility Permission ✓" : "Enable Accessibility Permission..."
        let menuItem = NSMenuItem(
            title: title,
            action: hasPermission ? nil : #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        menuItem.target = self
        menuItem.isEnabled = !hasPermission
        return menuItem
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func updateAccessibilityMenuItem() {
        guard let menuItem = accessibilityMenuItem else { return }

        let hasPermission = hotkeyManager.hasAccessibilityPermission()
        menuItem.title = hasPermission ? "Accessibility Permission ✓" : "Enable Accessibility Permission..."
        menuItem.action = hasPermission ? nil : #selector(openAccessibilitySettings)
        menuItem.isEnabled = !hasPermission
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

    private func setupTranscriptionService() {
        if transcriptionService.isModelDownloaded {
            do {
                try transcriptionService.initialize()
                print("Transcription service initialized")
            } catch {
                print("Failed to initialize transcription service: \(error)")
                showNotification(
                    title: "Transcription Unavailable",
                    body: "Failed to initialize Whisper model"
                )
            }
        } else {
            updateStatusIcon(downloading: true)
            showNotification(
                title: "Downloading Model",
                body: "First time setup: downloading Whisper model (~1.6GB)"
            )

            transcriptionService.downloadModelIfNeeded { [weak self] progress in
                print(String(format: "Download progress: %.1f%%", progress * 100))
                self?.updateDownloadProgress(progress)
            } completion: { [weak self] result in
                self?.updateStatusIcon(downloading: false)
                self?.removeDownloadProgress()

                switch result {
                case .success:
                    print("Model downloaded and initialized successfully")
                    self?.showNotification(
                        title: "Setup Complete",
                        body: "Whisper model ready for transcription"
                    )
                case .failure(let error):
                    print("Model download failed: \(error)")
                    self?.showNotification(
                        title: "Download Failed",
                        body: "Failed to download Whisper model: \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func setupHotkeyManager() {
        print("🎤 Setting up hotkey manager...")

        hotkeyManager.onKeyDown = { [weak self] in
            self?.handleHotkeyDown()
        }

        hotkeyManager.onKeyUp = { [weak self] in
            self?.handleHotkeyUp()
        }

        hotkeyManager.onCancelRequested = { [weak self] in
            self?.handleCancellation()
        }

        hotkeyManager.onPermissionGranted = { [weak self] in
            print("✅ Hotkey listener ready - Press Right Command to record")
            self?.updateAccessibilityMenuItem()
            self?.showNotification(
                title: "Voice Dictation Ready",
                body: "Hold Right Command (⌘) to record, press Escape to cancel"
            )
        }

        if hotkeyManager.start() {
            print("✅ Hotkey listener ready - Press Right Command to record")
            showNotification(
                title: "Voice Dictation Ready",
                body: "Hold Right Command (⌘) to record, press Escape to cancel"
            )
        } else {
            print("❌ Failed to start hotkey listener - waiting for permission")
            showNotification(
                title: "Permission Required",
                body: "Grant Accessibility permission in System Settings, then wait a moment - no restart needed!"
            )
        }
    }

    private func handleHotkeyDown() {
        recordingStartTime = Date()
        updateStatusIcon(recording: true)

        guard audioRecorder.startRecording() else {
            showNotification(title: "Recording Failed", body: "Could not start recording")
            updateStatusIcon(error: true)
            recordingStartTime = nil
            return
        }

        print("Recording started via hotkey")
    }

    private func handleHotkeyUp() {
        let startTime = recordingStartTime
        recordingStartTime = nil
        updateStatusIcon(recording: false)

        guard let recordingURL = audioRecorder.stopRecording() else {
            showNotification(title: "Recording Failed", body: "Could not save recording")
            updateStatusIcon(error: true)
            return
        }

        guard let startTime = startTime else {
            print("No recording start time recorded")
            return
        }

        let duration = Date().timeIntervalSince(startTime)
        print("Recording duration: \(String(format: "%.1f", duration)) seconds")

        guard duration >= 0.5 else {
            print("Recording too short (\(String(format: "%.1f", duration))s), ignoring")
            return
        }

        if duration > 60 {
            showNotification(
                title: "Recording Too Long",
                body: "Recording limited to 60 seconds. Processing first 60 seconds..."
            )
        }

        processRecording(url: recordingURL)
    }

    private func handleCancellation() {
        recordingStartTime = nil
        updateStatusIcon()
        audioRecorder.cancelRecording()
        print("Recording cancelled by user")
    }

    private func processRecording(url: URL) {
        guard transcriptionService.isReady else {
            showNotification(
                title: "Transcription Unavailable",
                body: "Whisper model not ready. Please wait for download to complete."
            )
            updateStatusIcon(error: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.updateStatusIcon()
            }
            return
        }

        updateStatusIcon(processing: true)
        print("Processing recording: \(url.path)")

        Task {
            do {
                let text = try await transcriptionService.transcribe(audioFile: url)

                await MainActor.run {
                    updateStatusIcon()
                    handleTranscriptionResult(text)
                    cleanupRecording(url)
                }
            } catch {
                await MainActor.run {
                    updateStatusIcon(error: true)
                    showNotification(
                        title: "Transcription Failed",
                        body: error.localizedDescription
                    )
                    print("Transcription error: \(error)")

                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        self?.updateStatusIcon()
                    }

                    cleanupRecording(url)
                }
            }
        }
    }

    private func handleTranscriptionResult(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            print("No speech detected")
            return
        }

        print("Transcription: \(trimmed)")
        clipboardManager.copyAndPaste(trimmed)
    }

    private func cleanupRecording(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            print("Cleaned up recording: \(url.path)")
        } catch {
            print("Failed to cleanup recording: \(error)")
        }
    }

    private func updateStatusIcon(recording: Bool = false, processing: Bool = false, downloading: Bool = false, error: Bool = false) {
        guard let button = statusItem?.button else { return }

        if error {
            button.image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: "Error")
            button.image?.isTemplate = true
        } else if downloading {
            button.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "Downloading")
            button.image?.isTemplate = true
        } else if processing {
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "Processing")
            button.image?.isTemplate = true
        } else if recording {
            button.image = NSImage(systemSymbolName: "mic.fill.badge.plus", accessibilityDescription: "Recording")
            button.image?.isTemplate = true
        } else {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Voice to Text")
            button.image?.isTemplate = true
        }
    }
}
