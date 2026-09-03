import DesignSystem
import Foundation
import StoryboardCore
import SwiftUI

/// The keyframe rows for the selected clip, under its lane.
///
/// Only for the selection, and only for properties that are animated. Every
/// property of every clip at once is five rows per clip and unreadable by the
/// second one — After Effects reveals a layer's properties the same way, and
/// for the same reason.
struct KeyframeRows: View {
    let node: EffectNode
    let scale: TimelineScale
    let headerWidth: CGFloat
    /// Where the playhead is inside the clip, for placing a new key.
    let localTime: Double
    /// The playhead read at the moment of a click, not at the last redraw.
    let playheadNow: () -> Double
    let isPlaying: Bool
    let addKeyframe: (TransformProperty, Double) -> Void
    let moveKeyframe: (TransformProperty, Keyframe.ID, Double) -> Void
    let removeKeyframe: (TransformProperty, Keyframe.ID) -> Void
    let setEasing: (TransformProperty, Keyframe.ID, Easing) -> Void
    /// Switches a property's animation on or off, keeping its keys.
    let setEnabled: (TransformProperty, Bool) -> Void
    /// Drops every key on a property.
    let clear: (TransformProperty) -> Void
    /// The key the inspector is editing, with the property it belongs to.
    let selectedKey: (property: TransformProperty, id: Keyframe.ID)?
    let selectKey: (TransformProperty, Keyframe.ID) -> Void

    static let rowHeight: CGFloat = 20

    /// How tall the rows are, so the timeline can make space.
    static var height: CGFloat {
        (rowHeight + Theme.Spacing.hair) * CGFloat(TransformProperty.allCases.count)
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.hair) {
            // Every property, not only the animated ones: this is where a key
            // gets added, and a property with none would have no row to add it
            // on.
            ForEach(TransformProperty.allCases, id: \.self) { property in
                KeyframeRow(
                    property: property,
                    track: node.transform[property],
                    nodeStart: node.startTime,
                    scale: scale,
                    headerWidth: headerWidth,
                    localTime: localTime,
                    playheadNow: playheadNow,
                    isPlaying: isPlaying,
                    addKeyframe: { addKeyframe(property, $0) },
                    moveKeyframe: { moveKeyframe(property, $0, $1) },
                    removeKeyframe: { removeKeyframe(property, $0) },
                    setEasing: { setEasing(property, $0, $1) },
                    setEnabled: { setEnabled(property, $0) },
                    clear: { clear(property) },
                    selectedKeyID: selectedKey?.property == property ? selectedKey?.id : nil,
                    selectKey: { selectKey(property, $0) },
                )
            }
        }
    }
}

/// One property's keys, laid along the timeline.
private struct KeyframeRow: View {
    let property: TransformProperty
    let track: StoryboardCore.KeyframeTrack
    /// The clip's position, since keyframe times are local to it.
    let nodeStart: Double
    let scale: TimelineScale
    let headerWidth: CGFloat
    let localTime: Double
    /// The playhead read at the moment of a click, not at the last redraw.
    let playheadNow: () -> Double
    /// Whether the clock is running, which is when a key cannot be placed
    /// meaningfully.
    let isPlaying: Bool
    let addKeyframe: (Double) -> Void
    let moveKeyframe: (Keyframe.ID, Double) -> Void
    let removeKeyframe: (Keyframe.ID) -> Void
    let setEasing: (Keyframe.ID, Easing) -> Void
    let setEnabled: (Bool) -> Void
    let clear: () -> Void
    /// The key the inspector is editing, if it is on this row.
    let selectedKeyID: Keyframe.ID?
    let selectKey: (Keyframe.ID) -> Void

    /// The key being dragged, and where it has reached.
    @State private var draft: (id: Keyframe.ID, time: Double)?
    /// The key under the pointer, so it can say it is reachable.
    @State private var hoveredKeyID: Keyframe.ID?

    private var isAnimating: Bool { track.isActive }

