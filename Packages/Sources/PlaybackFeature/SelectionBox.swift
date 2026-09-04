import AppKit
import DesignSystem
import Foundation
import StoryboardCore
import StoryboardRendering
import SwiftUI

/// What a drag on the selection box is asking for, in stage coordinates.
///
/// Deltas rather than absolute values: the box reports the change, and whoever
/// owns the clip decides what that means for its transform — which is where the
/// resting-value-or-keyframe rule already lives.
public struct ClipDrag: Sendable, Equatable {
    /// Movement across the stage.
    public var dx: Double = 0
    public var dy: Double = 0
    /// Multipliers on the clip's current scale. A corner drives both together;
    /// a side drives one, which is what stretching means.
    public var scaleX: Double = 1
    public var scaleY: Double = 1

    /// Whether this came from a side handle rather than a corner.
    ///
    /// Passed rather than inferred. The model used to read it off the values —
    /// "one axis is 1, so it must be a side" — and that is a guess: a side
    /// dragged back to exactly 1.0 is indistinguishable from a corner, and a
    /// corner is what it was treated as.
    ///
    /// It decides whether the axis lock applies. A corner keeps it, because
    /// dragging a corner means "make it bigger". A side ignores it, because
    /// stretching one axis is the only thing a side handle is for — obeying
    /// the lock there makes it a second corner.
    public var isStretch = false

    /// Whether the gesture has finished, so a caller can commit once.
    public var isFinished = false
}

/// The frame drawn around the selected clip.
///
/// Shows where a clip is and lets it be moved from there, the way selecting a
/// layer does in a video editor. It knows nothing about effects or documents:
/// it is given a box and reports what a hand did to it.
struct SelectionBox: View {
    let bounds: ClipBounds?

    /// Where the clip itself sits, in stage units — not the centre of its box.
    ///
    /// For a sprite the two agree and this changes nothing. For anything that
    /// travels they are different places, and the box centre is the wrong one:
    /// a radial burst is emitted from a point and its box is the whole spray,
    /// wider than the stage and centred nowhere near the emitter. The grip
    /// belongs where the effect comes from, which is what the eye is looking
    /// at and what the position fields describe.
    var origin: (x: Double, y: Double)?
    /// Stage size, so stage units can be converted to points and back.
    let stageSize: (width: Double, height: Double)
    let viewSize: CGSize
    /// Whether the framed clip refuses edits.
    ///
    /// Answered on demand rather than passed in: read as a property it made the
    /// window rebuild on every selection, and it matters only at the moment a
    /// gesture would move something.
    var isLocked: Bool
    let onDrag: (ClipDrag) -> Void

    /// Which stage lines the clip is currently caught on, for the canvas to
    /// draw.
    ///
    /// Reported rather than drawn here, because the guides run the width and
    /// height of the stage and this view is only as large as the clip.
    var onSnap: ((Double?, Double?) -> Void)?

    /// Whether the stage's landmarks pull a drag.
    var isSnappingEnabled = true

    /// Points per stage unit. One number because the stage keeps its aspect.
    private var scale: Double { viewSize.width / stageSize.width }

    /// The gesture's travel so far, applied to the box as it is drawn.
    ///
    /// The measured box comes from the frame the GPU last drew, which is always
    /// one behind the edit a drag has just made — and every step of that edit
    /// re-evaluates the clip before it can be drawn. Following the measurement
    /// alone, the frame visibly chased the image instead of holding it, which
    /// reads as the two fighting each other.
    ///
    /// Moving the box locally while the hand is down decouples the two: the
    /// frame answers the pointer immediately, and the measurement takes over
    /// again once the gesture ends and the two agree.
    /// Which zone the pointer is over, and so which cursor to show.
    ///
    /// `NSCursor.push()`/`pop()` is a stack, and these zones overlap: moving
    /// between them quickly interleaves the calls, leaving the stack unbalanced
    /// — a resize cursor appearing while merely moving, or a hand stuck over a
    /// corner. One piece of state and one `set()` cannot get out of step.
    @State private var hoveredZone: Zone?

