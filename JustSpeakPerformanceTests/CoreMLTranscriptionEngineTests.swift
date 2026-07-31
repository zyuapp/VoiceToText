import FluidAudio
import Foundation
import XCTest

final class CoreMLTranscriptionEngineTests: XCTestCase {
    func testModelSetupProgressReportsActualDownloadFraction() {
        let listing = DownloadUtils.DownloadProgress(
            fractionCompleted: 0,
            phase: .listing
        )
        let halfway = DownloadUtils.DownloadProgress(
            fractionCompleted: 0.25,
            phase: .downloading(completedFiles: 2, totalFiles: 8)
        )
        let complete = DownloadUtils.DownloadProgress(
            fractionCompleted: 0.5,
            phase: .downloading(completedFiles: 8, totalFiles: 8)
        )

        XCTAssertEqual(
            ModelSetupProgress.from(listing),
            .downloading(fractionCompleted: 0)
        )
        XCTAssertEqual(
            ModelSetupProgress.from(halfway),
            .downloading(fractionCompleted: 0.5)
        )
        XCTAssertEqual(
            ModelSetupProgress.from(complete),
            .downloading(fractionCompleted: 1)
        )
    }

    func testModelSetupProgressReportsPreparationAfterDownload() {
        let compiling = DownloadUtils.DownloadProgress(
            fractionCompleted: 0.75,
            phase: .compiling(modelName: "Encoder.mlmodelc")
        )
        let cachedModelLoad = DownloadUtils.DownloadProgress(
            fractionCompleted: 0.5,
            phase: .downloading(completedFiles: 0, totalFiles: 0)
        )

        XCTAssertEqual(ModelSetupProgress.from(compiling), .preparing)
        XCTAssertEqual(ModelSetupProgress.from(cachedModelLoad), .preparing)
    }

    func testTranscriptionRequiresAnInitializedModel() async {
        let engine = CoreMLTranscriptionEngine()
        let missingAudio = URL(fileURLWithPath: "/tmp/just-speak-uninitialized.wav")

        do {
            _ = try await engine.transcribe(audioFile: missingAudio)
            XCTFail("Expected transcription to reject an uninitialized engine.")
        } catch let error as CoreMLTranscriptionEngineError {
            guard case .modelNotDownloaded = error else {
                return XCTFail("Unexpected engine error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
