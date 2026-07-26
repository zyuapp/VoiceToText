import Foundation

enum ParakeetModel {
    static let id = "sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8"
    static let archiveURLString =
        "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/\(id).tar.bz2"
    static let archiveSHA256 =
        "157c157bc51155e03e37d2466522a3a737dd9c72bb25f36eb18912964161e1ad"

    static func files(in directory: URL) -> ParakeetModelFiles {
        ParakeetModelFiles(
            encoder: directory.appendingPathComponent("encoder.int8.onnx"),
            decoder: directory.appendingPathComponent("decoder.int8.onnx"),
            joiner: directory.appendingPathComponent("joiner.int8.onnx"),
            tokens: directory.appendingPathComponent("tokens.txt")
        )
    }
}

struct ParakeetModelFiles: Sendable {
    let encoder: URL
    let decoder: URL
    let joiner: URL
    let tokens: URL

    var all: [URL] {
        [encoder, decoder, joiner, tokens]
    }
}