    enum Zone: Equatable {
        case body
        case corner(Corner)
        case side(Side)

        var cursor: NSCursor {
            switch self {
            case .body: .openHand
            case let .corner(corner): corner.cursor
            case let .side(side): side.cursor
            }
        }
    }

    @State private var liveOffset: CGSize = .zero
    @State private var liveScaleX: Double = 1
    @State private var liveScaleY: Double = 1

    /// Where the box sits in view coordinates, pulled back to the stage.
    ///
    /// A background is deliberately larger than the frame it fills, so its true
    /// box falls mostly outside the stage and clipping it left four lines
    /// pressed against the edges — technically right, and useless: a frame no
    /// one can see says nothing about what is selected. Held inside instead, by
    /// enough of a margin to read as a frame rather than as the canvas border
    /// it sits next to.
    private var frame: CGRect? {
        guard let bounds else { return nil }
        let inset = Self.edgeInset
        var raw = CGRect(
            x: (bounds.minX + Double(OsuCanvas.xOffset)) * scale,
            y: bounds.minY * scale,
            width: bounds.width * scale,
            height: bounds.height * scale,
        )

        // Grown about the clip's own position, which is where the sprite
        // grows from.
        //
        // This used to grow about the centre of the box, and that is only the
        // same point when the origin is `Centre`. With `CentreLeft` the sprite
        // scales rightwards off its position while the frame spread evenly to
        // both sides: the preview showed one thing and the release committed
        // another, which is the frame lying about what a drag will do.
        //
        // Falls back to the centre when there is no clip position, which is
        // exactly what it did before asking.
        if liveScaleX != 1 || liveScaleY != 1 {
            let pivot = scalePivot(in: raw)
            let corner = raw.origin
            raw.size = CGSize(
                width: raw.width * liveScaleX,
                height: raw.height * liveScaleY,
            )
            raw.origin = CGPoint(
                x: pivot.x - (pivot.x - corner.x) * liveScaleX,
                y: pivot.y - (pivot.y - corner.y) * liveScaleY,
            )
        }
        raw = raw.offsetBy(dx: liveOffset.width, dy: liveOffset.height)

        // Held to the stage, moving or not.
        //
        // An earlier version let a moving box leave, because the grip lived
        // inside it and a clamped box dragged the grip back under the cursor,
        // which made the next event measure from somewhere else. Neither is
        // true any more: the grip is drawn on the stage and the gesture
        // measures in a fixed coordinate space, so the clamp no longer fights
        // the hand.
        //
        // And leaving is what broke it. Measured on a radial burst, the box is
        // 1504×2926 against a 463-point view — six times taller than the
        // screen. Its four borders sit far outside the canvas, so what is
        // drawn inside the stage is its empty middle: the frame is there and
        // reads as gone, taking the resize handles with it.
        let minX = max(inset, raw.minX)
        let minY = max(inset, raw.minY)
        let maxX = min(viewSize.width - inset, raw.maxX)
        let maxY = min(viewSize.height - inset, raw.maxY)

        // A clip whose sprites are momentarily off-stage measures as nothing,
        // and clamping that to a pixel collapsed the frame to a dot mid-drag —
        // an emitter re-evaluated between frames genuinely has different
        // particles, some of which briefly leave the stage. Below a size worth
        // drawing the frame is not drawn at all, which reads as "still
        // catching up" rather than as a control that broke.
        let width = maxX - minX
        let height = maxY - minY
        guard width > Self.minimumSize, height > Self.minimumSize else { return nil }

        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    /// How far the box is held off the stage edge.
    private static let edgeInset: CGFloat = 6

    /// Below this the frame is not worth drawing.
    private static let minimumSize: CGFloat = 8

    var body: some View {
        // Nothing to frame yet, or nothing left worth framing.
        if let box = frame {
            content(box)
        }
    }

    private func content(_ box: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            // Carries the stage's size so the stack aligns against it.
            //
            // A bare `Color.clear` expands to whatever is offered and takes the
            // stack with it, so the box was laid out against the window and its
            // handles landed in the window's corners. Same trap as the keyframe
            // diamonds: the size has to be declared *inside* the stack, not
            // applied to it afterwards.
            Color.clear
                .frame(width: viewSize.width, height: viewSize.height)

            ZStack {
                // Drawn only. Moving belongs to the grip below.
                //
                // The body carried `moveGesture` too, so both it and the grip
                // received the same drag and each wrote its own translation to
                // the shared offset — the frame flicked between two positions
                // and looked like two borders fighting. A logged drag showed
                // the travel itself going 66, 62, 94, 84: not a hand, two
                // gestures alternating.
                Rectangle()
                    .strokeBorder(
                        .white,
                        style: StrokeStyle(lineWidth: 1.5, dash: isLocked ? [4, 3] : []),
                    )
                    .allowsHitTesting(false)

                if !isLocked {
                    ForEach(Side.allCases, id: \.self) { side in
                        sideHandle(side, in: box)
                    }

                    ForEach(Corner.allCases, id: \.self) { corner in
                        handle(corner, in: box)
                    }

                    // The grip, inside the box's own stack — one hover
                    // surface, not two.
                    //
                    // It briefly lived in an outer `.overlay` so its position
                    // could come from the stage. That put it on a layer above
                    // the handles, and the two traded events: the log shows
                    // hover alternating corner → body → corner → side with the
                    // pointer still, so the cursor flickered between a hand and
                    // a resize arrow.
                    //
                    // The position still comes from the stage — the box is
                    // re-measured every evaluation and does not hold still —
                    // but it is converted into the box's own space here, so
                    // there is a single stack deciding what the pointer is on.
                    if let point = gripPointInBox(box) {
                        Circle()
                            .fill(.white)
                            .overlay(
                                Circle()
                                    .strokeBorder(.black.opacity(0.35), lineWidth: 1),
                            )
                            .frame(width: Self.gripSize, height: Self.gripSize)
                            .contentShape(.circle)
                            .position(point)
                            .onHover { hovering in
                                setZone(.body, hovering)
                            }
                    }
                }
            }
            .frame(width: box.width, height: box.height)
            // Turned to match the clip rather than grown to cover it. An
            // upright box around a rotating sprite swells and shrinks with the
            // angle, so a steady spin looked like the clip pulsing.
            .rotationEffect(.radians(bounds?.rotation ?? 0))
            .offset(x: box.minX, y: box.minY)
        }
        // The move gesture lives here, on a layer that does not move.
        //
        // Attached to the grip it chased itself: the grip is positioned inside
        // the box, the box follows `liveOffset`, so every event shifted the
        // view the gesture was anchored to and SwiftUI re-measured the
        // translation from the new place. A logged drag reported 172, 158, 197,
        // 175 — 27 reversals in 60 events, one of them 198 points. The hand was
        // steady; the anchor was not.
        // A background, not an overlay: laid over the corners it won their
        // hover even with an inset, so the top-left handle reported the body's
        // open hand and resizing from there was unreachable. The corners are
        // the smaller, more precise target, so they belong on top.
        .background(alignment: .topLeading) {
            if !isLocked, let box = frame {
                // The whole body, not just the grip: picking a clip up
                // anywhere on it is what a hand reaches for, and what every
                // editor does. The grip stays as the fallback for a clip too
                // small or too far off-stage to have a body worth aiming at.
                //
                // Inset so the corners keep their own margin — a resize handle
                // buried under the move area cannot be reached.
                // Inset only while the handles are inside it; once they move
                // out, the whole interior is grabbable.
                let inset = handlesSitOutside(box) ? 0 : Self.handleSize
                Color.clear
                    .frame(
                        width: max(box.width - inset * 2, 1),
                        height: max(box.height - inset * 2, 1),
                    )
                    .contentShape(.rect)
                    .offset(
                        x: box.minX - liveOffset.width + inset,
                        y: box.minY - liveOffset.height + inset,
                    )
                    .gesture(moveGesture)
                    .onHover { hovering in
                        setZone(.body, hovering)
                    }
            }
        }
        .frame(width: viewSize.width, height: viewSize.height)
        // The frame the move gesture measures against. On the outermost layer
        // because it is the only one sized to the stage rather than to the
        // clip: everything inside moves as the box is re-measured.
        .coordinateSpace(.named(Self.dragSpace))
        // Clipped to the stage: a background is deliberately larger than the
        // frame it fills, and a box drawn past the edge would spill over the
        // panels beside the canvas.
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.stage, style: .continuous))
        // A locked clip shows where it is but refuses to be moved, which is
        // what the lock is for.
        .allowsHitTesting(!isLocked)
    }

    // ─── Moving ──────────────────────────────────────────────────────────────

    /// A space that does not move, for the move gesture to measure in.
    ///
    /// **The bug this pins.** A `DragGesture` reports its translation relative
    /// to the view it is attached to, and that view is positioned from the
    /// box. An emitter's box is not stable — its particles travel, so it grows
    /// every frame, and it is re-measured asynchronously as the clip is
    /// re-evaluated. Every remeasure slid the view out from under the cursor
    /// and the next event's translation was taken from the new place.
    ///
    /// Logged on a radial burst: the pointer's reported location went from
    /// (432, 271) to (689, 1012) between two consecutive events of one gesture
    /// while the hand barely moved — a jump of 741 points, to a position
    /// outside the window. The clip went from (200, 240) to (599, 1179).
    ///
    /// Named on the canvas itself, which is anchored to the stage and never
    /// moves, so a translation means the same thing at every event.
    private static let dragSpace = "SelectionBox.stage"

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.dragSpace))
            .onChanged { value in
                // Converted through the stage scale, not tracked in points: at
                // any size but 1:1 the two disagree and the box drifts away
                // from the pointer.
                let snapped = snap(value.translation)

                // The box follows the *snapped* travel, not the hand's: a frame
                // that keeps following the pointer while the clip has jumped to
                // a line shows the two in different places, and the snap reads
                // as the drag being broken.
                liveOffset = CGSize(
                    width: snapped.dx * scale,
                    height: snapped.dy * scale,
                )
                onSnap?(snapped.snappedX, snapped.snappedY)
                onDrag(ClipDrag(dx: snapped.dx, dy: snapped.dy))
            }
            .onEnded { value in
                // Released before reporting: the measurement that arrives next
                // already contains this move, so keeping the offset would apply
                // it twice.
                liveOffset = .zero
                onSnap?(nil, nil)

                let snapped = snap(value.translation)
                onDrag(ClipDrag(dx: snapped.dx, dy: snapped.dy, isFinished: true))
            }
    }

    /// A drag pulled onto the stage's landmarks.
    ///
    /// Only while a box has actually been measured: with nothing to snap, a
    /// drag has no edges to test and passes through untouched.
    private func snap(_ translation: CGSize) -> StageSnap.Result {
        let travel = (dx: translation.width / scale, dy: translation.height / scale)
        guard let bounds else { return StageSnap.Result(dx: travel.dx, dy: travel.dy) }

        return StageSnap.adjust(
            (minX: bounds.minX, minY: bounds.minY, maxX: bounds.maxX, maxY: bounds.maxY),
            by: travel,
            // Held down, the drag passes through untouched.
            //
            // A snap with no way out is a cage: sometimes 318 is the number
            // somebody wants, and without an escape the only way to reach it is
            // to type it into the inspector. Command is what Figma and Sketch
            // use, and Option is already spoken for by the pen tool.
            isEnabled: isSnappingEnabled && !NSEvent.modifierFlags.contains(.command),
        )
    }

    // ─── Resizing ────────────────────────────────────────────────────────────

    /// A mid-edge handle, which stretches one axis.
    ///
    /// Corners keep both axes together; sides are how a clip is stretched, and
    /// stretching is the reason per-axis scale exists at all.
    enum Side: CaseIterable {
        case leading, trailing, top, bottom

        var isHorizontal: Bool { self == .leading || self == .trailing }

        /// Which way this edge travels to make the box bigger.
        var growth: Double {
            switch self {
            case .leading, .top: -1
            case .trailing, .bottom: 1
            }
        }

        func point(in size: CGSize, outset: CGFloat = 0) -> CGPoint {
            switch self {
            case .leading: CGPoint(x: -outset, y: size.height / 2)
            case .trailing: CGPoint(x: size.width + outset, y: size.height / 2)
            case .top: CGPoint(x: size.width / 2, y: -outset)
            case .bottom: CGPoint(x: size.width / 2, y: size.height + outset)
            }
        }

        var cursor: NSCursor { isHorizontal ? .resizeLeftRight : .resizeUpDown }
    }

    enum Corner: CaseIterable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing

        var alignment: Alignment {
            switch self {
            case .topLeading: .topLeading
            case .topTrailing: .topTrailing
            case .bottomLeading: .bottomLeading
            case .bottomTrailing: .bottomTrailing
            }
        }

        /// Where this corner sits inside a box of the given size.
        func point(in size: CGSize, outset: CGFloat = 0) -> CGPoint {
            CGPoint(
                x: alignment.horizontal == .leading ? -outset : size.width + outset,
                y: alignment.vertical == .top ? -outset : size.height + outset,
            )
        }

        /// The pointer for this corner, angled the way it resizes.
        ///
        /// AppKit ships no public diagonal resize cursor, so these come from
        /// the system's own images by name — the same ones every app shows on a
        /// window corner. A missing image falls back to the crosshair rather
        /// than to nothing, since a wrong-looking cursor still beats one that
        /// says the area is not interactive.
        var cursor: NSCursor {
            let name = switch self {
            case .topLeading, .bottomTrailing: "resizenorthwestsoutheast"
            case .topTrailing, .bottomLeading: "resizenortheastsouthwest"
            }
            return Self.systemCursor(named: name) ?? .crosshair
        }

        private static func systemCursor(named name: String) -> NSCursor? {
            let path = "/System/Library/Frameworks/ApplicationServices.framework"
                + "/Versions/A/Frameworks/HIServices.framework/Versions/A/Resources"
                + "/cursors/\(name)"
            guard let image = NSImage(contentsOfFile: "\(path)/cursor.pdf") else { return nil }
            return NSCursor(image: image, hotSpot: NSPoint(x: 8, y: 8))
        }

        /// Which way the corner has to travel to make the box bigger.
        var growth: (x: Double, y: Double) {
            switch self {
            case .topLeading: (-1, -1)
            case .topTrailing: (1, -1)
            case .bottomLeading: (-1, 1)
            case .bottomTrailing: (1, 1)
            }
        }
    }

    private func sideHandle(_ side: Side, in box: CGRect) -> some View {
        Rectangle()
            .fill(.white)
            .frame(
                width: side.isHorizontal ? Self.handleSize : Self.sideLength,
                height: side.isHorizontal ? Self.sideLength : Self.handleSize,
            )
            .contentShape(.rect.inset(by: -Self.handleSize))
            .position(side.point(in: box.size, outset: handleOffset(box)))
            .gesture(stretchGesture(side))
            .onHover { hovering in setZone(.side(side), hovering) }
    }

    private func stretchGesture(_ side: Side) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged {
                let drag = stretchDrag(side, $0.translation)
                liveScaleX = drag.scaleX
                liveScaleY = drag.scaleY
                onDrag(drag)
            }
            .onEnded {
                var drag = stretchDrag(side, $0.translation)
                drag.isFinished = true
                liveScaleX = 1
                liveScaleY = 1
                onDrag(drag)
            }
    }

    /// One axis, measured against that axis's own extent.
    private func stretchDrag(_ side: Side, _ translation: CGSize) -> ClipDrag {
        let extent = bounds ?? ClipBounds(minX: 0, minY: 0, maxX: 1, maxY: 1)
        let travel = (side.isHorizontal ? translation.width : translation.height)
            * side.growth / scale
        let span = max(side.isHorizontal ? extent.width : extent.height, 1)
        let factor = max(0.05, 1 + travel / span)

        return side.isHorizontal
            ? ClipDrag(scaleX: factor, scaleY: 1, isStretch: true)
            : ClipDrag(scaleX: 1, scaleY: factor, isStretch: true)
    }

    /// Whether the box is too small to hold its handles inside.
    ///
    /// A handle's grab area is far larger than the square drawn, and four of
    /// them meeting in the middle leave nothing to drag: under about 50pt the
    /// body is a sliver, and under 28pt it is gone entirely — the clip could
    /// only be resized, never moved. The same problem the timeline's resize
    /// ears already solve by sitting outside the clip.
    private func handlesSitOutside(_ box: CGRect) -> Bool {
        box.width < Self.crowdedSize || box.height < Self.crowdedSize
    }

    /// The point a live resize grows away from, in view coordinates.
    ///
    /// The clip's own position, because that is where the sprite scales from —
    /// the anchor is applied to the half-extent, so a `CentreLeft` sprite grows
    /// rightwards and a `Centre` one grows both ways.
    ///
    /// The centre of the box when there is no position to use, which is what
    /// this did before it asked and is right for the centred case.
    private func scalePivot(in box: CGRect) -> CGPoint {
        guard let origin else { return CGPoint(x: box.midX, y: box.midY) }
        return CGPoint(
            x: (origin.x + Double(OsuCanvas.xOffset)) * scale,
            y: origin.y * scale,
        )
    }

    /// Where the grip sits inside the box, derived from the stage.
    ///
    /// The clip's own position, converted into the box's space — never the
    /// centre of the box. An emitter's box is re-measured on every evaluation
    /// and its particles are in flight, so it changes size between frames:
    /// logged across one drag, the same clip reported 1949×2145, 811×451 and
    /// 285×451, and a grip placed relative to it landed at 942, then 393, then
    /// 146, flicking between them fast enough to read as vanishing.
    ///
    /// `nil` when the point falls outside the box, which is a clip dragged far
    /// enough that its origin is off the visible frame. Drawing it there would
    /// put a grip outside the thing it belongs to.
    ///
    /// The bound is the box itself, not the box less the grip's radius. Any
    /// origin but `Centre` puts the clip's position *on* an edge — `CentreLeft`
    /// on the left one, `TopLeft` on a corner — and a radius of margin rejected
    /// exactly those, so the grip disappeared for eight origins out of nine.
    /// Half a circle hanging over the frame is the honest picture of a sprite
    /// anchored to its edge.
    private func gripPointInBox(_ box: CGRect) -> CGPoint? {
        guard let point = stageGripPoint else { return nil }
        let inBox = CGPoint(x: point.x - box.minX, y: point.y - box.minY)

        guard inBox.x >= 0, inBox.x <= box.width,
              inBox.y >= 0, inBox.y <= box.height
        else { return nil }

        return inBox
    }

    /// Where the grip sits on the stage, in view coordinates.
    ///
    /// Derived from the clip's own position and the live drag offset — never
    /// from the box.
    ///
    /// **The bug this pins.** An emitter's box is re-measured on every
    /// evaluation and its particles are in flight, so it does not hold still:
    /// logged across a single drag, the same clip reported boxes of 1949×2145,
    /// 811×451 and 285×451. A grip positioned inside it landed somewhere
    /// different for each — 942, then 393, then 146 — flicking between them
    /// fast enough to read as the grip vanishing.
    ///
    /// `nil` when there is no clip position to draw it at.
    private var stageGripPoint: CGPoint? {
        guard let origin else { return nil }

        let x = (origin.x + Double(OsuCanvas.xOffset)) * scale + Double(liveOffset.width)
        let y = origin.y * scale + Double(liveOffset.height)

        // Held on the stage, because a clip can be dragged past the edge and a
        // grip nobody can see is a grip nobody can grab. The margin keeps it
        // off the canvas border rather than clear of the resize handles — out
        // here it no longer shares space with them.
        let margin = Double(Self.gripSize)
        return CGPoint(
            x: min(max(margin, x), viewSize.width - margin),
            y: min(max(margin, y), viewSize.height - margin),
        )
    }


    /// How far a handle moves out when it will not fit in.
    private func handleOffset(_ box: CGRect) -> CGFloat {
        handlesSitOutside(box) ? Self.handleSize * 1.5 : 0
    }

    private func handle(_ corner: Corner, in box: CGRect) -> some View {
        // Placed by `position`, not by alignment inside a full-size frame.
        //
        // That earlier version put `contentShape` *after* stretching the frame
        // to fill the box, so every handle's hit area was the whole rectangle:
        // the four sat on top of one another and on top of the move gesture, so
        // which corner answered a click was decided by their order rather than
        // by where the pointer was. Resizing picked a direction at random and
        // dragging the body never reached the move gesture at all.
        Rectangle()
            .fill(.white)
            .frame(width: Self.handleSize, height: Self.handleSize)
            // A 7pt square is a small target, so the grabbable area is larger
            // than what is drawn — but still only around this corner.
            .contentShape(.rect.inset(by: -Self.handleSize))
            .position(corner.point(in: box.size, outset: handleOffset(box)))
            .gesture(resizeGesture(corner))
            .onHover { hovering in
                setZone(.corner(corner), hovering)
            }
    }

    private func resizeGesture(_ corner: Corner) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged {
                let drag = scaleDrag(corner, $0.translation)
                liveScaleX = drag.scaleX
                liveScaleY = drag.scaleY
                onDrag(drag)
            }
            .onEnded {
                var drag = scaleDrag(corner, $0.translation)
                drag.isFinished = true
                liveScaleX = 1
                liveScaleY = 1
                onDrag(drag)
            }
    }

    /// Turns a corner drag into a scale multiplier.
    ///
    /// Both axes are projected onto the corner's outward direction and measured
    /// against the box's diagonal, so a drag away from the centre always grows
    /// and a drag towards it always shrinks — whichever corner is held.
    ///
    /// Picking a single axis by the box's shape was the bug: the shape read
    /// here is the *clipped* one, so a background wider than the stage chose
    /// horizontal travel while the hand was moving diagonally, and the sign
    /// came out backwards. The diagonal does not care what shape the box is.
    private func scaleDrag(_ corner: Corner, _ translation: CGSize) -> ClipDrag {
        let growth = corner.growth

        // Projected onto the corner's direction as a unit vector, so the number
        // is how far the hand actually travelled that way.
        //
        // Summing the two axes overstated it: a drag of 247 across and 164 down
        // adds to 411 while the hand covered 296 — a 1.39× exaggeration, which
        // is why the frame grew faster than the pointer. The diagonal of a unit
        // square is √2, not 2.
        let length = (growth.x * growth.x + growth.y * growth.y).squareRoot()
        let outward = (translation.width * growth.x + translation.height * growth.y)
            / max(length, 0.0001) / scale

        // Measured against the true box, not the one drawn: a background is
        // held inside the stage for legibility, and dividing by that clipped
        // width would make the same drag mean different amounts depending on
        // how much of the clip happens to be on screen.
        let extent = bounds ?? ClipBounds(minX: 0, minY: 0, maxX: 1, maxY: 1)
        let diagonal = max((extent.width * extent.width + extent.height * extent.height)
            .squareRoot(), 1)

        // Floored rather than allowed through zero: a clip scaled to nothing
        // has no box left to grab, and a negative one flips inside out.
                let factor = max(0.05, 1 + outward / diagonal)
        return ClipDrag(scaleX: factor, scaleY: factor)
    }

    /// Records the zone under the pointer and sets the cursor to match.
    ///
    /// A corner leaving does not clear a body that is still hovered: the two
    /// overlap, and their events arrive in no guaranteed order.
    private func setZone(_ zone: Zone, _ isHovered: Bool) {
        if isHovered {
            hoveredZone = zone
        } else if hoveredZone == zone {
            hoveredZone = nil
        }
        (hoveredZone?.cursor ?? .arrow).set()
    }

    private static let handleSize: CGFloat = 7

    /// Below this the handles move outside, leaving the body to be dragged.
    private static let crowdedSize: CGFloat = 56

    /// How long a side handle runs along its edge.
    private static let sideLength: CGFloat = 18

    /// The centre grip, larger than a corner because it is aimed at directly.
    private static let gripSize: CGFloat = 11
}


