import AppKit
import DesignSystem
import StoryboardCore
import StoryboardRendering
import SwiftUI

/// The storyboard camera, handled on the canvas.
///
/// The canvas shows the world **unmoved** while this is up, and the camera's
/// frame is drawn over it — what After Effects does with a top view beside the
/// active camera. That is what makes the camera something you point rather
/// than a column of numbers: you see what will be in the shot and what will
/// fall outside it.
///
/// - Drag inside the frame to pan.
/// - Drag a corner to zoom: a bigger frame is a wider shot.
/// - Drag the handle above the frame to roll; hold ⇧ to step by 15°.
/// - The path of the camera's position keys is drawn through the world, and a
///   point on it can be dragged to move where the camera stands at that key.
///
/// The frame is the shot of the lane at Z 0 — the one a camera at rest shows
/// as it is. Lanes set farther or nearer see a larger or smaller patch of
/// their own plane, which is what parallax is.
///
/// A drag holds a draft and commits once, on release — the same pattern the
/// path editor and the timeline use, for the same reason: writing through on
/// every pixel re-evaluates on every pixel.
struct CameraFrameEditor: View {
    /// Read for the clock and the stage format. The clock is read **here**, in
    /// this small view, so the frame follows the playhead without the canvas
    /// around it rebuilding sixty times a second.
    let model: PlaybackModel
    /// The camera, or `nil` when it is not being edited — asked for on demand,
    /// like every other seam into the shell on this canvas.
    let camera: () -> StoryboardCamera?
    let viewSize: CGSize
    /// A finished frame drag: where the camera looks, how close, and its roll.
    let onFrame: (_ x: Double, _ y: Double, _ zoom: Double, _ rotation: Double) -> Void
    /// A finished drag of a path point: the key's time and its new place.
    let onPathPoint: (_ time: Double, _ x: Double, _ y: Double) -> Void

    /// The shot while a hand is on it.
    @State private var draft: Shot?
    /// The shot as it was when the drag began — translations are measured
    /// from here, never from the previous event.
    @State private var origin: Shot?
    /// A path point being dragged.
    @State private var pointDraft: (time: Double, x: Double, y: Double)?

    private struct Shot: Equatable {
        var x: Double
        var y: Double
        var zoom: Double
        var rotation: Double
    }

    var body: some View {
        if let camera = camera() {
            let time = model.currentTime
            let shot = draft ?? Shot(
                x: camera.value(.x, at: time),
                y: camera.value(.y, at: time),
                zoom: camera.value(.zoom, at: time),
                rotation: camera.value(.rotation, at: time),
            )
            let corners = self.corners(of: shot, camera: camera, at: time)
            let centre = view(shot.x, shot.y)

            ZStack(alignment: .topLeading) {
                outside(corners)
                path(camera)
                interior(corners, centre: centre, shot: shot)
                label(corners, shot: shot)
                rollHandle(corners, centre: centre, shot: shot, camera: camera, time: time)
                cornerHandles(corners, centre: centre, shot: shot, camera: camera, time: time)
                pathPoints(camera)
            }
            .frame(width: viewSize.width, height: viewSize.height)
            .clipped()
        }
    }

    // ─── Drawing ─────────────────────────────────────────────────────────────

