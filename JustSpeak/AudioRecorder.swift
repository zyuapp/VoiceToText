import Foundation
import AVFoundation
import CoreAudio

class AudioRecorder: NSObject {
    struct InputDevice {
        let uniqueID: String
        let name: String
    }

    struct RecordingStartInfo {
        let inputDeviceName: String
        let usedSystemDefaultFallback: Bool
    }

    private enum RecorderError: LocalizedError {
        case recordingInProgress
        case inputDeviceUnavailable
        case inputCannotBeAdded
        case outputCannotBeAdded
        case wavOutputUnavailable
        case captureSessionDidNotStart
        case recordingCancelled
        case recordingFailed

        var errorDescription: String? {
            switch self {
            case .recordingInProgress:
                return "Another recording is still finishing."
            case .inputDeviceUnavailable:
                return "No audio input device is available."
            case .inputCannotBeAdded:
                return "The selected audio input could not be opened."
            case .outputCannotBeAdded:
                return "The audio recorder could not be configured."
            case .wavOutputUnavailable:
                return "WAV recording is unavailable."
            case .captureSessionDidNotStart:
                return "The selected audio input did not start."
            case .recordingCancelled:
                return "The recording was cancelled."
            case .recordingFailed:
                return "The recording could not be saved."
            }
        }
    }

    private struct InputSelection {
        let device: AVCaptureDevice
        let usedSystemDefaultFallback: Bool
    }

    private struct CaptureResources {
        let session: AVCaptureSession
        let output: AVCaptureAudioFileOutput
    }

    private let captureQueue = DispatchQueue(label: "com.zyu.just-speak.audio-capture")
    private var captureSession: AVCaptureSession?
    private var audioFileOutput: AVCaptureAudioFileOutput?
    private var recordingURL: URL?
    private var selectedDeviceUniqueID: String?
    private var activeAttemptID: UUID?
    private var pendingStartInfo: RecordingStartInfo?
    private var startCompletion: ((Result<RecordingStartInfo, Error>) -> Void)?
    private var stopCompletion: ((Result<URL, Error>) -> Void)?
    private var unexpectedFinishCompletion: ((Error) -> Void)?
    private var discardRecordingWhenFinished = false
    private var isStarting = false
    private var audioLevelMapper = AdaptiveAudioLevelMapper()
    private var levelFollower = AudioLevelFollower()

    var isRecording: Bool {
        audioFileOutput?.isRecording ?? false
    }

    /// Reads the meters and advances the level filter by `deltaTime` seconds, returning the
    /// filtered 0...1 level. `deltaTime` must be non-negative and modestly bounded.
    func sampleLevel(deltaTime: TimeInterval) -> Double {
        guard let audioFileOutput,
              audioFileOutput.isRecording,
              let connection = audioFileOutput.connection(with: .audio),
              !connection.audioChannels.isEmpty else {
            return 0
        }

        let averageDecibels = connection.audioChannels
            .map(\.averagePowerLevel)
            .max() ?? -160
        let peakDecibels = connection.audioChannels
            .map(\.peakHoldLevel)
            .max() ?? -160

        let mapped = audioLevelMapper.update(
            averageDecibels: averageDecibels,
            peakDecibels: peakDecibels,
            uptime: ProcessInfo.processInfo.systemUptime
        )

        return levelFollower.follow(mapped, deltaTime: deltaTime)
    }

    static func getAvailableInputDevices() -> [InputDevice] {
        discoverInputDevices().map {
            InputDevice(uniqueID: $0.uniqueID, name: $0.localizedName)
        }
    }

