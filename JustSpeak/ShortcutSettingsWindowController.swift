import AppKit
import SwiftUI

@MainActor
final class ShortcutSettingsWindowController: NSWindowController, NSWindowDelegate {
    private let captureController: ShortcutCaptureController

    init(
        store: RecordingShortcutStore,
        captureController: ShortcutCaptureController
    ) {
        self.captureController = captureController

        let hostingController = NSHostingController(
            rootView: ShortcutSettingsView(
                store: store,
                captureController: captureController
            )
        )
        let window = NSWindow(contentViewController: hostingController)

        window.title = "Recording Shortcut"
        window.styleMask = [.titled, .closable]
        window.collectionBehavior = [.moveToActiveSpace]
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed

        hostingController.view.layoutSubtreeIfNeeded()
        window.setContentSize(hostingController.view.fittingSize)
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }

            NSApplication.shared.activate(ignoringOtherApps: true)
            self.showWindow(nil)
            window.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        captureController.cancelCapture()
    }
}
