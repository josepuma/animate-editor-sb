import DesignSystem
import Foundation
import StoryboardCore
import SwiftUI

/// The keyframe rows for the selected clip, in collapsible groups.
///
/// One group for the transform and one per filter, which is how After Effects
/// lays out a layer — and for the same reason. Flat, a clip carrying three
/// filters would put fifteen rows above the nine anybody came for; folded, each
/// filter is one line until it is wanted.
///
/// The grouping is what lets a filter offer *every* parameter it can animate
/// rather than only the ones already animated. Without it, a parameter with no
/// keys had nowhere to appear, so the only way to start animating one was the
/// inspector — a stopwatch somebody had to already know was there.
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

    /// The clip's filters, each a group of its animatable parameters.
    var filters: [FilterNode] = []
    /// Whether the transform group is open, and how to change that.
    var isTransformExpanded = true
    var toggleTransform: () -> Void = {}
    /// Whether a filter's group is open, and how to change that.
    var isFilterExpanded: (FilterNode.ID) -> Bool = { _ in false }
    var toggleFilter: (FilterNode.ID) -> Void = { _ in }
    /// Jumps to a transform key: seeks to it and selects it.
    var goToKey: (TransformProperty, Keyframe) -> Void = { _, _ in }
    /// Jumps to a filter key.
    var goToFilterKey: (FilterNode.ID, String, Keyframe) -> Void = { _, _, _ in }
    /// The selected filter key, so its diamond can show it.
    var selectedFilterKey: (filterID: FilterNode.ID, parameter: String, id: Keyframe.ID)?
    /// Picks a filter key, so clicking its diamond does what clicking a
    /// transform one does.
    var selectFilterKey: (FilterNode.ID, String, Keyframe.ID) -> Void = { _, _, _ in }
    var filterDescriptor: (String) -> FilterDescriptor? = { _ in nil }
    var addFilterKeyframe: (FilterNode.ID, String, Double) -> Void = { _, _, _ in }
    var moveFilterKeyframe: (FilterNode.ID, String, Keyframe.ID, Double) -> Void = { _, _, _, _ in }
    var removeFilterKeyframe: (FilterNode.ID, String, Keyframe.ID) -> Void = { _, _, _ in }
    var setFilterEasing: (FilterNode.ID, String, Keyframe.ID, Easing) -> Void = { _, _, _, _ in }
    var setFilterEnabled: (FilterNode.ID, String, Bool) -> Void = { _, _, _ in }
    var clearFilter: (FilterNode.ID, String) -> Void = { _, _ in }

    /// One row per animatable filter parameter, identified by where it lives.
    ///
    /// A filter's id and a parameter name, because two glows on one clip can
    /// both animate intensity and the rows have to stay apart.
    struct FilterRow: Identifiable {
        let id: String
        let filterID: FilterNode.ID
        let parameter: String
        let title: String
        let track: StoryboardCore.KeyframeTrack
    }

    /// One filter's group: its heading and the rows inside it.
    struct FilterGroup: Identifiable {
        let id: FilterNode.ID
        let name: String
        let systemImage: String
        let rows: [FilterRow]

        var animatedCount: Int { rows.filter { !$0.track.isEmpty }.count }
    }

    /// Whether the selected filter key belongs to this row.
    private func selectedFilterKeyID(_ row: FilterRow) -> Keyframe.ID? {
        guard let selected = selectedFilterKey,
              selected.filterID == row.filterID, selected.parameter == row.parameter
        else { return nil }
        return selected.id
    }

    private var groups: [FilterGroup] {
        Self.groups(for: filters, descriptor: filterDescriptor)
    }

    /// The groups a clip's filters contribute, by one rule.
    ///
    /// Shared with whoever sizes the editor: a height worked out separately
    /// from what gets drawn is a height that eventually disagrees, and this
    /// timeline has already been bitten three times by exactly that.
    static func groups(
        for filters: [FilterNode],
        descriptor: (String) -> FilterDescriptor?,
    ) -> [FilterGroup] {
        filters.compactMap { filter in
            guard let descriptor = descriptor(filter.type) else { return nil }

            // Every parameter the filter says can be animated, not only those
            // already animated: this is where somebody starts one, and a
            // parameter with no keys would have no row to start it on.
            let rows = descriptor.parameters
                .filter(\.animation.isAnimatable)
                .map { parameter in
                    FilterRow(
                        id: "\(filter.id)/\(parameter.id)",
                        filterID: filter.id,
                        parameter: parameter.id,
                        // Just the parameter: the group heading above already
                        // says which filter, so repeating it costs width and
                        // says nothing new.
                        title: parameter.name,
                        track: filter.animations[parameter.id] ?? KeyframeTrack(),
                    )
                }
            guard !rows.isEmpty else { return nil }

            return FilterGroup(
                id: filter.id,
                name: descriptor.name,
                systemImage: descriptor.systemImage,
                rows: rows,
            )
        }
    }

    /// How many rows the editor draws for a clip, headings included.
    ///
    /// Depends on what is folded, so the caller passes the same answers the
    /// view will use — one of them guessing is how a height comes to disagree
    /// with its contents.
    static func rowCount(
        of node: EffectNode,
        descriptor: (String) -> FilterDescriptor?,
        isTransformExpanded: Bool,
        isFilterExpanded: (FilterNode.ID) -> Bool,
    ) -> Int {
        let filterGroups = groups(for: node.filters, descriptor: descriptor)

        // The transform heading, plus its properties when open.
        var count = 1 + (isTransformExpanded ? TransformProperty.allCases.count : 0)
        for group in filterGroups {
            count += 1 + (isFilterExpanded(group.id) ? group.rows.count : 0)
        }
        return count
    }

    static let rowHeight: CGFloat = 20

    /// How tall a given number of rows comes to.
    static func height(rows: Int) -> CGFloat {
        (rowHeight + Theme.Spacing.hair) * CGFloat(max(rows, 1))
    }

    /// The height of a clip with nothing folded away and no filters, for
    /// callers with no clip to ask about.
    static var height: CGFloat {
        height(rows: TransformProperty.allCases.count + 1)
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.hair) {
            KeyframeGroupHeader(
                title: "Transform",
                systemImage: "move.3d",
                animatedCount: TransformProperty.allCases
                    .filter { !node.transform[$0].isEmpty }.count,
                isExpanded: isTransformExpanded,
                toggle: toggleTransform,
            )

            if isTransformExpanded {
                // Every property, not only the animated ones: this is where a
                // key gets added, and a property with none would have no row to
                // add it on.
                ForEach(TransformProperty.allCases, id: \.self) { property in
                    KeyframeRow(
                        title: property.title,
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
                        selectedKeyID: selectedKey?.property == property
                            ? selectedKey?.id : nil,
                        selectKey: { selectKey(property, $0) },
                        goToKey: { goToKey(property, $0) },
                    )
                }
            }

            // Then one group per filter. The same row component throughout,
            // because a keyframe is a keyframe wherever it came from —
            // dragging, easing and deleting have to work one way or the mode
            // has two vocabularies.
            ForEach(groups) { group in
                KeyframeGroupHeader(
                    title: group.name,
                    systemImage: group.systemImage,
                    animatedCount: group.animatedCount,
                    isExpanded: isFilterExpanded(group.id),
                    toggle: { toggleFilter(group.id) },
                )

                if isFilterExpanded(group.id) {
                    ForEach(group.rows) { row in
                        KeyframeRow(
                            title: row.title,
                            track: row.track,
                            nodeStart: node.startTime,
                            scale: scale,
                            headerWidth: headerWidth,
                            localTime: localTime,
                            playheadNow: playheadNow,
                            isPlaying: isPlaying,
                            addKeyframe: {
                                addFilterKeyframe(row.filterID, row.parameter, $0)
                            },
                            moveKeyframe: {
                                moveFilterKeyframe(row.filterID, row.parameter, $0, $1)
                            },
                            removeKeyframe: {
                                removeFilterKeyframe(row.filterID, row.parameter, $0)
                            },
                            setEasing: {
                                setFilterEasing(row.filterID, row.parameter, $0, $1)
                            },
                            setEnabled: {
                                setFilterEnabled(row.filterID, row.parameter, $0)
                            },
                            clear: { clearFilter(row.filterID, row.parameter) },
                            // Selecting a filter key is not wired up yet: the
                            // inspector's key editor speaks `TransformProperty`,
                            // and widening it is its own change.
                            selectedKeyID: selectedFilterKeyID(row),
                            selectKey: { selectFilterKey(row.filterID, row.parameter, $0) },
                            goToKey: { goToFilterKey(row.filterID, row.parameter, $0) },
                        )
                    }
                }
            }
        }
    }
}

