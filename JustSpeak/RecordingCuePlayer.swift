import AVFoundation

final class RecordingCuePlayer: NSObject, AVAudioPlayerDelegate {
    private var startSound: AVAudioPlayer?
    private var playbackCompletion: (() -> Void)?

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
        playbackCompletion = completion

        guard let startSound else {
            finishPlayback()
            return
        }

        startSound.currentTime = 0

        guard startSound.play() else {
            finishPlayback()
            return
        }
    }

    func stop() {
        startSound?.stop()
        playbackCompletion = nil
    }

    func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        finishPlayback()
    }

    func audioPlayerDecodeErrorDidOccur(
        _ player: AVAudioPlayer,
        error: Error?
    ) {
        if let error {
            print("Double Spark recording cue playback failed: \(error)")
        }

        finishPlayback()
    }

    private func finishPlayback() {
        let completion = playbackCompletion
        playbackCompletion = nil
        completion?()
    }
}
