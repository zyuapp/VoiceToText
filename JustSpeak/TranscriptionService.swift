import Foundation

final class TranscriptionService {
    static let shared = TranscriptionService()

    private let engine: CoreMLTranscriptionEngine
    private var ready = false

    init(engine: CoreMLTranscriptionEngine = CoreMLTranscriptionEngine()) {
        self.engine = engine
    }

    var isReady: Bool {
        ready
    }

    var isModelDownloaded: Bool {
        engine.isModelDownloaded
    }

    func initialize() async throws {
        try await engine.initialize()
        ready = await engine.isReady
    }

    func downloadModelIfNeeded(
        progress: @escaping @MainActor @Sendable (Double) -> Void,
        completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void
    ) {
        let (progressStream, progressContinuation) = AsyncStream<Double>.makeStream()
        let progressDelivery = Task {
            for await downloadProgress in progressStream {
                progress(downloadProgress)
            }
        }

        Task { [weak self] in
            guard let self else {
                progressContinuation.finish()
                await progressDelivery.value
                return
            }

            let result: Result<Void, Error>
            do {
                try await engine.downloadAndInitialize { downloadProgress in
                    progressContinuation.yield(downloadProgress)
                }
                ready = await engine.isReady
                result = .success(())
            } catch {
                result = .failure(error)
            }

            progressContinuation.finish()
            await progressDelivery.value
            completion(result)
        }
    }

    func transcribe(audioFile: URL) async throws -> String {
        guard ready else {
            throw CoreMLTranscriptionEngineError.modelNotDownloaded
        }

        return try await engine.transcribe(audioFile: audioFile)
    }
}
