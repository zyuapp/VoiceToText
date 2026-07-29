import SwiftUI

/// Draws the last two seconds of recording levels as fixed-duration bars.
struct RecordingVisualizer: View {
    let track: RecordingLevelTrack

    private static let frameInterval = 1.0 / 60.0
    private static let size = CGSize(width: 126, height: 28)

    var body: some View {
        TimelineView(.animation(minimumInterval: Self.frameInterval)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            RecordingBars(samples: recentSamples(now: now), now: now)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityHidden(true)
    }

    private func recentSamples(now: TimeInterval) -> [RecordingLevelTrack.Sample] {
        track.samples(since: now - RecordingLevelTrack.window)
    }
}

/// Buckets are keyed to absolute time, so each bar keeps its value and slides left
/// instead of flickering in place.
private struct RecordingBars: View {
    let samples: [RecordingLevelTrack.Sample]
    let now: TimeInterval

    private static let barCount = 24
    private static let interval = RecordingLevelTrack.window / Double(barCount)
    private static let restingHeight = 0.07

    var body: some View {
        Canvas { context, size in
            let pitch = size.width / CGFloat(Self.barCount)
            let barWidth = pitch * 0.52

            for (bucket, level) in bucketedLevels() {
                let offset = now / Self.interval - Double(bucket)
                let x = size.width - CGFloat(offset) * pitch

                guard x >= -barWidth, x <= size.width else { continue }

                context.fill(
                    capsule(centeredAt: x, width: barWidth, level: level, size: size),
                    with: .color(.primary.opacity(0.2 + 0.75 * Double(x / size.width)))
                )
            }
        }
    }

    private func bucketedLevels() -> [Int: Double] {
        var levels: [Int: Double] = [:]

        for sample in samples {
            let bucket = Int((sample.time / Self.interval).rounded(.down))
            levels[bucket] = max(levels[bucket] ?? 0, sample.level)
        }

        return levels
    }

    private func capsule(centeredAt x: CGFloat, width: CGFloat, level: Double, size: CGSize) -> Path {
        let height = max(level, Self.restingHeight) * size.height
        let rect = CGRect(
            x: x - width / 2,
            y: (size.height - height) / 2,
            width: width,
            height: height
        )
        return Path(roundedRect: rect, cornerRadius: width / 2)
    }
}
