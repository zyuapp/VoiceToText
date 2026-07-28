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

    /// Loudest level in each of `buckets` equal time slices ending at `now`, oldest first.
    /// Resampling in space keeps the drawing smooth without slowing the meter down.
    func resample(now: TimeInterval, span: TimeInterval, buckets: Int) -> [Double] {
        var levels = [Double](repeating: 0, count: buckets)

        for offset in 0..<count {
            let sample = storage[(head - count + offset + storage.count) % storage.count]
            let age = now - sample.time

            guard age >= 0, age <= span else { continue }

            let index = min(Int((1 - age / span) * Double(buckets)), buckets - 1)
            levels[index] = max(levels[index], sample.level)
        }

        return levels
    }

    /// Level recorded at or just before `time`, or 0 when the track has nothing that old.
    func level(at time: TimeInterval) -> Double {
        for offset in stride(from: count - 1, through: 0, by: -1) {
            let sample = storage[(head - count + offset + storage.count) % storage.count]

            if sample.time <= time {
                return sample.level
            }
        }

        return 0
    }
}