    /// Whether there is a key at the playhead right now.
    private var isOnAKey: Bool {
        track.keyframes.contains { abs($0.time - localTime) < 1 }
    }

    private var stopwatchHelp: String {
        if track.isEmpty { return "Animate \(property.title)" }
        return isAnimating
            ? "Switch off \(property.title) animation (keys are kept)"
            : "Switch \(property.title) animation back on"
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.snug) {
            // The same controls the inspector has, so the mode is usable on
            // its own: someone working in the timeline should not have to cross
            // the window to switch a property on.
            HStack(spacing: Theme.Spacing.hair) {
                IconButton(
                    systemImage: isAnimating ? "stopwatch.fill" : "stopwatch",
                    size: Theme.Size.controlTiny,
                    isActive: isAnimating,
                    help: stopwatchHelp,
                ) {
                    if track.isEmpty {
                        guard !isPlaying else { return }
                        addKeyframe(playheadNow())
                    } else {
                        setEnabled(!isAnimating)
                    }
                }

                Text(property.title)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(
                        isAnimating ? Theme.Palette.secondary : Theme.Palette.tertiary,
                    )
                    .lineLimit(1)

                Spacer(minLength: 0)

                // A key at the playhead. Filled when there is one there, so the
                // button says what it will do before it is pressed.
                // Disabled while the clock runs.
                //
                // A key lands where the playhead is, and a moving playhead is
                // somewhere else by the time the click registers — the keys end
                // up scattered along the clip with no relation to where anyone
                // meant to put them. Every editor pauses to keyframe.
                IconButton(
                    systemImage: isOnAKey ? "diamond.fill" : "diamond",
                    size: Theme.Size.controlTiny,
                    isActive: isOnAKey,
                    help: isPlaying
                        ? "Pause to add a keyframe"
                        : (isOnAKey ? "On a keyframe" : "Add a keyframe here"),
                ) {
                    addKeyframe(playheadNow())
                }
                .disabled(isPlaying)
            }
            // The inset goes inside the fixed width, not around it.
            //
            // Applied outside, it made the header twenty points wider than the
            // one the playhead is placed against, so every keyframe drew that
            // far to the right of the moment it was placed at — a constant
            // offset, which is why zooming appeared not to affect it.
            .frame(width: headerWidth - Theme.Spacing.snug, alignment: .leading)
            .padding(.leading, Theme.Spacing.snug)
            .contextMenu {
                if !track.isEmpty {
                    Button(isAnimating ? "Disable Animation" : "Enable Animation") {
                        setEnabled(!isAnimating)
                    }
                    Divider()
                    Button("Delete All Keyframes", systemImage: "trash", role: .destructive) {
                        clear()
                    }
                }
            }

            ZStack(alignment: .leading) {
                // A spacer that declares the lane's width from inside the stack.
                //
                // Applied afterwards as a `.frame`, the width never reaches the
                // alignment: the stack sizes itself to its contents — a few
                // nine-point diamonds — aligns them leading within *that*, and
                // the frame then centres the whole tiny box in the lane. Every
                // key ended up measured from the middle, which is why their
                // spacing was right and their position was not.
                Color.clear.frame(width: scale.width, height: KeyframeRows.rowHeight)

                // A hairline joining the keys, so a property with two of them
                // reads as a span rather than as two unrelated dots.
                if let first = track.first, let last = track.last, track.isAnimated {
                    let from = x(of: first.time)
                    let to = x(of: last.time)
                    Rectangle()
                        .fill(Theme.Fill.subtle)
                        .frame(width: max(0, to - from), height: Theme.Size.hairline)
                        .offset(x: from)
                }

                ForEach(track.keyframes) { key in
                    diamond(key)
                }
            }
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .fill(track.isEmpty ? Color.clear : Theme.Fill.subtle)
            }
            .contentShape(.rect)
            // Double-click anywhere on the lane drops a key at the playhead,
            // which is the one thing an empty row is for.
            .onTapGesture(count: 2) { if !isPlaying { addKeyframe(localTime) } }
            .clipShape(Rectangle())

