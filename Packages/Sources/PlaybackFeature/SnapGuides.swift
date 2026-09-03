import DesignSystem
import StoryboardCore
import SwiftUI

/// The stage lines a dragged clip has caught.
///
/// Drawn only while a snap is active, and only for the axis that caught: a
/// guide that stays up says the clip is still held there, and one that appears
/// on an axis nothing snapped to says the wrong thing entirely.
///
/// Separate from `SelectionBox` because these run the full width and height of
/// the stage while the box is only as large as its clip.
struct SnapGuides: View {
    /// The vertical line the clip caught, in storyboard coordinates.
    let x: Double?
    /// The horizontal one.
    let y: Double?
    /// Whether the stage's centre lines are shown all the time.
    ///
    /// Different from a snap guide and drawn differently: a standing guide says
    /// *where the middle is*, a snap guide says *what this clip caught*. Drawn
    /// alike, the second is invisible the moment it lands on the first — which
    /// is exactly when it matters most.
    var showsCentre = false
    let stageSize: (width: Double, height: Double)
    let viewSize: CGSize

    /// Points per stage unit.
    private var scale: Double { viewSize.width / stageSize.width }

    /// Storyboard x to a point in the view.
    ///
    /// The wide stage starts at −107, so the origin has to be subtracted before
    /// scaling: a plain multiply puts every guide 107 units to the right of the
    /// line it names — which is exactly how a constant offset looks, and the
    /// same trap the path editor fell into.
    private func point(x storyboardX: Double) -> Double {
        (storyboardX - StageSnap.Stage.minX) * scale
    }

    private func point(y storyboardY: Double) -> Double {
        storyboardY * scale
    }

    var body: some View {
        Canvas { context, size in
            if showsCentre {
                var centre = Path()
                let midX = point(x: StageSnap.Stage.centreX)
                let midY = point(y: StageSnap.Stage.centreY)
                centre.move(to: CGPoint(x: midX, y: 0))
                centre.addLine(to: CGPoint(x: midX, y: size.height))
                centre.move(to: CGPoint(x: 0, y: midY))
                centre.addLine(to: CGPoint(x: size.width, y: midY))

                // Faint and solid, against the snap guide's bright dashes: this
                // one is scenery, and it sits over artwork the whole time.
                context.stroke(
                    centre,
                    with: .color(Theme.Palette.primary.opacity(0.25)),
                    lineWidth: 1,
                )
            }

            var path = Path()

            if let x {
                let at = point(x: x)
                path.move(to: CGPoint(x: at, y: 0))
                path.addLine(to: CGPoint(x: at, y: size.height))
            }
            if let y {
                let at = point(y: y)
                path.move(to: CGPoint(x: 0, y: at))
                path.addLine(to: CGPoint(x: size.width, y: at))
            }

            context.stroke(
                path,
                with: .color(Theme.Palette.accent),
                // Hairline and dashed, the way every editor draws one: a guide
                // has to be visible against arbitrary artwork without becoming
                // part of the picture.
                style: StrokeStyle(lineWidth: 1, dash: [4, 4]),
            )
        }
        .allowsHitTesting(false)
    }
}
