import Foundation
import StoryboardCore
import Testing

@testable import EditorShellFeature

/// What a dragged clip can line up with, besides the beat.
@Suite("Timeline snap anchors")
@MainActor
struct TimelineSnapAnchorTests {
    @Test("other clips' edges and the playhead are anchors")
    func collectsEdgesAndPlayhead() {
        let shell = EditorShellModel()
        let dragged = shell.addEffect(ShapeEffect.descriptor, at: 0, duration: 1000)
        let other = shell.addEffect(ShapeEffect.descriptor, at: 3000, duration: 500)
        shell.playheadTime = 1750

        let anchors = shell.timelineSnapAnchors(excluding: dragged.id)

        #expect(anchors.contains(other.startTime))
        #expect(anchors.contains(other.startTime + other.duration))
        #expect(anchors.contains(1750))
    }

    /// A clip snapping to its own edges would stick to wherever it started,
    /// and every drag would feel like pulling it off a magnet.
    @Test("the dragged clip is not its own anchor")
    func excludesTheDraggedClip() {
        let shell = EditorShellModel()
        let dragged = shell.addEffect(ShapeEffect.descriptor, at: 400, duration: 1000)
        shell.playheadTime = 9000

        let anchors = shell.timelineSnapAnchors(excluding: dragged.id)

        #expect(!anchors.contains(400))
        #expect(!anchors.contains(1400))
    }

    /// Lanes are separate in the view, not in time: a clip on another lane is
    /// exactly what a hit on this one lines up against.
    @Test("clips on other lanes count")
    func otherLanesCount() {
        let shell = EditorShellModel()
        let dragged = shell.addEffect(ShapeEffect.descriptor, at: 0, duration: 1000)
        let lane = shell.addTrack(at: 0)
        let other = shell.addEffect(ShapeEffect.descriptor, at: 2500, duration: 500, on: lane.id)

        let anchors = shell.timelineSnapAnchors(excluding: dragged.id)

        #expect(anchors.contains(other.startTime))
    }
}
