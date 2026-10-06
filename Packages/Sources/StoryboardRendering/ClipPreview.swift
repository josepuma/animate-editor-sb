import Foundation
import StoryboardCore

/// A clip being dragged on the canvas, drawn where the drag has taken it.
///
/// Nothing reaches the document until the hand comes up — every write
/// re-evaluates the clip, so per-event writes left the picture rebuilding from
/// an edit the next event had already superseded. Until then the canvas drew
/// the clip where it was and only the selection frame followed the pointer.
///
/// This moves what is *drawn*, at draw time: a shift and a scale about the
/// clip's own position, the same pivot a committed scale grows from. It works
/// on resolved states, which already carry the storyboard camera, so it is in
/// the same screen space as the drag — no camera to account for. It costs a
/// few multiplies per sprite of one clip per frame, so it follows the hand
/// while playback is paused as well as playing.
///
/// A rotated or keyframed clip previews as a group moved and scaled; the
/// committed result is what the evaluator makes of the same numbers, and is
/// swapped in on the frame its sprites arrive.
public struct ClipPreview: Sendable, Equatable {
    public var clipID: String
    public var dx: Double
    public var dy: Double
    public var scaleX: Double
    public var scaleY: Double
    /// Degrees, clockwise on screen — the unit the transform stores.
    public var rotation: Double
    public var pivotX: Double
    public var pivotY: Double

    public init(
        clipID: String,
        dx: Double = 0,
        dy: Double = 0,
        scaleX: Double = 1,
        scaleY: Double = 1,
        rotation: Double = 0,
        pivotX: Double = 0,
        pivotY: Double = 0,
    ) {
        self.clipID = clipID
        self.dx = dx
        self.dy = dy
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.rotation = rotation
        self.pivotX = pivotX
        self.pivotY = pivotY
    }

    /// Whether a sprite belongs to the dragged clip — the same test the
    /// selection box is measured with.
    public func covers(_ spriteID: String) -> Bool {
        ClipBounds.sprite(spriteID, belongsTo: clipID)
    }

    /// Scales about the pivot, turns about it, then shifts.
    ///
    /// The turn is clockwise for a growing angle because y grows downwards —
    /// the same sense a sprite's own rotation has, so the two add.
    public func apply(to state: inout SpriteRenderState) {
        let offsetX = (state.x - pivotX) * scaleX
        let offsetY = (state.y - pivotY) * scaleY
        let angle = rotation * .pi / 180
        let c = cos(angle), s = sin(angle)
        state.x = pivotX + offsetX * c - offsetY * s + dx
        state.y = pivotY + offsetX * s + offsetY * c + dy
        state.scaleX *= scaleX
        state.scaleY *= scaleY
        state.rotation += angle
    }
}
