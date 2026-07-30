import FluidAudio
import Foundation
import XCTest

final class CoreMLTranscriptionEngineTests: XCTestCase {
    func testModelSetupProgressStaysMonotonicAcrossFluidAudioPasses() {
        let setupProgress = ModelSetupProgress()
        var reported: [Double] = []

        for pass in 0..<7 {
            reported.append(
                setupProgress.normalize(
                    .init(
                        fractionCompleted: 0.5,
                        phase: .downloading(completedFiles: pass, totalFiles: 7)
                    )
                )
            )
            reported.append(
                setupProgress.normalize(
                    .init(
                        fractionCompleted: 1,
                        phase: .compiling(modelName: "")
                    )
                )
            )
        }

        XCTAssertTrue(
            zip(reported, reported.dropFirst()).allSatisfy { pair in
                pair.0 <= pair.1
            },
            "Setup progress must never move backward between FluidAudio loading passes."
        )
        XCTAssertLessThan(reported.max() ?? 1, 1)
        XCTAssertEqual(reported.last ?? 0, 0.95, accuracy: 0.000_001)
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
