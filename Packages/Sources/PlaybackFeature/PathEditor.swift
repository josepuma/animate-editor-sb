import AppKit
import DesignSystem
import StoryboardCore
import StoryboardRendering
import SwiftUI

/// Draws and edits a motion path on the canvas.
///
/// A path written as numbers is a table, not a path, so this is the half of the
/// feature that makes it usable: click to place points, drag to curve them,
/// drag a point to move it. The same gestures a pen tool has anywhere else,
/// because a tool that works differently here is one that has to be learned
/// twice.
struct PathEditor: View {
    @Binding var path: MotionPath
    /// Stage size, so stage units convert to points and back.
    let stageSize: (width: Double, height: Double)
    let viewSize: CGSize
    /// Whether clicks add points, or only move the ones already there.
    let isDrawing: Bool

    @State private var dragging: Drag?
    @State private var hovered: Int?

    /// The shape being dragged, held locally until the hand comes up.
    ///
    /// Writing straight through re-evaluates the whole effect on every pixel of
    /// movement — a Magic emitter is hundreds of particles, so a drag became a
    /// slideshow. The same draft-then-commit the timeline already uses for
    /// dragging clips, and for the same reason.
    @State private var draft: MotionPath?

    /// What is drawn: the draft while a hand is down, the document otherwise.
    private var shown: MotionPath { draft ?? path }

    /// What the hand is currently holding.
    private enum Drag: Equatable {
        case point(Int)
        /// A handle, and which side of its point.
        case handle(Int, outgoing: Bool)
        /// The curve being pulled out of a point as it is placed — the drag
        /// that follows a click in every pen tool.
        case placing(Int)
    }

