import Foundation

enum TranscriptionServiceError: Error {
    case modelNotDownloaded
    case whisperInitFailed
    case transcriptionFailed(String)
}

class TranscriptionService {
    static let shared = TranscriptionService()

    private var whisper: WhisperWrapper?
    private let modelDownloader = ModelDownloader.shared

    var isReady: Bool {
        whisper != nil
    }

    var isModelDownloaded: Bool {
        modelDownloader.isModelDownloaded
    }

    func initialize() throws {
        guard modelDownloader.isModelDownloaded else {
            throw TranscriptionServiceError.modelNotDownloaded
        }

        do {
            whisper = try WhisperWrapper(modelPath: modelDownloader.modelPath.path)
        } catch {
            throw TranscriptionServiceError.whisperInitFailed
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
                do {
                    try self?.initialize()
                    completion(.success(()))
                } catch {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func transcribe(audioFile: URL) async throws -> String {
        guard let whisper = whisper else {
            throw TranscriptionServiceError.modelNotDownloaded
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let text = try whisper.transcribe(audioFile: audioFile)
                    continuation.resume(returning: text)
                } catch {
                    continuation.resume(throwing: TranscriptionServiceError.transcriptionFailed(error.localizedDescription))
                }
            }
        }
    }

    func transcribe(audioData: [Float]) async throws -> String {
        guard let whisper = whisper else {
            throw TranscriptionServiceError.modelNotDownloaded
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let text = try whisper.transcribe(audioData: audioData)
                    continuation.resume(returning: text)
                } catch {
                    continuation.resume(throwing: TranscriptionServiceError.transcriptionFailed(error.localizedDescription))
                }
            }
        }
    }
}