    static func uniqueID(forLegacyDeviceID deviceID: UInt32) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanagedDeviceUID: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &unmanagedDeviceUID
        )

        guard status == noErr, let unmanagedDeviceUID else { return nil }
        return unmanagedDeviceUID.takeUnretainedValue() as String
    }

    func setInputDevice(id: String?) {
        selectedDeviceUniqueID = id
    }

    func startRecording(
        attemptID: UUID,
        unexpectedFinish: @escaping (Error) -> Void,
        completion: @escaping (Result<RecordingStartInfo, Error>) -> Void
    ) {
        guard captureSession == nil, !isStarting else {
            completion(.failure(RecorderError.recordingInProgress))
            return
        }

        isStarting = true
        let url = createRecordingURL()
        let selectedDeviceUniqueID = selectedDeviceUniqueID

        captureQueue.async { [weak self] in
            guard let self else { return }

            do {
                let result = try self.startRecorder(
                    at: url,
                    selectedDeviceUniqueID: selectedDeviceUniqueID
                )
                DispatchQueue.main.async { [weak self] in
                    self?.completeRecordingStart(
                        resources: result.resources,
                        info: result.info,
                        url: url,
                        attemptID: attemptID,
                        unexpectedFinish: unexpectedFinish,
                        completion: completion
                    )
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.isStarting = false
                    self?.removeRecordingFile(at: url)
                    completion(.failure(error))
                }
            }
        }
    }

    func stopRecording(
        attemptID: UUID,
        completion: @escaping (Result<URL, Error>) -> Void
    ) -> Bool {
        guard let audioFileOutput,
              activeAttemptID == attemptID,
              audioFileOutput.isRecording,
              stopCompletion == nil,
              !discardRecordingWhenFinished else {
            return false
        }

        stopCompletion = completion
        captureQueue.async {
            audioFileOutput.stopRecording()
        }
        return true
    }

    func cancelRecording(attemptID: UUID) {
        guard activeAttemptID == attemptID,
              let audioFileOutput else { return }

        discardRecordingWhenFinished = true
        stopCompletion = nil

        if audioFileOutput.isRecording {
            captureQueue.async {
                audioFileOutput.stopRecording()
            }
        }

        print("Recording cancelled")
    }
}

