import Foundation
import AVFoundation

class AudioRecorder: NSObject {
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private(set) var lastRecordingURL: URL?

    var isRecording: Bool {
        audioRecorder?.isRecording ?? false
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
}

extension AudioRecorder {
    private func createRecordingURL() -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let timestamp = Int(Date().timeIntervalSince1970)
        return tempDir.appendingPathComponent("recording_\(timestamp).wav")
    }

    private func startRecorder(at url: URL) -> Bool {
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
