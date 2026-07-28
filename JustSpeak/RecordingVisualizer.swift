import SwiftUI

/// Recording level styles. `visualizerSize` and `pillWidth` move together: the pill shrinks
/// by exactly the width the visualizer gives up.
enum RecordingVisualizerStyle: String, CaseIterable {
    case ember
    case envelope
    case bars
    case ripple

    static let `default` = RecordingVisualizerStyle.ember

    var title: String {
        switch self {
        case .ember: "Ember"
        case .envelope: "Envelope"
        case .bars: "Bars"
        case .ripple: "Ripple"
        }
    }

    var visualizerSize: CGSize {
        switch self {
        case .ember, .envelope, .bars: CGSize(width: 126, height: 28)
        case .ripple: CGSize(width: 46, height: 30)
        }
    }

    var pillWidth: CGFloat {
        switch self {
        case .ember, .envelope, .bars: 300
        case .ripple: 232
        }
    }
}

/// Draws the recording level. A single `TimelineView` drives every style, so the drawing
/// clock and the sampling clock never beat against each other. Drawing faster than the
/// sampler feeds it would only repaint identical frames.
struct RecordingVisualizer: View {
    let style: RecordingVisualizerStyle
    let track: RecordingLevelTrack
    let sparkField: EmberSparkField

    private static let frameInterval = 1.0 / 60.0

    var body: some View {
        TimelineView(.animation(minimumInterval: Self.frameInterval)) { timeline in
            content(now: timeline.date.timeIntervalSinceReferenceDate)
        }
        .frame(width: style.visualizerSize.width, height: style.visualizerSize.height)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func content(now: TimeInterval) -> some View {
        switch style {
        case .ember:
            EmberVisualizer(
                levels: track.resample(
                    now: now,
                    span: RecordingLevelTrack.window,
                    buckets: EmberVisualizer.traceResolution
                ),
                live: track.level(at: now),
                sparks: sparkField.sparks,
                time: now
            )
        case .envelope:
            EnvelopeVisualizer(samples: recentSamples(now: now), now: now)
        case .bars:
            BarsVisualizer(samples: recentSamples(now: now), now: now)
        case .ripple:
            RippleVisualizer(levels: RippleVisualizer.delays.map { track.level(at: now - $0) })
        }
    }

    private func recentSamples(now: TimeInterval) -> [RecordingLevelTrack.Sample] {
        track.samples(since: now - RecordingLevelTrack.window)
    }
}

/// A trail rising from a floor with a glowing head at the live edge, shedding sparks on
/// syllable onsets. Resampling to a few dozen buckets and curving through them keeps the
/// line smooth while the meter itself stays instant.
private struct EmberVisualizer: View {
    let levels: [Double]
    let live: Double
    let sparks: [EmberSparkField.Spark]
    let time: TimeInterval

    static let traceResolution = 30

    private static let inset: CGFloat = 2.5
    private static let glow = Color(red: 0.98, green: 0.68, blue: 0.34)

    var body: some View {
        Canvas { context, size in
            let geometry = TraceGeometry(size: size, inset: Self.inset)

            drawTrail(in: &context, geometry: geometry)
            drawSparks(in: &context, geometry: geometry)
            drawHead(in: &context, geometry: geometry)
        }
    }

    /// Keeps silence breathing instead of flatlining.
    private func restingLevel(at index: Int) -> Double {
        0.05 + 0.028 * sin(time * 1.7 + Double(index) * 0.42)
    }

    private func drawTrail(in context: inout GraphicsContext, geometry: TraceGeometry) {
        let points = levels.enumerated().map { index, level in
            CGPoint(
                x: geometry.x(progress: Double(index) / Double(max(levels.count - 1, 1))),
                y: geometry.y(level: max(level, restingLevel(at: index)))
            )
        }

        guard points.count > 1 else { return }

        context.stroke(
            smoothPath(through: points),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: .primary.opacity(0), location: 0),
                    .init(color: .primary.opacity(0.42), location: 0.62),
                    .init(color: Self.glow.opacity(0.95), location: 1)
                ]),
                startPoint: .zero,
                endPoint: CGPoint(x: geometry.size.width, y: 0)
            ),
            style: StrokeStyle(lineWidth: 1.4 + live * 1.3, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawSparks(in context: inout GraphicsContext, geometry: TraceGeometry) {
        for spark in sparks {
            let radius = 0.5 + 0.8 * spark.life
            let center = CGPoint(
                x: geometry.x(progress: spark.x),
                y: geometry.y(level: spark.y)
            )

            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )),
                with: .color(Self.glow.opacity(spark.life * 0.85))
            )
        }
    }

    private func drawHead(in context: inout GraphicsContext, geometry: TraceGeometry) {
        let center = CGPoint(
            x: geometry.x(progress: 1),
            y: geometry.y(level: max(live, restingLevel(at: levels.count - 1)))
        )
        let core = 1.5 + live * 1.9

        context.fill(
            Path(ellipseIn: CGRect(
                x: center.x - core * 2.6,
                y: center.y - core * 2.6,
                width: core * 5.2,
                height: core * 5.2
            )),
            with: .radialGradient(
                Gradient(colors: [Self.glow.opacity(0.3 + 0.35 * live), Self.glow.opacity(0)]),
                center: center,
                startRadius: 0,
                endRadius: core * 2.6
            )
        )

        context.fill(
            Path(ellipseIn: CGRect(
                x: center.x - core,
                y: center.y - core,
                width: core * 2,
                height: core * 2
            )),
            with: .color(Self.glow)
        )
    }

    private func smoothPath(through points: [CGPoint]) -> Path {
        var path = Path()
        path.move(to: points[0])

        for index in 1..<(points.count - 1) {
            let midpoint = CGPoint(
                x: (points[index].x + points[index + 1].x) / 2,
                y: (points[index].y + points[index + 1].y) / 2
            )
            path.addQuadCurve(to: midpoint, control: points[index])
        }

        path.addLine(to: points[points.count - 1])
        return path
    }
}

