import SwiftUI

/// Diagonal stripes filling a rectangle, for a region that is *derived* from
/// something next to it rather than a thing of its own.
///
/// The flat way to say "this part is different" without a gradient — the
/// convention video editors use for a clip's handles or a render's out-of-range
/// stretch. Stroke it in a colour and clip it to the shape it fills.
public struct Hatching: Shape {
    private let spacing: CGFloat

    /// - Parameter spacing: the distance between stripes, along the edge.
    public init(spacing: CGFloat) {
        self.spacing = max(spacing, 1)
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        // Lines at 45°, from beyond the left edge to past the right, so the
        // corners are covered: a stripe starting at x reaches x + height.
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return path
    }
}
