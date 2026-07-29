import Foundation

/// Smooths the mapped 0...1 level over time.
///
/// `AudioLevelMapper` decides how loud a frame is; this decides how fast the
/// indicator is allowed to follow. Attack is near-instant so syllables register, and
/// release is short enough that the trail falls between words — speech syllables run
/// 150-250 ms, so anything slower reads as not responding at all.
///
/// Coefficients derive from the elapsed interval rather than being fixed per frame, so
/// the response stays the same when the sampler jitters or its rate changes.
struct AudioLevelFollower {
    private var level = 0.0

    private static let attackSeconds = 0.014
    private static let releaseSeconds = 0.11
    private static let silenceThreshold = 0.002

    mutating func reset() {
        level = 0
    }

    /// `deltaTime` must be non-negative; a negative interval would drive the level away
    /// from its target.
    mutating func follow(_ target: Double, deltaTime: TimeInterval) -> Double {
        let seconds = target > level ? Self.attackSeconds : Self.releaseSeconds
        level += (target - level) * Self.coefficient(seconds: seconds, deltaTime: deltaTime)

        if level < Self.silenceThreshold {
            level = 0
        }

        return level
    }

    private static func coefficient(seconds: TimeInterval, deltaTime: TimeInterval) -> Double {
        guard seconds > 0 else { return 1 }
        return 1 - exp(-deltaTime / seconds)
    }
}
