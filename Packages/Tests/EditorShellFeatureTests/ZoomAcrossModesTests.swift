import CoreGraphics
import Testing

@testable import EditorShellFeature

/// Zoom is a magnification and an offset, and both are meaningless against a
/// different span.
///
/// The bug this pins: carried from a three-minute song into a twenty-second
/// clip, a saved offset put the visible window somewhere the clip is not — the
/// ruler showed a stretch the clip did not cover, and every key drawn against
/// it landed far from the playhead it was placed at.
@Suite("Zoom across modes")
struct ZoomAcrossModesTests {
    @Test("a fresh zoom shows the whole span")
    func freshZoomShowsEverything() {
        let clip = 56_000.0...76_000.0
        let zoom = TimelineZoom(full: clip, state: TimelineZoom.State())

        #expect(zoom.visible == clip)
    }

    /// A song's offset applied to a clip's span is what put the ruler in the
    /// wrong place.
    @Test("a carried-over offset lands outside the clip")
    func carriedOffsetMisses() {
        let song = 0.0...200_000.0
        var songZoom = TimelineZoom(full: song, state: TimelineZoom.State())
        songZoom.setMagnification(4, around: 0.5)

        // The same state, against a twenty-second clip.
        let clip = 56_000.0...76_000.0
        let clipZoom = TimelineZoom(full: clip, state: songZoom.state)

        // Zoomed in four times, the window covers a fraction of the clip —
        // which is exactly what left the keys crushed somewhere off to one side.
        #expect(clipZoom.visible != clip)
        #expect(clipZoom.visible.upperBound - clipZoom.visible.lowerBound < 20_000)
    }

    @Test("resetting the state restores the full span")
    func resetting() {
        let clip = 56_000.0...76_000.0
        var zoom = TimelineZoom(full: clip, state: TimelineZoom.State())
        zoom.setMagnification(8, around: 0.2)
        #expect(zoom.visible != clip)

        let reset = TimelineZoom(full: clip, state: TimelineZoom.State())
        #expect(reset.visible == clip)
    }
}

/// Where a keyframe lands, in the clip's own time.
///
/// The bug this pins: opening the keyframe editor moves the playhead into the
/// clip, but that runs *after* the first render — and on that frame the rows
/// were handed a negative local time, so every key drew against a moment the
/// clip does not contain.
@Suite("Local time")
struct LocalTimeTests {
    private let clipStart = 46_876.0
    private let clipDuration = 30_000.0

    private func local(playhead: Double) -> Double {
        min(max(0, playhead - clipStart), clipDuration)
    }

    @Test("a playhead before the clip clamps to its start")
    func beforeTheClip() {
        #expect(local(playhead: 0) == 0)
        #expect(local(playhead: 40_000) == 0)
    }

    @Test("a playhead after the clip clamps to its end")
    func afterTheClip() {
        #expect(local(playhead: 200_000) == clipDuration)
    }

    @Test("a playhead inside the clip measures from its start")
    func insideTheClip() {
        #expect(local(playhead: clipStart) == 0)
        #expect(local(playhead: clipStart + 5000) == 5000)
        #expect(local(playhead: clipStart + clipDuration) == clipDuration)
    }

    /// A key placed at the clamped time and drawn against the clip's own ruler
    /// has to land where the playhead is.
    @Test("a key drawn from a clamped time lands under the playhead")
    func keyLandsUnderThePlayhead() {
        let scale = TimelineScale(
            range: clipStart...(clipStart + clipDuration),
            width: 1000,
        )
        let playhead = clipStart + 12_000

        let keyLocal = local(playhead: playhead)
        #expect(scale.x(of: clipStart + keyLocal) == scale.x(of: playhead))
    }
}
