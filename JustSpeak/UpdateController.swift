import AppKit
import Sparkle

@MainActor
final class UpdateController: NSObject, SPUUserDriver {
    let menuItem = NSMenuItem(
        title: "Check for Updates…",
        action: #selector(performMenuAction),
        keyEquivalent: ""
    )

    private lazy var updater = SPUUpdater(
        hostBundle: .main,
        applicationBundle: .main,
        userDriver: self,
        delegate: nil
    )
    private var updateReply: ((SPUUserUpdateChoice) -> Void)?
    private var readyReply: ((SPUUserUpdateChoice) -> Void)?
    private var updateVersion: String?
    private var expectedDownloadSize: UInt64 = 0
    private var downloadedSize: UInt64 = 0

    override init() {
        super.init()
        menuItem.target = self
    }

    func start() {
        do {
            try updater.start()
            updater.checkForUpdatesInBackground()
        } catch {
            showFailure(error)
        }
    }

    @objc private func performMenuAction() {
        if let readyReply {
            self.readyReply = nil
            readyReply(.install)
        } else if let updateReply {
            self.updateReply = nil
            updateReply(.install)
        } else {
            updater.checkForUpdates()
        }
    }

    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        setMenu(title: "Checking for Updates…", enabled: false)
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        updateVersion = appcastItem.displayVersionString

        if appcastItem.isInformationOnlyUpdate {
            reply(.dismiss)
            setIdle()
        } else if state.stage == .downloaded {
            readyReply = reply
            showReady()
        } else {
            updateReply = reply
            setMenu(
                title: "Update \(appcastItem.displayVersionString) Available — Download",
                enabled: true
            )
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
        print("Update release notes error: \(error)")
    }

    func showUpdateNotFoundWithError(
        _ error: Error,
        acknowledgement: @escaping () -> Void
    ) {
        setIdle()
        acknowledgement()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        showFailure(error)
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        setMenu(title: "Downloading Update…", enabled: false)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedDownloadSize = expectedContentLength
        downloadedSize = 0
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        downloadedSize += length
        guard expectedDownloadSize > 0 else { return }
        let percent = min(downloadedSize * 100 / expectedDownloadSize, 100)
        setMenu(title: "Downloading Update… \(percent)%", enabled: false)
    }

    func showDownloadDidStartExtractingUpdate() {
        setMenu(title: "Preparing Update…", enabled: false)
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        let percent = Int(min(max(progress, 0), 1) * 100)
        setMenu(title: "Preparing Update… \(percent)%", enabled: false)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        readyReply = reply
        showReady()
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        setMenu(title: "Installing Update…", enabled: false)
    }

    func showUpdateInstalledAndRelaunched(
        _ relaunched: Bool,
        acknowledgement: @escaping () -> Void
    ) {
        acknowledgement()
    }

    func dismissUpdateInstallation() {
        updateReply = nil
        readyReply = nil
        setIdle()
    }

    private func showReady() {
        let suffix = updateVersion.map { " \($0)" } ?? ""
        setMenu(title: "Restart to Install Update\(suffix)", enabled: true)
    }

    private func showFailure(_ error: Error) {
        print("Update error: \(error)")
        setMenu(title: "Update Check Failed — Try Again", enabled: true)
    }

    private func setIdle() {
        setMenu(title: "Check for Updates…", enabled: true)
    }

    private func setMenu(title: String, enabled: Bool) {
        menuItem.title = title
        menuItem.isEnabled = enabled
    }
}
