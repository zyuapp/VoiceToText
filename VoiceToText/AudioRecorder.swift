import Foundation
import AVFoundation
import CoreAudio

class AudioRecorder: NSObject {
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private(set) var lastRecordingURL: URL?
    private var selectedDeviceID: AudioDeviceID?

    var isRecording: Bool {
        audioRecorder?.isRecording ?? false
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

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.delegate = self
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
