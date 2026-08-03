import AVFoundation

final class RecordingCuePlayer {
    private var startSound: AVAudioPlayer?

    init() {
        guard let soundURL = Bundle.main.url(
            forResource: "DoubleSpark",
            withExtension: "wav"
        ) else {
            print("Double Spark recording cue is missing from the app bundle")
            return
        }

        do {
            startSound = try AVAudioPlayer(contentsOf: soundURL)
            startSound?.prepareToPlay()
        } catch {
            print("Could not load Double Spark recording cue: \(error)")
        }
    }

    func playStartCue() {
        stop()

        guard let startSound else { return }

        startSound.currentTime = 0
        startSound.play()
    }

    func stop() {
        startSound?.stop()
    }
}
