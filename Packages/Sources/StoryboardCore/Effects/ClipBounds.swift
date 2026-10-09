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
    /// - Parameter originOf: where the sprite's image hangs off its position.
    ///   Defaults to `.centre`, which is what this assumed before it asked —
    ///   and what nine origins out of ten are not.
    public static func around(
        _ states: [SpriteRenderState],
        sizeOf: (String) -> (width: Double, height: Double)?,
        originOf: (String) -> Origin = { _ in .centre },
    ) -> ClipBounds? {
        var box: ClipBounds?

        for state in states where state.visible && state.opacity > 0 {
            let size = sizeOf(state.spriteId)
            let halfWidth = abs((size?.width ?? 0) * state.scaleX) / 2
            let halfHeight = abs((size?.height ?? 0) * state.scaleY) / 2

            // The anchor decides where the image hangs off the position, and
            // this used to assume the middle. A `CentreLeft` sprite draws to
            // the *right* of its position, so a box centred on it sat a half
            // width to the left of the picture — the frame beside the sprite
            // rather than around it.
            //
            // Same expression the vertex shader uses, so the two cannot drift:
            // `(0.5 - anchor) * 2 * halfSize`.
            //
            // The half-extent is UNSIGNED here on purpose. osu! flips a sprite
            // in place — the box stays where origin plus position put it and
            // only the pixels inside are mirrored. Folding the flip into this
            // offset (as the renderer once did) swung a `TopCentre` bar at
            // y=480 upward into the frame, where osu! leaves it hanging off
            // the bottom edge, invisible.
            let anchor = originOf(state.spriteId).anchor
            let offsetX = (0.5 - Double(anchor.x)) * 2 * halfWidth
            let offsetY = (0.5 - Double(anchor.y)) * 2 * halfHeight

            // Turned with the sprite, because osu! turns a sprite about its
            // origin, not its centre. Left upright, a stretched `TopLeft` bar
            // turned 16° had its frame tens of pixels off the picture.
            let c = cos(state.rotation), s = sin(state.rotation)
            let centreX = state.x + offsetX * c - offsetY * s
            let centreY = state.y + offsetX * s + offsetY * c

            // The sprite's own extent, about its centre, with its angle — so
            // the frame can be turned to match rather than grown to cover.
            let sprite = ClipBounds(
                minX: centreX - halfWidth,
                minY: centreY - halfHeight,
                maxX: centreX + halfWidth,
                maxY: centreY + halfHeight,
                rotation: state.rotation,
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
        // Compared without building a joined string, because this runs once per
        // sprite per frame while a clip is selected — and allocating there is
        // paid for by every sprite in the storyboard, not just the clip's.
        guard spriteID.hasPrefix(nodeID) else { return false }
        let rest = spriteID.dropFirst(nodeID.count)
        return rest.isEmpty || rest.first == "/"
    }

    /// Whether a sprite belongs to any clip of a group selection.
    ///
    /// A few clips are tried one by one, which allocates nothing. Past that —
    /// a select-all is every clip in the project — each sprite would be
    /// compared against all of them every frame, so the id is cut at each
    /// separator instead and the pieces looked up: a few lookups per sprite
    /// however large the group.
    public static func sprite(_ spriteID: String, belongsToAnyOf nodeIDs: Set<String>) -> Bool {
        if nodeIDs.count <= smallGroup {
            return nodeIDs.contains { sprite(spriteID, belongsTo: $0) }
        }
        if nodeIDs.contains(spriteID) { return true }
        var index = spriteID.startIndex
        while let slash = spriteID[index...].firstIndex(of: "/") {
            if nodeIDs.contains(String(spriteID[..<slash])) { return true }
            index = spriteID.index(after: slash)
        }
        return false
    }

    /// Up to this many clips, comparing against each beats cutting the id.
    private static let smallGroup = 8

    /// The box around both.
    ///
    /// Two boxes turned alike are joined in their own axes and stay turned —
    /// two bars end to end along a slanted line are one long slanted frame.
    /// Turned differently, there is no one angle to draw: the result is the
    /// upright box around both boxes' turned corners. A spinning particle
    /// field gets that, and it is the honest answer.
    ///
    /// The angle used to be dropped here outright, and the upright extents
    /// joined as if nothing were turned.
    public func union(_ other: ClipBounds) -> ClipBounds {
        if abs(rotation - other.rotation) < Self.sameAngle {
            let a = local(), b = other.local()
            let minU = Swift.min(a.minU, b.minU), maxU = Swift.max(a.maxU, b.maxU)
            let minV = Swift.min(a.minV, b.minV), maxV = Swift.max(a.maxV, b.maxV)
            // The centre goes back to the stage; the extent stays in the
            // turned axes.
            let u = (minU + maxU) / 2, v = (minV + maxV) / 2
            let c = cos(rotation), s = sin(rotation)
            let x = u * c - v * s, y = u * s + v * c
            let halfWidth = (maxU - minU) / 2, halfHeight = (maxV - minV) / 2
            return ClipBounds(
                minX: x - halfWidth, minY: y - halfHeight,
                maxX: x + halfWidth, maxY: y + halfHeight,
                rotation: rotation,
            )
        }
        let corners = self.corners() + other.corners()
        return ClipBounds(
            minX: corners.map(\.x).min()!, minY: corners.map(\.y).min()!,
            maxX: corners.map(\.x).max()!, maxY: corners.map(\.y).max()!,
        )
    }

    /// Angles closer than this are one angle.
    private static let sameAngle = 0.0001

    /// The extent in the box's own turned axes.
    private func local() -> (minU: Double, maxU: Double, minV: Double, maxV: Double) {
        let c = cos(rotation), s = sin(rotation)
        let u = centreX * c + centreY * s
        let v = -centreX * s + centreY * c
        return (u - width / 2, u + width / 2, v - height / 2, v + height / 2)
    }

    /// The four corners on the stage, turned about the centre.
    private func corners() -> [(x: Double, y: Double)] {
        let c = cos(rotation), s = sin(rotation)
        return [(-1.0, -1.0), (1, -1), (1, 1), (-1, 1)].map { sx, sy in
            let dx = sx * width / 2, dy = sy * height / 2
            return (centreX + dx * c - dy * s, centreY + dx * s + dy * c)
        }
    }
}
