import Foundation
import AVFoundation
import CoreAudio

class AudioRecorder: NSObject {
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private(set) var lastRecordingURL: URL?
    private var selectedDeviceID: AudioDeviceID?
    private var audioLevelMapper = AdaptiveAudioLevelMapper()
    private var levelFollower = AudioLevelFollower()

    var isRecording: Bool {
        audioRecorder?.isRecording ?? false
    }

    /// Reads the meters and advances the level filter by `deltaTime` seconds, returning the
    /// filtered 0...1 level. `deltaTime` must be non-negative and modestly bounded.
    func sampleLevel(deltaTime: TimeInterval) -> Double {
        guard let audioRecorder, audioRecorder.isRecording else { return 0 }

        audioRecorder.updateMeters()

        let mapped = audioLevelMapper.update(
            averageDecibels: audioRecorder.averagePower(forChannel: 0),
            peakDecibels: audioRecorder.peakPower(forChannel: 0),
            uptime: ProcessInfo.processInfo.systemUptime
        )

        return levelFollower.follow(mapped, deltaTime: deltaTime)
    }

    static func getAvailableInputDevices() -> [(id: AudioDeviceID, name: String)] {
        var devices: [(id: AudioDeviceID, name: String)] = []

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        ) == noErr else { return devices }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else { return devices }

        for deviceID in deviceIDs {
            if hasInputChannels(deviceID: deviceID), let name = getDeviceName(deviceID: deviceID) {
                devices.append((id: deviceID, name: name))
            }
        }

        return devices
    }

    func setInputDevice(id: AudioDeviceID?) {
        selectedDeviceID = id
    }

    static func getCurrentInputDeviceID() -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioDeviceID()
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        ) == noErr else { return nil }

        return deviceID
    }

    private static func hasInputChannels(deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize
        ) == noErr else { return false }

        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferList.deallocate() }

        guard AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            bufferList
        ) == noErr else { return false }

        return bufferList.pointee.mNumberBuffers > 0
    }

    private static func getDeviceName(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceName: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)

        guard AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceName
        ) == noErr else { return nil }

        return deviceName as String
    }

    func startRecording() -> Bool {
        guard let url = createRecordingURL() else { return false }

        recordingURL = url
        return startRecorder(at: url)
    }

    func stopRecording() -> URL? {
        guard let recorder = audioRecorder, recorder.isRecording else {
            return nil
        }

        recorder.stop()
        lastRecordingURL = recordingURL
        print("Recording stopped: \(recordingURL?.path ?? "unknown")")
        return recordingURL
    }

    func cancelRecording() {
        guard let recorder = audioRecorder, recorder.isRecording else {
            return
        }

        recorder.stop()
        print("Recording cancelled")

        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            print("Cancelled recording cleaned up: \(url.path)")
        }

        recordingURL = nil
    }
}

extension AudioRecorder {
    private func createRecordingURL() -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let timestamp = Int(Date().timeIntervalSince1970)
        return tempDir.appendingPathComponent("recording_\(timestamp).wav")
    }

    private func startRecorder(at url: URL) -> Bool {
        if let deviceID = selectedDeviceID {
            setSystemDefaultInputDevice(deviceID: deviceID)
        }

        let settings = createAudioSettings()
        levelFollower.reset()

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioLevelMapper.beginSession()
            audioRecorder?.record()
            print("Recording started: \(url.path)")
            return true
        } catch {
            print("Failed to start recording: \(error)")
            return false
        }
    }

    private func setSystemDefaultInputDevice(deviceID: AudioDeviceID) {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = deviceID
        let dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            dataSize,
            &deviceID
        )

        if status == noErr {
            if let name = Self.getDeviceName(deviceID: deviceID) {
                print("Set input device to: \(name)")
            }
        } else {
            print("Failed to set input device, status: \(status)")
        }
    }

    private func createAudioSettings() -> [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        print(flag ? "Recording finished successfully" : "Recording failed")
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error = error {
            print("Recording encode error: \(error)")
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
