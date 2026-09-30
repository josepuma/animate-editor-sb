import AppKit
import SwiftUI
import Testing
@testable import EditorShellFeature
@testable import StoryboardCore

/// A keyframe row is exactly as wide as its header and its lane, however far
/// its keys sit outside what is on screen.
///
/// Reported from camera mode as the timeline "coming out": zoomed in, the
/// ruler slid off to the right and the lanes ran past the panel. The hairline
/// joining a row's keys was sized from the first key to the last — thousands
/// of points once zoomed in — and a `.frame` widens layout where an `.offset`
/// would not. One row wider than the panel made the whole column wider, and
/// the ruler above was centred on it.
@MainActor
@Suite("Keyframe row layout")
struct KeyframeRowLayoutTests {
    private func width(of track: StoryboardCore.KeyframeTrack, visible: ClosedRange<Double>) -> CGFloat {
        let row = KeyframeRow(
            title: "Camera X", track: track, nodeStart: 0,
            scale: TimelineScale(range: visible, width: 600), headerWidth: 224,
            localTime: 0, playheadNow: { 0 }, isPlaying: false,
            addKeyframe: { _ in }, moveKeyframe: { _, _ in }, removeKeyframe: { _ in },
            setEasing: { _, _ in }, setEnabled: { _ in }, clear: {},
            selectedKeyID: nil, selectKey: { _ in },
        )
        return NSHostingView(rootView: row).fittingSize.width
    }

    @Test("keys far outside the view do not widen the row")
    func farKeysKeepWidth() {
        let track = StoryboardCore.KeyframeTrack([Keyframe(time: 0, value: 0), Keyframe(time: 150_000, value: 1)])
        let whole = width(of: track, visible: 0 ... 150_000)
        let zoomed = width(of: track, visible: 12_000 ... 12_500)
        #expect(abs(zoomed - whole) < 1, "zoomed in, the row grew from \(whole) to \(zoomed) points")
    }
}
