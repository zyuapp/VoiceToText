import Foundation
import AVFoundation

enum WhisperError: Error {
    case modelNotFound
    case initializationFailed
    case transcriptionFailed
    case invalidAudioFormat
}

class WhisperWrapper {
    private var context: OpaquePointer?
    private let modelPath: String

    init(modelPath: String) throws {
        self.modelPath = modelPath

        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw WhisperError.modelNotFound
        }

        var contextParams = whisper_context_default_params()
        contextParams.use_gpu = true

        context = whisper_init_from_file_with_params(modelPath, contextParams)

        guard context != nil else {
            throw WhisperError.initializationFailed
        }
    }

    deinit {
        if let context = context {
            whisper_free(context)
        }
    }

    func transcribe(audioFile: URL) throws -> String {
        guard let audioData = try? loadAudioData(from: audioFile) else {
            throw WhisperError.invalidAudioFormat
        }

        return try transcribe(audioData: audioData)
    }

    func transcribe(audioData: [Float]) throws -> String {
        guard let context = context else {
            throw WhisperError.initializationFailed
        }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_progress = false
        params.print_special = false
        params.print_realtime = false
        params.print_timestamps = false
        params.translate = false
        params.language = UnsafePointer(strdup("en"))
        params.n_threads = 4
        params.offset_ms = 0
        params.no_context = true
        params.single_segment = false

        let result = audioData.withUnsafeBufferPointer { buffer in
            whisper_full(context, params, buffer.baseAddress, Int32(buffer.count))
        }

        if let lang = params.language {
            free(UnsafeMutableRawPointer(mutating: lang))
        }

        guard result == 0 else {
            throw WhisperError.transcriptionFailed
        }

        let segmentCount = whisper_full_n_segments(context)
        var transcription = ""

        for i in 0..<segmentCount {
            if let segmentText = whisper_full_get_segment_text(context, i) {
                transcription += String(cString: segmentText)
            }
        }

        return transcription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadAudioData(from url: URL) throws -> [Float] {
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let frameCount = UInt32(audioFile.length)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw WhisperError.invalidAudioFormat
        }

        try audioFile.read(into: buffer)

        guard let channelData = buffer.floatChannelData else {
            throw WhisperError.invalidAudioFormat
        }

        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))

        if format.sampleRate != 16000 {
            return resample(samples, from: format.sampleRate, to: 16000)
        }

        return samples
    }

    private func resample(_ samples: [Float], from sourceRate: Double, to targetRate: Double) -> [Float] {
        let ratio = sourceRate / targetRate
        let outputLength = Int(Double(samples.count) / ratio)
        var resampled = [Float](repeating: 0, count: outputLength)

        for i in 0..<outputLength {
            let sourceIndex = Double(i) * ratio
            let index = Int(sourceIndex)
            let fraction = Float(sourceIndex - Double(index))

            if index + 1 < samples.count {
                resampled[i] = samples[index] * (1.0 - fraction) + samples[index + 1] * fraction
            } else {
                resampled[i] = samples[index]
            }
        }

        return resampled
    }
}
