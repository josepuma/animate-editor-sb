import Foundation

/// The area a clip's sprites occupy on the stage, and what dragging it means.
///
/// Selecting a clip should show where it is, the way a selected layer does in
/// any editor — and a box you can see is a box a hand will try to drag.
public struct ClipBounds: Sendable, Equatable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    /// The angle the clip is turned by, in radians.
    ///
    /// Carried so a frame can be drawn turned rather than grown. An
    /// axis-aligned box around a rotated sprite swells to about 1.41× at 45°
    /// and shrinks back at 90°, so a steady spin reads as the clip pulsing —
    /// the box is right about what it contains and wrong about what it is
    /// showing. Only meaningful when every sprite shares one angle; a clip
    /// whose sprites turn independently reports none, and the upright box is
    /// then the honest answer.
    public var rotation: Double = 0

    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }
    public var centreX: Double { (minX + maxX) / 2 }
    public var centreY: Double { (minY + maxY) / 2 }

    public init(
        minX: Double,
        minY: Double,
        maxX: Double,
        maxY: Double,
        rotation: Double = 0,
    ) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
        self.rotation = rotation
    }

    /// The box around a clip's sprites at one moment.
    ///
    /// Measured from the resolved states rather than from the sprites'
    /// declared positions: an emitter mid-flight covers a very different area
    /// from the point it was placed at, and a box drawn around the placement
    /// would sit nowhere near the particles it claims to contain.
    ///
    /// - Parameter sizeOf: the drawn size of a sprite's image, which only the
    ///   renderer knows. A sprite whose size is unknown still contributes its
    ///   position, so a clip never reports an empty box just because an image
    ///   is missing.
    public static func around(
        _ states: [SpriteRenderState],
        sizeOf: (String) -> (width: Double, height: Double)?,
    ) -> ClipBounds? {
        var box: ClipBounds?

        var sharedAngle: Double?
        var anglesAgree = true

        for state in states where state.visible && state.opacity > 0 {
            let size = sizeOf(state.spriteId)
            let halfWidth = abs((size?.width ?? 0) * state.scaleX) / 2
            let halfHeight = abs((size?.height ?? 0) * state.scaleY) / 2

            if let sharedAngle {
                if abs(sharedAngle - state.rotation) > 0.0001 { anglesAgree = false }
            } else {
                sharedAngle = state.rotation
            }

            // Measured upright, about each sprite's own centre. The angle is
            // reported alongside instead of being folded in, so the frame can
            // be turned to match rather than grown to cover.
            let sprite = ClipBounds(
                minX: state.x - halfWidth,
                minY: state.y - halfHeight,
                maxX: state.x + halfWidth,
                maxY: state.y + halfHeight,
            )
            box = box.map { $0.union(sprite) } ?? sprite
        }

        // Sprites turning independently — a spinning particle field — have no
        // one angle to draw, so the frame stays upright.
        if var result = box, anglesAgree, let sharedAngle {
            result.rotation = sharedAngle
            return result
        }
        return box
    }

    /// Whether a sprite belongs to a clip.
    ///
    /// An effect prefixes every sprite it makes with its node's id, so
    /// ownership is readable straight off the id — no second map to keep in
    /// step with the sprites themselves. The separator matters: without it a
    /// node whose id is a prefix of another's would claim its neighbour's
    /// particles.
    public static func sprite(_ spriteID: String, belongsTo nodeID: String) -> Bool {
        // Compared without building a joined string, because this runs once per
        // sprite per frame while a clip is selected — and allocating there is
        // paid for by every sprite in the storyboard, not just the clip's.
        guard spriteID.hasPrefix(nodeID) else { return false }
        let rest = spriteID.dropFirst(nodeID.count)
        return rest.isEmpty || rest.first == "/"
    }

    public func union(_ other: ClipBounds) -> ClipBounds {
        ClipBounds(
            minX: Swift.min(minX, other.minX),
            minY: Swift.min(minY, other.minY),
            maxX: Swift.max(maxX, other.maxX),
            maxY: Swift.max(maxY, other.maxY),
        )
    }
}
