import Foundation
import Testing

@testable import StoryboardPersistence

/// Playback speed is a multiple of the track's own tempo.
@Suite("Audio rate")
struct AudioRateTests {
    @Test("a fresh player runs at normal speed")
    func defaultsToOne() {
        #expect(AudioPlayer().rate == 1)
    }

    @Test("the rate is kept")
    func roundTrips() {
        let player = AudioPlayer()
        player.rate = 0.5
        #expect(player.rate == 0.5)
    }

    /// Clamped rather than refused: a rate far outside the useful range turns
    /// the song into an artefact instead of a reference.
    @Test("an absurd rate is clamped, not refused", arguments: [
        (Float(0.01), AudioPlayer.minimumRate),
        (Float(-4), AudioPlayer.minimumRate),
        (Float(64), AudioPlayer.maximumRate),
    ])
    func clampsOutOfRange(asked: Float, expected: Float) {
        let player = AudioPlayer()
        player.rate = asked
        #expect(player.rate == expected, "asked \(asked), got \(player.rate)")
    }

    /// The bounds have to leave room for the speeds the menu offers, or the
    /// UI would list a rate the player refuses to take.
    @Test("the menu's speeds all fit")
    func boundsCoverTheMenu() {
        #expect(AudioPlayer.minimumRate <= 0.25)
        #expect(AudioPlayer.maximumRate >= 2)
    }
}
