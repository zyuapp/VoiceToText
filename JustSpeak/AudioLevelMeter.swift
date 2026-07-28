import Foundation

/// Turns `AVAudioRecorder` meter readings into a 0...1 level that tracks speech syllables.
///
/// The decibel window floats instead of being fixed: the floor follows the quietest recent
/// frames and the ceiling follows the loudest, so a quiet headset and a hot desk mic both
/// use the full range. Attack is near-instant; release is slow enough to read as motion
/// rather than flicker.
struct AudioLevelMeter {
    private var floorDecibels = Self.restingFloor
    private var ceilingDecibels = Self.restingCeiling
    private var smoothedLevel = 0.0

    private static let restingFloor: Float = -46
    private static let restingCeiling: Float = -24
    private static let silenceDecibels: Float = -54
    private static let minimumWindow: Float = 10
    private static let peakWeight: Float = 0.62

    private static let attackSeconds = 0.014
    private static let releaseSeconds = 0.11
    private static let floorFallSeconds = 0.6
    private static let floorRiseSeconds = 30.0
    private static let ceilingFallSeconds = 2.5

    mutating func reset() {
        floorDecibels = Self.restingFloor
        ceilingDecibels = Self.restingCeiling
        smoothedLevel = 0
    }

    mutating func update(
        peakDecibels: Float,
        averageDecibels: Float,
        deltaTime: TimeInterval
    ) -> Double {
        let decibels = Self.peakWeight * peakDecibels + (1 - Self.peakWeight) * averageDecibels
        trackWindow(decibels: decibels, deltaTime: deltaTime)

        let target = decibels <= Self.silenceDecibels ? 0 : normalize(decibels)
        let seconds = target > smoothedLevel ? Self.attackSeconds : Self.releaseSeconds
        smoothedLevel += (target - smoothedLevel) * Self.coefficient(seconds: seconds, deltaTime: deltaTime)

        if smoothedLevel < 0.002 {
            smoothedLevel = 0
        }

        return smoothedLevel
    }

    /// Falls quickly to a new noise floor but climbs back only over tens of seconds, so a
    /// long utterance cannot drag the floor up into the middle of the speech itself.
    private mutating func trackWindow(decibels: Float, deltaTime: TimeInterval) {
        let seconds = decibels < floorDecibels ? Self.floorFallSeconds : Self.floorRiseSeconds
        let floorTarget = max(decibels, Self.silenceDecibels)
        floorDecibels += (floorTarget - floorDecibels)
            * Float(Self.coefficient(seconds: seconds, deltaTime: deltaTime))

        if decibels > ceilingDecibels {
            ceilingDecibels = decibels
        } else {
            ceilingDecibels += (decibels - ceilingDecibels)
                * Float(Self.coefficient(seconds: Self.ceilingFallSeconds, deltaTime: deltaTime))
        }

        ceilingDecibels = max(
            ceilingDecibels,
            floorDecibels + Self.minimumWindow,
            Self.restingCeiling
        )
    }

    private func normalize(_ decibels: Float) -> Double {
        let span = max(ceilingDecibels - floorDecibels, Self.minimumWindow)
        let normalized = Double((decibels - floorDecibels) / span)
        return pow(min(max(normalized, 0), 1), 0.72)
    }

    private static func coefficient(seconds: TimeInterval, deltaTime: TimeInterval) -> Double {
        guard seconds > 0 else { return 1 }
        return 1 - exp(-deltaTime / seconds)
    }
}
