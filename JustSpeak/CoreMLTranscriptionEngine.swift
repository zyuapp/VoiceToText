import AVFoundation
import FluidAudio
import Foundation

enum CoreMLTranscriptionEngineError: LocalizedError, Sendable {
    case modelNotDownloaded
    case modelInitializationFailed(String)
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotDownloaded:
            return "The Parakeet model is not downloaded."
        case .modelInitializationFailed(let message):
            return "Could not initialize the Parakeet model: \(message)"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        }
    }
}

nonisolated final class ModelSetupProgress: @unchecked Sendable {
    private static let maximumBeforeReady = 0.95

    private let lock = NSLock()
    private var lastReported = 0.0

    func normalize(_ upstreamFraction: Double) -> Double {
        lock.lock()
        defer { lock.unlock() }

        let normalized = min(
            max(upstreamFraction, 0),
            Self.maximumBeforeReady
        )
        lastReported = max(lastReported, normalized)
        return lastReported
    }
}

actor CoreMLTranscriptionEngine {
    typealias ProgressHandler = @Sendable (Double) -> Void

    private static let modelVersion: AsrModelVersion = .v2
    private static let minimumInferenceSamples = 16_000

    private let audioConverter = AudioConverter(sampleRate: 16_000)
    private var manager: AsrManager?
    private var isTranscribing = false
    private var transcriptionWaiters: [CheckedContinuation<Void, Never>] = []

    nonisolated var isModelDownloaded: Bool {
        let directory = AsrModels.defaultCacheDirectory(for: Self.modelVersion)
        return AsrModels.modelsExist(at: directory, version: Self.modelVersion)
    }

    func initialize() async throws {
        guard isModelDownloaded else {
            throw CoreMLTranscriptionEngineError.modelNotDownloaded
        }

        do {
            let models = try await AsrModels.loadFromCache(version: Self.modelVersion)
            try await configureManager(with: models)
        } catch let error as CoreMLTranscriptionEngineError {
            throw error
        } catch {
            throw CoreMLTranscriptionEngineError.modelInitializationFailed(
                error.localizedDescription
            )
        }
    }

    func downloadAndInitialize(progress: ProgressHandler? = nil) async throws {
        let setupProgress = ModelSetupProgress()
        progress?(0)

        do {
            let models = try await AsrModels.downloadAndLoad(
                version: Self.modelVersion
            ) { update in
                progress?(setupProgress.normalize(update.fractionCompleted))
            }
            try await configureManager(with: models)
            progress?(1)
        } catch let error as CoreMLTranscriptionEngineError {
            throw error
        } catch {
            throw CoreMLTranscriptionEngineError.modelInitializationFailed(
                error.localizedDescription
            )
        }
    }

    func transcribe(audioFile: URL) async throws -> String {
        guard let manager else {
            throw CoreMLTranscriptionEngineError.modelNotDownloaded
        }

        await waitForTranscriptionSlot()
        defer { releaseTranscriptionSlot() }

        do {
            let result = try await transcribe(audioFile, using: manager)
            return result.text
        } catch {
            throw CoreMLTranscriptionEngineError.transcriptionFailed(
                error.localizedDescription
            )
        }
    }

    private func transcribe(
        _ audioFile: URL,
        using manager: AsrManager
    ) async throws -> ASRResult {
        guard try requiresMinimumPadding(audioFile) else {
            return try await manager.transcribe(audioFile, source: .microphone)
        }

        let samples = try audioConverter.resampleAudioFile(audioFile)
        let paddingCount = max(0, Self.minimumInferenceSamples - samples.count)
        let paddedSamples = samples + Array(repeating: 0, count: paddingCount)
        return try await manager.transcribe(paddedSamples, source: .microphone)
    }

    private func requiresMinimumPadding(_ audioFile: URL) throws -> Bool {
        let file = try AVAudioFile(forReading: audioFile)
        let sampleRateRatio = 16_000 / file.processingFormat.sampleRate
        let estimatedSamples = Double(file.length) * sampleRateRatio
        return estimatedSamples < Double(Self.minimumInferenceSamples)
    }

    private func configureManager(with models: AsrModels) async throws {
        let newManager = AsrManager(config: .default)
        try await newManager.initialize(models: models)

        guard await newManager.isAvailable else {
            throw CoreMLTranscriptionEngineError.modelInitializationFailed(
                "FluidAudio did not make all CoreML models available."
            )
        }

        manager = newManager
    }

    private func waitForTranscriptionSlot() async {
        guard isTranscribing else {
            isTranscribing = true
            return
        }

        await withCheckedContinuation { continuation in
            transcriptionWaiters.append(continuation)
        }
    }

    private func releaseTranscriptionSlot() {
        guard !transcriptionWaiters.isEmpty else {
            isTranscribing = false
            return
        }

        transcriptionWaiters.removeFirst().resume()
    }
}
