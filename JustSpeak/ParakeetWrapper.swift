import Foundation
import AVFoundation

enum ParakeetError: Error {
    case initializationFailed
    case transcriptionFailed
    case invalidAudioFormat
}

final class ParakeetWrapper: @unchecked Sendable {
    private let bridge: ParakeetBridge

    init(modelFiles: ParakeetModelFiles) throws {
        do {
            bridge = try ParakeetBridge(
                encoderPath: modelFiles.encoder.path,
                decoderPath: modelFiles.decoder.path,
                joinerPath: modelFiles.joiner.path,
                tokensPath: modelFiles.tokens.path
            )
        } catch {
            throw ParakeetError.initializationFailed
        }
    }

    func transcribe(audioFile: URL) throws -> String {
        guard let audioData = try? loadAudioData(from: audioFile) else {
            throw ParakeetError.invalidAudioFormat
        }

        return try transcribe(audioData: audioData)
    }

    func transcribe(audioData: [Float]) throws -> String {
        guard !audioData.isEmpty else {
            throw ParakeetError.invalidAudioFormat
        }

        do {
            return try audioData.withUnsafeBufferPointer { buffer in
                try bridge.transcribeSamples(buffer.baseAddress!, count: buffer.count)
            }
        } catch {
            throw ParakeetError.transcriptionFailed
        }
    }

    private func loadAudioData(from url: URL) throws -> [Float] {
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let frameCount = UInt32(audioFile.length)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw ParakeetError.invalidAudioFormat
        }

        try audioFile.read(into: buffer)

        guard let channelData = buffer.floatChannelData else {
            throw ParakeetError.invalidAudioFormat
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