    /// Everything outside the shot, dimmed: the part of the world the game
    /// will not show. Cut with even-odd rather than a blend mode, which does
    /// nothing unless a compositing group wraps both shapes.
    private func outside(_ corners: [CGPoint]) -> some View {
        SwiftUI.Path { area in
            area.addRect(CGRect(origin: .zero, size: viewSize))
            area.addLines(corners)
            area.closeSubpath()
        }
        .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)
    }

    /// The frame itself, which is also what a pan drags.
    private func interior(_ corners: [CGPoint], centre: CGPoint, shot: Shot) -> some View {
        let outline = FrameOutline(points: corners)
        return ZStack {
            outline
                .fill(Color.clear)
                .contentShape(outline)
            outline
                .stroke(Theme.Palette.selection, lineWidth: 1.5)
                .allowsHitTesting(false)
            // The point the camera looks at.
            Image(systemName: "plus")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.selection)
                .position(centre)
                .allowsHitTesting(false)
        }
        .onHover { inside in
            if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let start = origin ?? shot
                    if origin == nil { origin = shot }
                    // Moving the frame right is looking right: the shot
                    // follows the hand across the world, however it is turned.
                    var moved = start
                    moved.x += Double(value.translation.width) / scale
                    moved.y += Double(value.translation.height) / scale
                    draft = moved
                }
                .onEnded { _ in commit() },
        )
    }

    /// How close the camera is and how it is turned, where the eye already is.
    private func label(_ corners: [CGPoint], shot: Shot) -> some View {
        let text = shot.rotation == 0
            ? String(format: "Camera  ×%.2f", shot.zoom)
            : String(format: "Camera  ×%.2f  %.0f°", shot.zoom, shot.rotation)
        return Text(text)
            .font(Theme.Typography.micro)
            .foregroundStyle(Theme.Palette.selection)
            .fixedSize()
            .padding(.horizontal, Theme.Spacing.tight)
            // Kept on the canvas: a rolled or zoomed-out frame puts its top
            // left corner off the edge, and the label went with it — the one
            // readout that says what the frame is doing, gone exactly when the
            // frame is doing something.
            .position(
                x: min(max(corners[0].x + 60, 70), viewSize.width - 70),
                y: min(max(corners[0].y - Theme.Spacing.compact, Theme.Spacing.compact), viewSize.height - Theme.Spacing.compact),
            )
            .allowsHitTesting(false)
    }

    /// A handle on every corner; dragging one zooms about the frame's centre.
    private func cornerHandles(
        _ corners: [CGPoint], centre: CGPoint, shot: Shot, camera: StoryboardCamera, time: Double,
    ) -> some View {
        ForEach(corners.indices, id: \.self) { index in
            Rectangle()
                .fill(Theme.Palette.selection)
                .frame(width: 9, height: 9)
                // A grab area bigger than the square, so the corner is found
                // without aiming at a nine-point target.
                .padding(5)
                .contentShape(.rect)
                .position(corners[index])
                .onHover { inside in
                    if inside { NSCursor.crosshair.push() } else { NSCursor.pop() }
                }
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            let start = origin ?? shot
                            if origin == nil { origin = shot }
                            let startCorner = self.corners(of: start, camera: camera, at: time)[index]
                            let reach = hypot(startCorner.x - centre.x, startCorner.y - centre.y)
                            let now = hypot(value.location.x - centre.x, value.location.y - centre.y)
                            guard now > 4, reach > 0 else { return }
                            // A frame pulled larger is a wider shot, so the
                            // zoom goes down as the corner goes out.
                            var zoomed = start
                            zoomed.zoom = min(max(start.zoom * Double(reach / now), CameraProperty.zoom.range.lowerBound),
                                              CameraProperty.zoom.range.upperBound)
                            draft = zoomed
                        }
                        .onEnded { _ in commit() },
                )
        }
    }

    /// The roll handle, standing off the middle of the frame's top edge — where
    /// every editor puts the one that turns a selection.
    private func rollHandle(
        _ corners: [CGPoint], centre: CGPoint, shot: Shot, camera: StoryboardCamera, time: Double,
    ) -> some View {
        let top = CGPoint(x: (corners[0].x + corners[1].x) / 2, y: (corners[0].y + corners[1].y) / 2)
        let outward = CGVector(dx: top.x - centre.x, dy: top.y - centre.y)
        let length = max(hypot(outward.dx, outward.dy), 1)
        let knob = CGPoint(x: top.x + outward.dx / length * 22, y: top.y + outward.dy / length * 22)

        return ZStack {
            SwiftUI.Path { stem in
                stem.move(to: top)
                stem.addLine(to: knob)
            }
            .stroke(Theme.Palette.selection, lineWidth: 1)
            .allowsHitTesting(false)

            Circle()
                .fill(Theme.Palette.selection)
                .frame(width: 10, height: 10)
                .padding(5)
                .contentShape(Circle())
                .position(knob)
                .help("Drag to roll the camera — hold ⇧ for 15° steps")
                .onHover { inside in
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            let start = origin ?? shot
                            if origin == nil { origin = shot }
                            let from = atan2(value.startLocation.y - centre.y, value.startLocation.x - centre.x)
                            let to = atan2(value.location.y - centre.y, value.location.x - centre.x)
                            // Wrapped into half a turn either way, so crossing
                            // the back of the circle does not jump a full turn.
                            var delta = Double(to - from)
                            if delta > .pi { delta -= 2 * .pi }
                            if delta < -.pi { delta += 2 * .pi }
                            // On screen, y grows downward, so a clockwise drag
                            // is a growing angle — and a clockwise roll.
                            var rolled = start.rotation + delta * 180 / .pi
                            if NSEvent.modifierFlags.contains(.shift) {
                                rolled = (rolled / 15).rounded() * 15
                            }
                            var turned = start
                            turned.rotation = min(max(rolled, CameraProperty.rotation.range.lowerBound),
                                                  CameraProperty.rotation.range.upperBound)
                            draft = turned
                        }
                        .onEnded { _ in commit() },
                )
        }
    }

    /// The camera's route through the world, sampled from the same values the
    /// bake reads so the line is where the camera will go.
    private func path(_ camera: StoryboardCamera) -> some View {
        let keys = camera.pathPoints
        return SwiftUI.Path { line in
            guard let first = keys.first, let last = keys.last, last.time > first.time else { return }
            let steps = 120
            for step in 0 ... steps {
                let time = first.time + (last.time - first.time) * Double(step) / Double(steps)
                let point = view(camera.value(.x, at: time), camera.value(.y, at: time))
                if step == 0 { line.move(to: point) } else { line.addLine(to: point) }
            }
        }
        .stroke(Theme.Palette.selection.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        .allowsHitTesting(false)
    }

    /// One square per position key, draggable.
    private func pathPoints(_ camera: StoryboardCamera) -> some View {
        let keys = camera.pathPoints
        return ForEach(keys.indices, id: \.self) { index in
            let key = keys[index]
            let shown = pointDraft?.time == key.time ? (pointDraft!.x, pointDraft!.y) : (key.x, key.y)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Theme.Palette.primary)
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(Theme.Palette.selection, lineWidth: 1.5),
                )
                .frame(width: 9, height: 9)
                .padding(4)
                .contentShape(.rect)
                .position(view(shown.0, shown.1))
                .help("Camera key at \(Int(key.time)) ms")
                .onHover { inside in
                    if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
                }
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            let to = stage(value.location)
                            pointDraft = (key.time, to.x, to.y)
                        }
                        .onEnded { _ in
                            defer { pointDraft = nil }
                            guard let pointDraft else { return }
                            onPathPoint(pointDraft.time, pointDraft.x, pointDraft.y)
                        },
                )
        }
    }

    // ─── Committing ──────────────────────────────────────────────────────────

    private func commit() {
        defer {
            draft = nil
            origin = nil
        }
        guard let draft, draft != origin else { return }
        onFrame(draft.x, draft.y, draft.zoom, draft.rotation)
    }

    // ─── Space ───────────────────────────────────────────────────────────────

    /// The stage's size in storyboard units.
    private var stageWidth: Double { Double(OsuCanvas.size(widescreen: model.isWidescreen).width) }

    /// Storyboard coordinates start left of the frame on a widescreen stage:
    /// −107 to 747. A plain scale puts everything 107 units off — the trap the
    /// path editor already fell into once.
    private var margin: Double { Double(OsuCanvas.offset(widescreen: model.isWidescreen)) }

    private var scale: Double { Double(viewSize.width) / stageWidth }

    private func view(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: (x + margin) * scale, y: y * scale)
    }

    private func stage(_ point: CGPoint) -> (x: Double, y: Double) {
        (Double(point.x) / scale - margin, Double(point.y) / scale)
    }

    /// The shot's four corners on the canvas, clockwise from the top left.
    ///
    /// From the camera's own `frame(at:)` — the inverse of the bake — with the
    /// shot's pan, zoom and roll laid over the camera's depth and lens at this
    /// moment, so a frame drawn mid-dolly is the frame the dolly produces.
    private func corners(of shot: Shot, camera: StoryboardCamera, at time: Double) -> [CGPoint] {
        var lens = StoryboardCamera()
        lens[value: .x] = shot.x
        lens[value: .y] = shot.y
        lens[value: .zoom] = shot.zoom
        lens[value: .rotation] = shot.rotation
        lens[value: .z] = camera.value(.z, at: time)
        lens[value: .focal] = camera.value(.focal, at: time)
        return lens.frame(at: 0, stage: -margin ... (stageWidth - margin)).corners.map { view($0.x, $0.y) }
    }
}

/// The frame's outline, as a shape — so the same four points draw the stroke
/// and decide where a press counts as inside.
private struct FrameOutline: Shape {
    let points: [CGPoint]

    func path(in _: CGRect) -> SwiftUI.Path {
        SwiftUI.Path { outline in
            outline.addLines(points)
            outline.closeSubpath()
        }
    }
}
