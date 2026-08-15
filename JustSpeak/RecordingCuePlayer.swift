import AVFoundation

final class RecordingCuePlayer: NSObject, AVAudioPlayerDelegate {
    private var startSound: AVAudioPlayer?
    private var completion: (() -> Void)?

    override init() {
        super.init()

        guard let soundURL = Bundle.main.url(
            forResource: "DoubleSpark",
            withExtension: "wav"
        ) else {
            print("Double Spark recording cue is missing from the app bundle")
            return
        }

        do {
            startSound = try AVAudioPlayer(contentsOf: soundURL)
            startSound?.delegate = self
            startSound?.prepareToPlay()
        } catch {
            print("Could not load Double Spark recording cue: \(error)")
        }
    }

    func playStartCue(completion: @escaping () -> Void) {
        stop()

        guard let startSound else {
            completion()
            return
        }

        self.completion = completion
        startSound.currentTime = 0
        if !startSound.play() {
            finishPlayback()
        }
    }

    func stop() {
        completion = nil
        startSound?.stop()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        finishPlayback()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        finishPlayback()
    }

    private func finishPlayback() {
        let completion = completion
        self.completion = nil
        completion?()
    }
}
