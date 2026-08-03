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
        case inputDeviceUnavailable
        case inputCannotBeAdded
        case outputCannotBeAdded
        case wavOutputUnavailable
        case captureSessionDidNotStart
        case recordingCancelled
        case recordingFailed

        var errorDescription: String? {
            switch self {
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
    private var selectedDeviceUniqueID: String?
    private var activeAttemptID: UUID?
    private var pendingStartInfo: RecordingStartInfo?
    private var startCompletion: ((Result<RecordingStartInfo, Error>) -> Void)?
    private var stopCompletion: ((Result<URL, Error>) -> Void)?
    private var unexpectedFinishCompletion: ((Error) -> Void)?
    private var discardRecordingWhenFinished = false
    private var isStarting = false
    private let audioLevelMapper = AudioLevelMapper()
    private var levelFollower = AudioLevelFollower()

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

        let mapped = audioLevelMapper.map(
            averageDecibels: averageDecibels,
            peakDecibels: peakDecibels
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
    ) -> Bool {
        guard captureSession == nil, !isStarting else {
            return false
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
                    Self.removeRecordingFile(at: url)
                    completion(.failure(error))
                }
            }
        }

        return true
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
        activeAttemptID = attemptID
        pendingStartInfo = info
        startCompletion = completion
        unexpectedFinishCompletion = unexpectedFinish
        levelFollower.reset()
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
        Self.removeRecordingFile(at: url)
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
            Self.removeRecordingFile(at: url)
            return
        }

        guard let completion else {
            Self.removeRecordingFile(at: url)
            unexpectedFinish?(error ?? RecorderError.recordingFailed)
            return
        }

        guard recordingFinishedSuccessfully(error: error) else {
            Self.removeRecordingFile(at: url)
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

    static func removeRecordingFile(at url: URL) {
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
