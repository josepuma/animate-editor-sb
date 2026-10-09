import Foundation

/// Which clip is under a point on the canvas.
///
/// Selecting what is plainly visible should not take a search through the
/// timeline: the picture already says where every clip is. This asks the last
/// frame drawn, front to back, and answers with the first clip whose sprite
/// covers the point.
///
/// A sprite is hit where it is *seen*: its image's alpha at the pointer, times
/// how opaque the sprite is right now, has to clear `visibleAlpha`. Testing
/// the box instead made a glow, or a PNG with a wide clear margin, a wall in
/// front of everything that showed through it. A sprite whose image is
/// unknown — a missing file, drawn as a flat quad — falls back to its box,
/// which is exactly what it draws.
public enum CanvasHitTest {
    /// One drawn sprite: where it is, and the size of its image.
    public struct Candidate: Sendable {
        public var state: SpriteRenderState
        public var width: Double
        public var height: Double
        public var origin: Origin
        /// The image's transparency, or `nil` to test the box.
        public var mask: AlphaMask?

        public init(
            state: SpriteRenderState,
            width: Double,
            height: Double,
            origin: Origin,
            mask: AlphaMask? = nil,
        ) {
            self.state = state
            self.width = width
            self.height = height
            self.origin = origin
            self.mask = mask
        }
    }

    /// How opaque a pixel has to look to catch the pointer.
    ///
    /// Low on purpose: a soft glow's faint body is still the glow someone is
    /// pointing at. What it rules out is the clear margin around an image and
    /// a sprite faded all but out.
    public static let visibleAlpha = 0.08

    /// The topmost clip under `point`, in stage units.
    ///
    /// - Parameters:
    ///   - candidates: in draw order, back to front — the order the renderer
    ///     drew them, so the last one is on top.
    ///   - owner: the clip a sprite belongs to, or `nil` when it cannot be
    ///     selected from the canvas — a locked or hidden lane, or a sprite from
    ///     an imported storyboard. Those are clicked through, to whatever is
    ///     drawn behind them.
    public static func clip(
        at point: (x: Double, y: Double),
        in candidates: [Candidate],
        owner: (String) -> String?,
    ) -> String? {
        for candidate in candidates.reversed() {
            let state = candidate.state
            guard state.visible, state.opacity > 0 else { continue }
            guard isSeen(candidate, at: point) else { continue }
            if let clip = owner(state.spriteId) { return clip }
        }
        return nil
    }
}

extension CanvasHitTest {
    static func isSeen(_ candidate: Candidate, at point: (x: Double, y: Double)) -> Bool {
        let state = candidate.state
        guard let mask = candidate.mask else {
            guard let box = ClipBounds.around(
                [state],
                sizeOf: { _ in (width: candidate.width, height: candidate.height) },
                originOf: { _ in candidate.origin },
            ) else { return false }
            return box.contains(point)
        }
        guard let uv = textureCoordinate(of: point, on: candidate) else { return false }
        return mask.alpha(u: uv.u, v: uv.v) * state.opacity >= visibleAlpha
    }

    /// Where on its image a sprite is drawn at a point, or `nil` when the
    /// point is off it.
    ///
    /// The sprite vertex shader run backwards: it scales a −1…1 quad by the
    /// half-extent (signed, which is how a flip mirrors in place), shifts it
    /// by the anchor offset (unsigned), turns it, and moves it to the
    /// position. Undone in the opposite order, a point lands back in the quad.
    static func textureCoordinate(
        of point: (x: Double, y: Double),
        on candidate: Candidate,
    ) -> (u: Double, v: Double)? {
        let state = candidate.state
        let halfX = candidate.width * state.scaleX * 0.5 * (state.flipH ? -1 : 1)
        let halfY = candidate.height * state.scaleY * 0.5 * (state.flipV ? -1 : 1)
        guard halfX != 0, halfY != 0 else { return nil }

        let dx = point.x - state.x
        let dy = point.y - state.y
        let c = cos(state.rotation)
        let s = sin(state.rotation)
        // The inverse turn: the shader's rotation matrix, transposed.
        var localX = dx * c + dy * s
        var localY = -dx * s + dy * c

        let anchor = candidate.origin.anchor
        localX -= (0.5 - Double(anchor.x)) * 2 * abs(halfX)
        localY -= (0.5 - Double(anchor.y)) * 2 * abs(halfY)

        let u = (localX / halfX + 1) / 2
        let v = (localY / halfY + 1) / 2
        guard u >= 0, u <= 1, v >= 0, v <= 1 else { return nil }
        return (u, v)
    }
}

public extension ClipBounds {
    /// Whether a point lies inside the box as it is drawn — turned about its
    /// centre by `rotation`, the way the selection frame is.
    func contains(_ point: (x: Double, y: Double)) -> Bool {
        // Turned back into the box's own axes, then compared upright.
        let dx = point.x - centreX
        let dy = point.y - centreY
        let c = cos(-rotation)
        let s = sin(-rotation)
        let x = centreX + dx * c - dy * s
        let y = centreY + dx * s + dy * c
        return x >= minX && x <= maxX && y >= minY && y <= maxY
    }
}
