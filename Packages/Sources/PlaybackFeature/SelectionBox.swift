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
    /// Stage size, so stage units can be converted to points and back.
    let stageSize: (width: Double, height: Double)
    let viewSize: CGSize
    let isLocked: Bool
    let onDrag: (ClipDrag) -> Void

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

        var cursor: NSCursor {
            switch self {
            case .body: .openHand
            case let .corner(corner): corner.cursor
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

        // Grown about its own centre, so a resize reads as the clip growing
        // rather than as the box sliding off one corner.
        if liveScaleX != 1 || liveScaleY != 1 {
            let centre = CGPoint(x: raw.midX, y: raw.midY)
            raw.size = CGSize(
                width: raw.width * liveScaleX,
                height: raw.height * liveScaleY,
            )
            raw.origin = CGPoint(x: centre.x - raw.width / 2, y: centre.y - raw.height / 2)
        }
        raw = raw.offsetBy(dx: liveOffset.width, dy: liveOffset.height)

        // Held to the stage only while the box is at rest.
        //
        // The clamp keeps an oversized clip readable, but during a move it
        // fights the hand: the box stops at the edge while the pointer keeps
        // going, and since the grip is positioned inside the box, the grip
        // jumps back under the cursor and the next event measures from
        // somewhere else — the frame appears to bounce. A moving box is being
        // watched, not read, so it is allowed to leave.
        guard liveOffset == .zero else {
            return raw.width > Self.minimumSize && raw.height > Self.minimumSize ? raw : nil
        }

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
                    // A grip at the centre, because the body is not always
                    // grabbable: a clip can be larger than the stage, or so
                    // small that its inside is a few pixels, and either way
                    // there is no reliable place to take hold of it. The centre
                    // is always there, and it is where a hand looks first.
                    Circle()
                        .fill(.white)
                        .frame(width: Self.gripSize, height: Self.gripSize)
                        .overlay(
                            Circle()
                                .strokeBorder(.black.opacity(0.35), lineWidth: 1),
                        )
                        .contentShape(.circle.inset(by: -Self.handleSize))
                        .position(x: box.width / 2, y: box.height / 2)
                        .onHover { hovering in
                            setZone(.body, hovering)
                        }

                    ForEach(Corner.allCases, id: \.self) { corner in
                        handle(corner, in: box)
                    }
                }
            }
            .frame(width: box.width, height: box.height)
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
                Color.clear
                    .frame(
                        width: max(box.width - Self.handleSize * 2, 1),
                        height: max(box.height - Self.handleSize * 2, 1),
                    )
                    .contentShape(.rect)
                    .offset(
                        x: box.minX - liveOffset.width + Self.handleSize,
                        y: box.minY - liveOffset.height + Self.handleSize,
                    )
                    .gesture(moveGesture)
                    .onHover { hovering in
                        setZone(.body, hovering)
                    }
            }
        }
        .frame(width: viewSize.width, height: viewSize.height)
        // Clipped to the stage: a background is deliberately larger than the
        // frame it fills, and a box drawn past the edge would spill over the
        // panels beside the canvas.
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.stage, style: .continuous))
        // A locked clip shows where it is but refuses to be moved, which is
        // what the lock is for.
        .allowsHitTesting(!isLocked)
    }

    // ─── Moving ──────────────────────────────────────────────────────────────

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                liveOffset = value.translation

                // Converted through the stage scale, not tracked in points: at
                // any size but 1:1 the two disagree and the box drifts away
                // from the pointer.
                onDrag(ClipDrag(
                    dx: value.translation.width / scale,
                    dy: value.translation.height / scale,
                ))
            }
            .onEnded { value in
                // Released before reporting: the measurement that arrives next
                // already contains this move, so keeping the offset would apply
                // it twice.
                liveOffset = .zero
                onDrag(ClipDrag(
                    dx: value.translation.width / scale,
                    dy: value.translation.height / scale,
                    isFinished: true,
                ))
            }
    }

    // ─── Resizing ────────────────────────────────────────────────────────────

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
        func point(in size: CGSize) -> CGPoint {
            CGPoint(
                x: alignment.horizontal == .leading ? 0 : size.width,
                y: alignment.vertical == .top ? 0 : size.height,
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
            .position(corner.point(in: box.size))
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

    /// The centre grip, larger than a corner because it is aimed at directly.
    private static let gripSize: CGFloat = 11
}


