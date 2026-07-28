import Foundation

/// Sparks thrown off the ember trail at syllable onsets.
///
/// Positions are normalized: `x` runs 0 (oldest edge) to 1 (live edge) and `y` is in the
/// same 0...1 space the trail's level uses, so the field is independent of the drawn size.
/// Advanced by the level sampler rather than by drawing, which keeps the step uniform.
@MainActor
final class EmberSparkField {
    struct Spark {
        var x: Double
        var y: Double
        var velocityX: Double
        var velocityY: Double
        var life: Double
    }

    private(set) var sparks: [Spark] = []
    private var isArmed = true
    private var emissionSeed = 0

    private static let onsetLevel = 0.55
    private static let rearmLevel = 0.38
    private static let lifeSeconds = 0.62
    private static let burstSize = 3
    private static let limit = 48

    func clear() {
        sparks.removeAll(keepingCapacity: true)
        isArmed = true
    }

    func advance(level: Double, deltaTime: TimeInterval) {
        emit(level: level)

        for index in sparks.indices {
            sparks[index].x += sparks[index].velocityX * deltaTime
            sparks[index].y += sparks[index].velocityY * deltaTime
            sparks[index].velocityY -= sparks[index].velocityY * 1.8 * deltaTime
            sparks[index].life -= deltaTime / Self.lifeSeconds
        }

        sparks.removeAll { $0.life <= 0 || $0.x < -0.05 }
    }

    private func emit(level: Double) {
        if level < Self.rearmLevel {
            isArmed = true
        }

        guard isArmed, level >= Self.onsetLevel else { return }

        isArmed = false

        guard sparks.count + Self.burstSize <= Self.limit else { return }

        for _ in 0..<Self.burstSize {
            emissionSeed &+= 1
            let spread = Self.jitter(emissionSeed)
            sparks.append(
                Spark(
                    x: 1,
                    y: level,
                    velocityX: -0.22 - 0.5 * Self.jitter(emissionSeed &* 7),
                    velocityY: 0.18 + 0.5 * spread,
                    life: 1
                )
            )
        }
    }

    /// Deterministic 0...1 scatter; a seeded hash keeps bursts varied without pulling in RNG.
    private static func jitter(_ seed: Int) -> Double {
        let mixed = UInt64(bitPattern: Int64(seed &* 2_654_435_761)) &* 0x9E37_79B9_7F4A_7C15
        return Double(mixed >> 40) / Double(UInt64(1) << 24)
    }
}