/// One property's keys, laid along the timeline.
struct KeyframeRow: View {
    /// What this row animates, for the label and the tooltips.
    ///
    /// A title rather than a `TransformProperty`, which is all the row ever
    /// used one for: everything else arrives as a track and a set of callbacks
    /// with the property already applied. That makes the row reusable by
    /// anything with keyframes — a filter's parameters included — instead of
    /// needing a near-copy per kind of animated thing.
    let title: String
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
    /// Jumps to a keyframe: moves the playhead there **and** selects it.
    ///
    /// One callback rather than two, because they are one action. Seeking
    /// without selecting leaves the inspector describing something else — the
    /// arrow lands on a key the panel then declines to talk about.
    var goToKey: (Keyframe) -> Void = { _ in }

    /// The key being dragged, and where it has reached.
    @State private var draft: (id: Keyframe.ID, time: Double)?
    /// The key under the pointer, so it can say it is reachable.
    @State private var hoveredKeyID: Keyframe.ID?

    private var isAnimating: Bool { track.isActive }

    /// Whether there is a key at the playhead right now.
    private var isOnAKey: Bool {
        track.keyframes.contains { abs($0.time - localTime) < 1 }
    }

    /// The nearest key before the playhead, if any.
    ///
    /// Strictly before, and by the same tolerance the diamond uses to call
    /// itself filled — otherwise standing on a key would offer to jump to
    /// itself, which looks like a broken button.
    private var previousKey: Keyframe? {
        track.keyframes.last { $0.time < localTime - 1 }
    }

