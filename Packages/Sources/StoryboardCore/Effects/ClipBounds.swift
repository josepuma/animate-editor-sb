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

    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }
    public var centreX: Double { (minX + maxX) / 2 }
    public var centreY: Double { (minY + maxY) / 2 }

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
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

        for state in states where state.visible && state.opacity > 0 {
            let size = sizeOf(state.spriteId)
            let halfWidth = abs((size?.width ?? 0) * state.scaleX) / 2
            let halfHeight = abs((size?.height ?? 0) * state.scaleY) / 2

            // Rotation is folded in by taking the extent of the rotated
            // rectangle, so a spinning sprite is contained at every angle
            // rather than only at zero.
            let cosine = abs(cos(state.rotation))
            let sine = abs(sin(state.rotation))
            let reachX = halfWidth * cosine + halfHeight * sine
            let reachY = halfWidth * sine + halfHeight * cosine

            let sprite = ClipBounds(
                minX: state.x - reachX,
                minY: state.y - reachY,
                maxX: state.x + reachX,
                maxY: state.y + reachY,
            )
            box = box.map { $0.union(sprite) } ?? sprite
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
        spriteID == nodeID || spriteID.hasPrefix(nodeID + "/")
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
