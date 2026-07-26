import CryptoKit
import Foundation

enum ModelDownloadError: Error {
    case invalidURL
    case downloadFailed(String)
    case integrityCheckFailed
    case extractionFailed(String)
    case invalidArchive
    case fileWriteFailed(String)
}

extension ModelDownloadError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The Parakeet model URL is invalid."
        case .downloadFailed(let message):
            return "Parakeet model download failed: \(message)"
        case .integrityCheckFailed:
            return "The downloaded Parakeet model failed its integrity check."
        case .extractionFailed(let message):
            return "Could not extract the Parakeet model: \(message)"
        case .invalidArchive:
            return "The Parakeet model archive is missing required files."
        case .fileWriteFailed(let message):
            return "Could not install the Parakeet model: \(message)"
        }
    }
}

final class ModelDownloader: NSObject {
    static let shared = ModelDownloader()

    private var downloadTask: URLSessionDownloadTask?
    private var progressHandler: ((Double) -> Void)?
    private var completionHandler: ((Result<URL, Error>) -> Void)?

    var modelDirectory: URL {
        appSupportDirectory
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("parakeet", isDirectory: true)
            .appendingPathComponent(ParakeetModel.id, isDirectory: true)
    }

    var modelFiles: ParakeetModelFiles {
        ParakeetModel.files(in: modelDirectory)
    }

    var isModelDownloaded: Bool {
        modelFiles.all.allSatisfy {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }

    func downloadModel(
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        if isModelDownloaded {
            completion(.success(modelDirectory))
            return
        }

        guard let url = URL(string: ParakeetModel.archiveURLString) else {
            completion(.failure(ModelDownloadError.invalidURL))
            return
        }

        progressHandler = progress
        completionHandler = completion

        let session = URLSession(
            configuration: .default,
            delegate: self,
            delegateQueue: nil
        )
        downloadTask = session.downloadTask(with: url)
        downloadTask?.resume()
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
    }

    private var appSupportDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("just-speak", isDirectory: true)
    }

    private func installModel(from downloadedArchive: URL) throws {
        let fileManager = FileManager.default
        let downloadsDirectory = appSupportDirectory
            .appendingPathComponent("Models/.downloads", isDirectory: true)
        let archive = downloadsDirectory
            .appendingPathComponent("\(ParakeetModel.id).tar.bz2")
        let extractingDirectory = downloadsDirectory
            .appendingPathComponent("\(ParakeetModel.id).extracting", isDirectory: true)
        let stagingDirectory = downloadsDirectory
            .appendingPathComponent("\(ParakeetModel.id).installing", isDirectory: true)

        try fileManager.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
        removeIfPresent(archive)
        removeIfPresent(extractingDirectory)
        removeIfPresent(stagingDirectory)

        do {
            try fileManager.moveItem(at: downloadedArchive, to: archive)
            guard try sha256(of: archive) == ParakeetModel.archiveSHA256 else {
                throw ModelDownloadError.integrityCheckFailed
            }

            try fileManager.createDirectory(
                at: extractingDirectory,
                withIntermediateDirectories: true
            )
            try extract(archive: archive, to: extractingDirectory)
            try stageModel(from: extractingDirectory, at: stagingDirectory)

            try fileManager.createDirectory(
                at: modelDirectory.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            removeIfPresent(modelDirectory)
            try fileManager.moveItem(at: stagingDirectory, to: modelDirectory)
        } catch let error as ModelDownloadError {
            throw error
        } catch {
            throw ModelDownloadError.fileWriteFailed(error.localizedDescription)
        }

        removeIfPresent(archive)
        removeIfPresent(extractingDirectory)
    }

    private func extract(archive: URL, to destination: URL) throws {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xjf", archive.path, "-C", destination.path]
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw ModelDownloadError.extractionFailed(error.localizedDescription)
        }

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ModelDownloadError.extractionFailed(message ?? "tar exited with an error")
        }
    }

    private func stageModel(from extractingDirectory: URL, at stagingDirectory: URL) throws {
        let fileManager = FileManager.default
        let nestedDirectory = extractingDirectory
            .appendingPathComponent(ParakeetModel.id, isDirectory: true)
        let sourceDirectory = fileManager.fileExists(atPath: nestedDirectory.path)
            ? nestedDirectory
            : extractingDirectory

        let sourceFiles = ParakeetModel.files(in: sourceDirectory).all
        guard sourceFiles.allSatisfy({ fileManager.fileExists(atPath: $0.path) }) else {
            throw ModelDownloadError.invalidArchive
        }

        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        for source in sourceFiles {
            try fileManager.copyItem(
                at: source,
                to: stagingDirectory.appendingPathComponent(source.lastPathComponent)
            )
        }
    }

    private func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func removeIfPresent(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

extension ModelDownloader: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            try installModel(from: location)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.completionHandler?(.success(self.modelDirectory))
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.completionHandler?(.failure(error))
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
        guard totalBytesExpectedToWrite > 0 else { return }
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
        guard let error else { return }
        DispatchQueue.main.async { [weak self] in
            self?.completionHandler?(
                .failure(ModelDownloadError.downloadFailed(error.localizedDescription))
            )
        }
    }
}
