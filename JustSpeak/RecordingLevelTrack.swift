import Foundation

/// Time-stamped ring of recent level samples.
///
/// Samples carry their own timestamp so visualizers can place them against wall-clock
/// time. Scroll speed then stays even even when the sampling timer jitters.
@MainActor
final class RecordingLevelTrack {
    struct Sample {
        let time: TimeInterval
        let level: Double
    }

    static let window: TimeInterval = 2.0

    private var storage: [Sample]
    private var head = 0
    private var count = 0

    init(capacity: Int = 192) {
        storage = Array(repeating: Sample(time: 0, level: 0), count: capacity)
    }

    func append(level: Double, at time: TimeInterval) {
        storage[head] = Sample(time: time, level: level)
        head = (head + 1) % storage.count
        count = min(count + 1, storage.count)
    }

    func clear() {
        head = 0
        count = 0
    }

    /// Samples newer than `cutoff`, oldest first.
    func samples(since cutoff: TimeInterval) -> [Sample] {
        var result: [Sample] = []
        result.reserveCapacity(count)

        for offset in 0..<count {
            let sample = storage[(head - count + offset + storage.count) % storage.count]

            if sample.time >= cutoff {
                result.append(sample)
            }
        }

        return result
    }

}