            Spacer(minLength: 0)
        }
        .frame(height: KeyframeRows.rowHeight)
    }

    /// Where a local time falls on the timeline.
    private func x(of localTime: Double) -> CGFloat {
        scale.x(of: nodeStart + localTime)
    }

    /// A keyframe: the diamond every timeline uses for one.
    @ViewBuilder
    private func diamond(_ key: Keyframe) -> some View {
        let time = draft?.id == key.id ? draft!.time : key.time
        let size: CGFloat = 9

        let isHovered = hoveredKeyID == key.id
        let isSelected = selectedKeyID == key.id

        Diamond()
            .fill(isAnimating ? Theme.Palette.accent : Theme.Palette.tertiary)
            // A ring rather than a size change: growing the diamond moves its
            // own edges, and a key is a moment — it should not appear to cover
            // more of the timeline because a pointer is near it.
            .overlay {
                if isSelected {
                    Diamond()
                        .stroke(Theme.Palette.primary, lineWidth: Theme.Size.hairline)
                        .padding(-3)
                } else if isHovered {
                    Diamond()
                        .stroke(Theme.Palette.primary.opacity(0.6), lineWidth: Theme.Size.hairline)
                        .padding(-2)
                }
            }
            // The grab area is padding around the shape, not a `contentShape`
            // larger than it.
            //
            // A content shape wider than its view widens the view for layout
            // too, so in a leading-aligned stack the diamond was centred inside
            // that larger box before its offset was applied — every key drew
            // half a hit area to the right of the moment it belonged to, which
            // is why the spacing between keys looked right while the whole row
            // sat too far along.
            .frame(width: size, height: size)
            .padding(.horizontal, size / 2)
            .frame(height: KeyframeRows.rowHeight)
            .contentShape(.rect)
            .offset(x: x(of: time) - size)
            .onHover { hovering in
                hoveredKeyID = hovering ? key.id : nil
                // The cursor says the key can be dragged before anything is
                // clicked, which is the one thing a diamond cannot say itself.
                if hovering { NSCursor.openHand.push() } else { NSCursor.pop() }
            }
            .onTapGesture { selectKey(key.id) }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if draft == nil { selectKey(key.id) }
                        let shift = scale.duration(ofWidth: value.translation.width)
                        draft = (key.id, max(0, key.time + shift))
                    }
                    .onEnded { _ in
                        defer { draft = nil }
                        guard let draft else { return }
                        moveKeyframe(draft.id, draft.time)
                    },
            )
            .contextMenu {
                // The curve belongs to the key it leaves from, which is how a
                // storyboard command carries its own easing.
                Menu("Easing") {
                    ForEach(KeyframeEasing.allCases, id: \.self) { option in
                        Button(option.title) { setEasing(key.id, option.easing) }
                    }
                }
                Divider()
                Button("Delete Keyframe", systemImage: "trash", role: .destructive) {
                    removeKeyframe(key.id)
                }
            }
    }
}

/// The curves offered on a keyframe.
///
/// A short list rather than all thirty-five osu! easings: the rest are
/// reachable from a script, and a menu of thirty-five names is a menu nobody
/// reads.
enum KeyframeEasing: String, CaseIterable {
    case linear
    case easeOut
    case easeIn
    case easeInOut

    var title: String {
        switch self {
        case .linear: "Linear"
        case .easeOut: "Ease Out"
        case .easeIn: "Ease In"
        case .easeInOut: "Ease In Out"
        }
    }

    var easing: Easing {
        switch self {
        case .linear: .linear
        case .easeOut: .out
        case .easeIn: .in
        case .easeInOut: .quadInOut
        }
    }

    /// The option matching an easing, for showing what a key already has.
    ///
    /// Falls back to linear: a key can carry any of osu!'s thirty-five curves —
    /// from a script, or a preset — and a menu of four cannot name them all.
    static func matching(_ easing: Easing) -> KeyframeEasing {
        allCases.first { $0.easing == easing } ?? .linear
    }
}

/// The diamond a keyframe is drawn as.
private struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}
