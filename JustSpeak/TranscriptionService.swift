import Foundation

enum TranscriptionServiceError: Error {
    case modelNotDownloaded
    case parakeetInitFailed
    case transcriptionFailed(String)
}

final class TranscriptionService {
    static let shared = TranscriptionService()

    private var parakeet: ParakeetWrapper?
    private let modelDownloader = ModelDownloader.shared
    private let inferenceQueue = DispatchQueue(
        label: "com.zyu.just-speak.parakeet",
        qos: .userInitiated
    )

    var isReady: Bool {
        parakeet != nil
    }

    var isModelDownloaded: Bool {
        modelDownloader.isModelDownloaded
    }

    func initialize() async throws {
        guard modelDownloader.isModelDownloaded else {
            throw TranscriptionServiceError.modelNotDownloaded
        }

        let modelFiles = modelDownloader.modelFiles
        do {
            parakeet = try await withCheckedThrowingContinuation { continuation in
                inferenceQueue.async {
                    do {
                        let wrapper = try ParakeetWrapper(modelFiles: modelFiles)
                        continuation.resume(returning: wrapper)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } catch {
            throw TranscriptionServiceError.parakeetInitFailed
        }
    }

    func downloadModelIfNeeded(
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        modelDownloader.downloadModel { downloadProgress in
            progress(downloadProgress)
        } completion: { [weak self] result in
            switch result {
            case .success:
                Task {
                    guard let self else { return }
                    do {
                        try await self.initialize()
                        completion(.success(()))
                    } catch {
                        completion(.failure(error))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func transcribe(audioFile: URL) async throws -> String {
        guard let parakeet = parakeet else {
            throw TranscriptionServiceError.modelNotDownloaded
        }

        return try await withCheckedThrowingContinuation { continuation in
            inferenceQueue.async {
                do {
                    let text = try parakeet.transcribe(audioFile: audioFile)
                    continuation.resume(returning: text)
                } catch {
                    continuation.resume(throwing: TranscriptionServiceError.transcriptionFailed(error.localizedDescription))
                }
            }
        }
    }
}