extension AudioRecorder {
    private static func discoverInputDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    private func createRecordingURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("recording_\(UUID().uuidString).wav")
    }

    private func startRecorder(
        at url: URL,
        selectedDeviceUniqueID: String?
    ) throws -> (resources: CaptureResources, info: RecordingStartInfo) {
        let selection = try resolveInputSelection(
            selectedDeviceUniqueID: selectedDeviceUniqueID
        )
        let resources = try createCaptureResources(for: selection.device)

        resources.session.startRunning()
        guard resources.session.isRunning else {
            throw RecorderError.captureSessionDidNotStart
        }

        return (
            resources: resources,
            info: RecordingStartInfo(
                inputDeviceName: selection.device.localizedName,
                usedSystemDefaultFallback: selection.usedSystemDefaultFallback
            )
        )
    }

    private func resolveInputSelection(
        selectedDeviceUniqueID: String?
    ) throws -> InputSelection {
        if let selectedDeviceUniqueID,
           let selectedDevice = AVCaptureDevice(uniqueID: selectedDeviceUniqueID),
           selectedDevice.isConnected,
           selectedDevice.hasMediaType(.audio) {
            return InputSelection(
                device: selectedDevice,
                usedSystemDefaultFallback: false
            )
        }

        guard let defaultDevice = AVCaptureDevice.default(for: .audio) else {
            throw RecorderError.inputDeviceUnavailable
        }

        return InputSelection(
            device: defaultDevice,
            usedSystemDefaultFallback: selectedDeviceUniqueID != nil
        )
    }

    private func createCaptureResources(for device: AVCaptureDevice) throws -> CaptureResources {
        guard AVCaptureAudioFileOutput.availableOutputFileTypes().contains(.wav) else {
            throw RecorderError.wavOutputUnavailable
        }

        let session = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureAudioFileOutput()

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard session.canAddInput(input) else {
            throw RecorderError.inputCannotBeAdded
        }
        session.addInput(input)

        guard session.canAddOutput(output) else {
            throw RecorderError.outputCannotBeAdded
        }
        session.addOutput(output)
        output.audioSettings = createAudioSettings()

        return CaptureResources(
            session: session,
            output: output
        )
    }

    private func completeRecordingStart(
        resources: CaptureResources,
        info: RecordingStartInfo,
        url: URL,
        attemptID: UUID,
        unexpectedFinish: @escaping (Error) -> Void,
        completion: @escaping (Result<RecordingStartInfo, Error>) -> Void
    ) {
        captureSession = resources.session
        audioFileOutput = resources.output
        recordingURL = url
        activeAttemptID = attemptID
        pendingStartInfo = info
        startCompletion = completion
        unexpectedFinishCompletion = unexpectedFinish
        levelFollower.reset()
        audioLevelMapper.beginSession()
        resources.output.startRecording(
            to: url,
            outputFileType: .wav,
            recordingDelegate: self
        )
    }

    private func finishRecordingStart(
        output: AVCaptureFileOutput,
        url: URL
    ) {
        guard output === audioFileOutput,
              let info = pendingStartInfo,
              let completion = startCompletion else { return }

        pendingStartInfo = nil
        startCompletion = nil
        isStarting = false

        guard !discardRecordingWhenFinished else {
            captureQueue.async {
                output.stopRecording()
            }
            completion(.failure(RecorderError.recordingCancelled))
            return
        }

        print("Recording started with \(info.inputDeviceName): \(url.path)")
        completion(.success(info))
    }

    private func finishRecording(
        output: AVCaptureFileOutput,
        url: URL,
        error: Error?
    ) {
        guard output === audioFileOutput else { return }

        let startCompletion = startCompletion
        let completion = stopCompletion
        let unexpectedFinish = unexpectedFinishCompletion
        let shouldDiscard = discardRecordingWhenFinished
        let session = clearCaptureState()

        stopCaptureSession(session) { [weak self] in
            if let startCompletion {
                self?.completeFailedRecordingStart(
                    url: url,
                    error: error,
                    shouldDiscard: shouldDiscard,
                    completion: startCompletion
                )
                return
            }

            self?.completeRecordingFinish(
                url: url,
                error: error,
                shouldDiscard: shouldDiscard,
                completion: completion,
                unexpectedFinish: unexpectedFinish
            )
        }
    }

    private func recordingFinishedSuccessfully(error: Error?) -> Bool {
        guard let error else { return true }

        return (error as NSError)
            .userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true
    }

    private func completeFailedRecordingStart(
        url: URL,
        error: Error?,
        shouldDiscard: Bool,
        completion: (Result<RecordingStartInfo, Error>) -> Void
    ) {
        removeRecordingFile(at: url)
        let failure = shouldDiscard
            ? RecorderError.recordingCancelled
            : error ?? RecorderError.recordingFailed
        completion(.failure(failure))
    }

    private func completeRecordingFinish(
        url: URL,
        error: Error?,
        shouldDiscard: Bool,
        completion: ((Result<URL, Error>) -> Void)?,
        unexpectedFinish: ((Error) -> Void)?
    ) {
        if shouldDiscard {
            removeRecordingFile(at: url)
            return
        }

        guard let completion else {
            removeRecordingFile(at: url)
            unexpectedFinish?(error ?? RecorderError.recordingFailed)
            return
        }

        guard recordingFinishedSuccessfully(error: error) else {
            removeRecordingFile(at: url)
            completion(.failure(error ?? RecorderError.recordingFailed))
            return
        }

        print("Recording stopped: \(url.path)")
        completion(.success(url))
    }

    private func clearCaptureState() -> AVCaptureSession? {
        let session = captureSession
        captureSession = nil
        audioFileOutput = nil
        recordingURL = nil
        activeAttemptID = nil
        pendingStartInfo = nil
        startCompletion = nil
        stopCompletion = nil
        unexpectedFinishCompletion = nil
        discardRecordingWhenFinished = false
        isStarting = false
        return session
    }

    private func stopCaptureSession(
        _ session: AVCaptureSession?,
        completion: @escaping () -> Void
    ) {
        captureQueue.async {
            if session?.isRunning == true {
                session?.stopRunning()
            }

            DispatchQueue.main.async {
                completion()
            }
        }
    }

    private func removeRecordingFile(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            try FileManager.default.removeItem(at: url)
            print("Recording cleaned up: \(url.path)")
        } catch {
            print("Failed to clean up recording: \(error)")
        }
    }

    private func createAudioSettings() -> [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]
    }
}

extension AudioRecorder: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.finishRecordingStart(
                output: output,
                url: fileURL
            )
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.finishRecording(
                output: output,
                url: outputFileURL,
                error: error
            )
        }
    }
}

