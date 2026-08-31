import StoryboardCore
import Testing

@testable import PlaybackFeature

/// What playback is bounded by.
///
/// Editing one clip's keyframes, playback belongs to that clip: running on past
/// its end carries the playhead somewhere the ruler no longer reaches, and
/// every property reads as whatever its last key left behind.
@MainActor
@Suite("Playback loop range")
struct LoopRangeTests {
    /// A model with a minute of timeline.
    ///
    /// Built from a sprite that spans it: with no audio the range comes from
    /// the storyboard, and an empty one leaves nothing to seek within.
    private func model() -> PlaybackModel {
        let sprite = StoryboardSprite(
            id: "s", layer: .foreground, origin: .centre,
            filePath: "a.png", defaultX: 0, defaultY: 0,
            commands: [
                Command(easing: .linear, startTime: 0, endTime: 60_000,
                        payload: .fade(start: 1, end: 1)),
            ],
        )
        let model = PlaybackModel()
        model.contentLoaded(
            name: "test",
            sprites: StoryboardResolver.prepare([sprite]),
            duration: 60_000,
            audioURL: nil,
        )
        return model
    }

    @Test("with no loop range, seeking is bounded by the timeline")
    func unbounded() {
        let model = model()

        model.seek(to: 40_000)
        #expect(model.currentTime == 40_000)
    }

    @Test("a loop range clamps seeking to itself")
    func clampsSeeking() {
        let model = model()
        model.loopRange = 10_000...20_000

        model.seek(to: 40_000)
        #expect(model.currentTime == 20_000)

        model.seek(to: 0)
        #expect(model.currentTime == 10_000)
    }

    /// The clip is what is being worked on, so playback returns to its start
    /// rather than the song's.
    @Test("playing past the range loops to its start")
    func loopsWithinTheRange() {
        let model = model()
        model.loopRange = 5000...8000
        model.seek(to: 7900)
        model.startPlayback()

        model.advance(by: 500)

        #expect(model.currentTime == 5000)
    }

    /// The bug this pins: inside the track the clock follows the audio
    /// hardware, and the bound was only checked when the *track* ran out —
    /// which never happens for a range in the middle of a song. A two-second
    /// clip looped visually while the music played straight past it.
    @Test("a range in the middle of a song still loops")
    func midSongRangeLoops() {
        let model = model()
        model.loopRange = 30_000...32_000
        model.seek(to: 31_800)
        model.startPlayback()

        model.advance(by: 400)

        #expect(model.currentTime == 30_000)
    }

    @Test("clearing the range gives the whole timeline back")
    func clearing() {
        let model = model()
        model.loopRange = 10_000...20_000
        model.seek(to: 15_000)

        model.loopRange = nil
        model.seek(to: 40_000)

        #expect(model.currentTime == 40_000)
    }
}
