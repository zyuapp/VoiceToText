import Foundation

enum ModelDownloadError: Error {
    case downloadFailed(String)
    case invalidURL
    case fileWriteFailed
}

class ModelDownloader: NSObject {
    static let shared = ModelDownloader()

    private let modelName = "ggml-large-v3-turbo.bin"
    private let modelURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin"

    private var downloadTask: URLSessionDownloadTask?
    private var progressHandler: ((Double) -> Void)?
    private var completionHandler: ((Result<URL, Error>) -> Void)?

    var modelPath: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let modelDir = appSupport.appendingPathComponent("VoiceToText/Models", isDirectory: true)

        try? FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        return modelDir.appendingPathComponent(modelName)
    }

    var isModelDownloaded: Bool {
        FileManager.default.fileExists(atPath: modelPath.path)
    }

    func downloadModel(
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        if isModelDownloaded {
            completion(.success(modelPath))
            return
        }

        guard let url = URL(string: modelURL) else {
            completion(.failure(ModelDownloadError.invalidURL))
            return
        }

        self.progressHandler = progress
        self.completionHandler = completion

        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        downloadTask = session.downloadTask(with: url)
        downloadTask?.resume()
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
    }
}

extension ModelDownloader: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            let modelDir = modelPath.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

            if FileManager.default.fileExists(atPath: modelPath.path) {
                try FileManager.default.removeItem(at: modelPath)
            }

            try FileManager.default.moveItem(at: location, to: modelPath)

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.completionHandler?(.success(self.modelPath))
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.completionHandler?(.failure(ModelDownloadError.fileWriteFailed))
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)

        DispatchQueue.main.async { [weak self] in
            self?.progressHandler?(progress)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error = error {
            DispatchQueue.main.async { [weak self] in
                self?.completionHandler?(.failure(ModelDownloadError.downloadFailed(error.localizedDescription)))
            }
        }
    }
}