    private var scale: Double { viewSize.width / stageSize.width }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The catcher first, so it sits **behind** everything it must not
            // steal from. In front it took the press before a point could see
            // it, and dragging an existing point placed a new one on top of it.
            catcher
            curve
            handles
            points
        }
        .frame(width: viewSize.width, height: viewSize.height)
    }

    // ─── Drawing ─────────────────────────────────────────────────────────────

    /// The curve itself, sampled rather than described.
    ///
    /// `Path.addCurve` could draw the béziers directly and would disagree with
    /// the evaluator the moment either changed: what is drawn has to be what
    /// travels, so both read the same `position(at:)`.
    private var curve: some View {
        SwiftUI.Path { line in
            guard !shown.isEmpty else { return }
            let steps = 120
            for step in 0 ... steps {
                guard let at = shown.position(at: Double(step) / Double(steps)) else { continue }
                let point = view(at.x, at.y)
                if step == 0 { line.move(to: point) } else { line.addLine(to: point) }
            }
        }
        .stroke(Theme.Palette.accent.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        .allowsHitTesting(false)
    }

    /// The handles, as spokes out of their points.
    private var handles: some View {
        ForEach(Array(shown.points.enumerated()), id: \.offset) { index, point in
            let anchor = view(point.x, point.y)

            ForEach([true, false], id: \.self) { outgoing in
                let dx = outgoing ? point.outX : point.inX
                let dy = outgoing ? point.outY : point.inY

                if dx != 0 || dy != 0 {
                    let tip = view(point.x + dx, point.y + dy)

                    SwiftUI.Path { spoke in
                        spoke.move(to: anchor)
                        spoke.addLine(to: tip)
                    }
                    .stroke(Theme.Palette.accent.opacity(0.4), lineWidth: 1)

                    Circle()
                        .fill(Theme.Palette.accent)
                        .frame(width: 7, height: 7)
                        .position(tip)
                        .gesture(handleDrag(index: index, outgoing: outgoing))
                }
            }
        }
    }

    private var points: some View {
        ForEach(Array(shown.points.enumerated()), id: \.offset) { index, point in
            // Square, so a point reads as different from a handle without
            // needing a legend — the same distinction every vector editor makes.
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(hovered == index ? Theme.Palette.primary : Theme.Palette.accent)
                .frame(width: 9, height: 9)
                .position(view(point.x, point.y))
                .onHover { inside in
                    hovered = inside ? index : (hovered == index ? nil : hovered)
                    // The one visible sign that ⌥ does something here.
                    //
                    // A gesture nobody can see is a gesture nobody finds, and
                    // this one was chosen for consistency rather than for being
                    // obvious — so the cursor has to carry the hint that the
                    // shape of the tool no longer does.
                    if inside {
                        (NSEvent.modifierFlags.contains(.option)
                            ? NSCursor.crosshair
                            : NSCursor.openHand).set()
                    } else {
                        NSCursor.arrow.set()
                    }
                }
                .gesture(pointDrag(index: index))
                .contextMenu {
                    Button("Remove Point") { remove(index) }
                    if shown.points[index].outX != 0 || shown.points[index].outY != 0 {
                        Button("Straighten") { straighten(index) }
                    }
                }
        }
    }

    /// The surface that receives a click on empty canvas.
    ///
    /// Only while drawing: left up the rest of the time it would swallow every
    /// click meant for the clip underneath, and a tool that stays armed after
    /// it is finished is one that fights the app.
    @ViewBuilder
    private var catcher: some View {
        if isDrawing {
            Color.clear
                .contentShape(.rect)
                .gesture(placeGesture)
        }
    }

    // ─── Gestures ────────────────────────────────────────────────────────────

    /// Click to place, drag to curve.
    ///
    /// One gesture rather than a tap beside a drag: a tap gesture next to a
    /// drag holds the event while it waits to see which it is, and the delay
    /// reads as the tool being slow. `minimumDistance: 0` lets a still click
    /// reach `onEnded` as a click.
    private var placeGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if case let .placing(index) = dragging {
                    curveWhilePlacing(index: index, to: value.location)
                    return
                }

                var working = draft ?? path
                let stage = self.stage(value.startLocation)
                working.points.append(.init(x: stage.x, y: stage.y))
                draft = working
                dragging = .placing(working.points.count - 1)
                curveWhilePlacing(index: working.points.count - 1, to: value.location)
            }
            .onEnded { value in
                // A click that never moved: place the point and leave it sharp.
                if dragging == nil {
                    var working = draft ?? path
                    let stage = self.stage(value.location)
                    working.points.append(.init(x: stage.x, y: stage.y))
                    draft = working
                }
                commit()
            }
    }

    /// Pulling a curve out of a point as it is placed.
    ///
    /// Both handles move together and opposite each other, which is what keeps
    /// the curve smooth through the point. Breaking them apart is a separate
    /// gesture in every tool that offers it, and worth adding later rather than
    /// making the common case awkward now.
    private func curveWhilePlacing(index: Int, to location: CGPoint) {
        pullCurve(index: index, to: location)
    }

    /// Dragging a point moves it; ⌥-dragging pulls a curve out of it.
    ///
    /// The pen-tool convention, and taken over a more discoverable design on
    /// purpose: anyone about to draw béziers has met this gesture already, and
    /// inventing a different one here means learning it twice.
    ///
    /// It also solves a circle the first version could not escape — handles
    /// were only drawn once a point had a curve, so a straight point had
    /// nothing to grab and could never be curved after it was placed.
    private func pointDrag(index: Int) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .modifiers(.option)
            .onChanged { value in
                pullCurve(index: index, to: value.location)
            }
            .onEnded { _ in commit() }
            .exclusively(
                before: DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        var working = draft ?? path
                        guard working.points.indices.contains(index) else { return }
                        let to = stage(value.location)
                        // The handles ride along, because they are stored
                        // relative to the point — moving one without them would
                        // straighten its curve the instant it was touched.
                        working.points[index].x = to.x
                        working.points[index].y = to.y
                        draft = working
                    }
                    .onEnded { _ in commit() },
            )
    }

    /// Pulls symmetrical handles out of a point.
    ///
    /// Shared with placing, because they are the same act: a curve is a curve
    /// whether it is drawn as the point goes down or added afterwards.
    private func pullCurve(index: Int, to location: CGPoint) {
        var working = draft ?? path
        guard working.points.indices.contains(index) else { return }
        let point = working.points[index]
        let pulled = stage(location)

        let dx = pulled.x - point.x
        let dy = pulled.y - point.y

        working.points[index].outX = dx
        working.points[index].outY = dy
        working.points[index].inX = -dx
        working.points[index].inY = -dy
        draft = working
    }

    private func handleDrag(index: Int, outgoing: Bool) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                var working = draft ?? path
                guard working.points.indices.contains(index) else { return }
                let point = working.points[index]
                let to = stage(value.location)
                let dx = to.x - point.x
                let dy = to.y - point.y

                if outgoing {
                    working.points[index].outX = dx
                    working.points[index].outY = dy
                    working.points[index].inX = -dx
                    working.points[index].inY = -dy
                } else {
                    working.points[index].inX = dx
                    working.points[index].inY = dy
                    working.points[index].outX = -dx
                    working.points[index].outY = -dy
                }
                draft = working
            }
            .onEnded { _ in commit() }
    }

    /// Hands the finished shape to the document, once.
    private func commit() {
        if let draft { path = draft }
        draft = nil
        dragging = nil
    }

    /// Takes the curve back out of a point.
    ///
    /// The other half of ⌥-dragging: a gesture that only adds is one you cannot
    /// undo without deleting the point and placing it again.
    private func straighten(_ index: Int) {
        var working = draft ?? path
        guard working.points.indices.contains(index) else { return }
        working.points[index].inX = 0
        working.points[index].inY = 0
        working.points[index].outX = 0
        working.points[index].outY = 0
        path = working
        draft = nil
    }

    private func remove(_ index: Int) {
        var working = draft ?? path
        guard working.points.indices.contains(index) else { return }
        working.points.remove(at: index)
        path = working
        draft = nil
    }

    // ─── Space ───────────────────────────────────────────────────────────────

    /// Storyboard coordinates start left of the frame, not at its edge.
    ///
    /// A widescreen stage runs from −107 to 747: the 4:3 picture with a margin
    /// either side. Converting with a plain scale drew the path 107 units to
    /// the right of where the filter would put it, so the trail came out
    /// shifted by exactly that much — the right shape, the wrong place, which
    /// is what a constant offset always looks like.
    private var margin: Double { Double(OsuCanvas.offset(widescreen: isWidescreen)) }

    /// Widescreen when the stage is wider than the 4:3 picture.
    private var isWidescreen: Bool { stageSize.width > 641 }

    private func view(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: (x + margin) * scale, y: y * scale)
    }

    private func stage(_ point: CGPoint) -> (x: Double, y: Double) {
        (Double(point.x) / scale - margin, Double(point.y) / scale)
    }
}