/// Maps normalized trail coordinates onto the canvas.
private struct TraceGeometry {
    let size: CGSize
    let inset: CGFloat

    func x(progress: Double) -> CGFloat {
        inset + CGFloat(progress) * (size.width - inset * 2)
    }

    func y(level: Double) -> CGFloat {
        size.height - inset - CGFloat(min(max(level, 0), 1)) * (size.height - inset * 2)
    }
}

/// Mirrored envelope that scrolls right to left, drawing the last two seconds of speech.
private struct EnvelopeVisualizer: View {
    let samples: [RecordingLevelTrack.Sample]
    let now: TimeInterval

    private static let restingThickness = 0.035

    var body: some View {
        Canvas { context, size in
            context.fill(
                shape(size: size),
                with: .linearGradient(
                    Gradient(colors: [.primary.opacity(0.12), .primary.opacity(0.95)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: 0)
                )
            )
        }
    }

    private func shape(size: CGSize) -> Path {
        let midY = size.height / 2
        let reach = midY - 1
        let points = topEdge(size: size, midY: midY, reach: reach)

        guard points.count > 1 else {
            return restingPath(size: size, midY: midY, reach: reach)
        }

        var path = Path()
        path.move(to: points[0])

        for point in points.dropFirst() {
            path.addLine(to: point)
        }

        for point in points.reversed() {
            path.addLine(to: CGPoint(x: point.x, y: 2 * midY - point.y))
        }

        path.closeSubpath()
        return path
    }

    private func topEdge(size: CGSize, midY: CGFloat, reach: CGFloat) -> [CGPoint] {
        samples.compactMap { sample in
            let age = now - sample.time

            guard age >= 0, age <= RecordingLevelTrack.window else { return nil }

            let x = size.width * (1 - age / RecordingLevelTrack.window)
            let amplitude = max(sample.level, Self.restingThickness) * reach
            return CGPoint(x: x, y: midY - amplitude)
        }
    }

    private func restingPath(size: CGSize, midY: CGFloat, reach: CGFloat) -> Path {
        let thickness = Self.restingThickness * reach
        return Path(
            roundedRect: CGRect(
                x: 0,
                y: midY - thickness,
                width: size.width,
                height: thickness * 2
            ),
            cornerRadius: thickness
        )
    }
}

/// Fixed-duration buckets rendered as capsules. Buckets are keyed to absolute time, so
/// each bar keeps its value and slides left instead of flickering in place.
private struct BarsVisualizer: View {
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

/// Concentric rings driven by the level at increasing delays, so loudness radiates
/// outward as a ripple instead of only pulsing a single dot.
private struct RippleVisualizer: View {
    let levels: [Double]

    static let delays: [TimeInterval] = [0, 0.09, 0.19]

    private static let radii: [(base: Double, span: Double)] = [
        (0.22, 0.28),
        (0.44, 0.40),
        (0.64, 0.36)
    ]

    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height) / 2 - 0.75
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            for index in Self.radii.indices.reversed() {
                let level = levels.indices.contains(index) ? levels[index] : 0
                let ring = Self.radii[index]
                let radius = (ring.base + ring.span * level) * unit
                let path = Path(ellipseIn: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))

                if index == 0 {
                    context.fill(path, with: .color(.primary.opacity(0.55 + 0.45 * level)))
                } else {
                    context.stroke(
                        path,
                        with: .color(.primary.opacity((0.62 - 0.2 * Double(index)) * (0.3 + 0.7 * level))),
                        lineWidth: 1.7 - 0.45 * Double(index)
                    )
                }
            }
        }
    }
}
