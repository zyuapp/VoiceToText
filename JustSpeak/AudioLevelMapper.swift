import Foundation

/// Maps recorder meter readings to a stable 0...1 display level.
///
/// The mapping is intentionally independent of recording duration. A recording indicator
/// should show microphone energy, not classify speech, so sustained audio must never be
/// absorbed into an adaptive noise floor.
struct AudioLevelMapper {
    private enum Constants {
        static let minimumVisibleDecibels: Float = -65
        static let loudSpeechDecibels: Float = -10
        static let peakAllowance: Float = 8
        static let responseExponent = 0.7
    }

    func map(averageDecibels: Float, peakDecibels: Float) -> Double {
        let decibels = max(averageDecibels, peakDecibels - Constants.peakAllowance)

        guard decibels.isFinite, decibels > Constants.minimumVisibleDecibels else {
            return 0
        }

        let span = Constants.loudSpeechDecibels - Constants.minimumVisibleDecibels
        let normalized = min((decibels - Constants.minimumVisibleDecibels) / span, 1)
        return pow(Double(normalized), Constants.responseExponent)
    }
}