private struct AdaptiveAudioLevelMapper {
    private enum Constants {
        static let initialNoiseFloor: Float = -50
        static let minimumNoiseFloor: Float = -70
        static let maximumNoiseFloor: Float = -25
        static let gateOpenSNR: Float = 6
        static let gateCloseSNR: Float = 3
        static let fullScaleSNR: Float = 25
        static let steadyLevelDeviation: Float = 2
        static let maximumSteadyNoiseSNR: Float = 14
        static let normalRiseRate: Float = 1.5
        static let steadyRiseRate: Float = 6
        static let hangoverDuration = 0.4
        static let recentLevelCapacity = 15
    }

    private var noiseFloor = Constants.initialNoiseFloor
    private var gateIsOpen = false
    private var hangoverRemaining = 0.0
    private var recentLevels: [Float] = []
    private var lastUpdateTime: TimeInterval?

    mutating func beginSession() {
        self = Self()
    }

    mutating func update(
        averageDecibels: Float,
        peakDecibels: Float,
        uptime: TimeInterval
    ) -> Double {
        let interval = updateInterval(at: uptime)
        let level = max(averageDecibels, peakDecibels - 8)

        guard level.isFinite, level > -100 else { return 0 }

        recordRecentLevel(level)
        adaptNoiseFloor(toward: level, interval: interval)

        let signalToNoise = level - noiseFloor
        updateGate(signalToNoise: signalToNoise, interval: interval)
        return visualLevel(signalToNoise: signalToNoise)
    }

    private mutating func updateInterval(at uptime: TimeInterval) -> TimeInterval {
        defer { lastUpdateTime = uptime }
        guard let lastUpdateTime else { return 1.0 / 30.0 }
        return min(max(uptime - lastUpdateTime, 1.0 / 120.0), 0.1)
    }

    private mutating func recordRecentLevel(_ level: Float) {
        recentLevels.append(level)
        if recentLevels.count > Constants.recentLevelCapacity {
            recentLevels.removeFirst()
        }
    }

    private mutating func adaptNoiseFloor(toward level: Float, interval: TimeInterval) {
        if level < noiseFloor {
            let alpha = Float(1 - exp(-interval / 0.25))
            noiseFloor += (level - noiseFloor) * alpha
        } else if shouldRaiseNoiseFloor(toward: level) {
            let rate = recentLevelsAreSteady ? Constants.steadyRiseRate : Constants.normalRiseRate
            noiseFloor += min(level - noiseFloor, rate * Float(interval))
        }

        noiseFloor = min(
            max(noiseFloor, Constants.minimumNoiseFloor),
            Constants.maximumNoiseFloor
        )
    }

    private func shouldRaiseNoiseFloor(toward level: Float) -> Bool {
        guard gateIsOpen else { return true }
        return recentLevelsAreSteady
            && level - noiseFloor <= Constants.maximumSteadyNoiseSNR
    }

    private var recentLevelsAreSteady: Bool {
        guard recentLevels.count == Constants.recentLevelCapacity else { return false }

        let mean = recentLevels.reduce(0, +) / Float(recentLevels.count)
        let variance = recentLevels.reduce(0) { total, level in
            let difference = level - mean
            return total + difference * difference
        } / Float(recentLevels.count)
        return sqrt(variance) < Constants.steadyLevelDeviation
    }

    private mutating func updateGate(signalToNoise: Float, interval: TimeInterval) {
        if signalToNoise >= Constants.gateOpenSNR {
            gateIsOpen = true
            hangoverRemaining = Constants.hangoverDuration
        } else if gateIsOpen, signalToNoise < Constants.gateCloseSNR {
            hangoverRemaining -= interval
            if hangoverRemaining <= 0 {
                gateIsOpen = false
            }
        }
    }

    private func visualLevel(signalToNoise: Float) -> Double {
        let usableSignal = max(signalToNoise - Constants.gateCloseSNR, 0)
        let usableRange = Constants.fullScaleSNR - Constants.gateCloseSNR
        let normalizedLevel = min(usableSignal / usableRange, 1)
        return Double(pow(normalizedLevel, 0.7))
    }
}