    private var nextKey: Keyframe? {
        track.keyframes.first { $0.time > localTime + 1 }
    }

    private var stopwatchHelp: String {
        if track.isEmpty { return "Animate \(title)" }
        return isAnimating
            ? "Switch off \(title) animation (keys are kept)"
            : "Switch \(title) animation back on"
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

                Text(title)
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
                // Jump to the previous key, then the diamond, then the next —
                // the arrangement After Effects uses, and worth copying because
                // it puts the two navigation controls either side of the thing
                // they navigate between.
                //
                // Without them the only way to land exactly on a key is to drag
                // the playhead onto it by eye, and a key a pixel away is a key
                // that edits nothing when you type a value.
                IconButton(
                    systemImage: "arrowtriangle.left.fill",
                    size: Theme.Size.controlTiny,
                    help: previousKey == nil
                        ? "No earlier keyframe"
                        : "Go to previous keyframe",
                ) {
                    previousKey.map(goToKey)
                }
                // Dimmed rather than hidden at the ends: a control that vanishes
                // moves the diamond under the pointer, so the next click lands
                // on something else.
                .disabled(previousKey == nil)
                .opacity(previousKey == nil ? 0.35 : 1)

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

                IconButton(
                    systemImage: "arrowtriangle.right.fill",
                    size: Theme.Size.controlTiny,
                    help: nextKey == nil ? "No later keyframe" : "Go to next keyframe",
                ) {
                    nextKey.map(goToKey)
                }
                .disabled(nextKey == nil)
                .opacity(nextKey == nil ? 0.35 : 1)
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
