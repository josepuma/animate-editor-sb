import DesignSystem
import StoryboardCore
import SwiftUI

/// The left panel: whatever the rail has selected.
struct SidePanelView: View {
    /// Fixed width, so the shell can size the workspace around the canvas.
    static let width: CGFloat = 240

    @Bindable var shell: EditorShellModel
    /// Where a newly added effect is placed.
    var playheadTime: Double = 0

    /// Which effect's presets are open, if any.
    ///
    /// One at a time: with every group expanded the list is exactly the flat
    /// list this grouping exists to avoid.
    @State private var expandedEffect: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
            SectionHeader(shell.sidePanel.title)

            switch shell.sidePanel {
            case .assets: assets
            case .scripts: scripts
            case .filters: filtersPanel
            case .layers: layers
            case .timing: timing
            }
        }
        .padding(Theme.Spacing.compact)
        .frame(width: Self.width, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .surface(.panel)
    }

    // ─── Assets ──────────────────────────────────────────────────────────────

    private var assets: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
            ChipPicker(
                items: AssetItem.Kind.allCases,
                selection: $shell.assetFilter,
                label: \.title,
            )

            if shell.visibleAssets.isEmpty {
                ComingSoon(
                    title: "No assets",
                    detail: "Images referenced by the storyboard appear here.",
                    systemImage: "photo.on.rectangle.angled",
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.tight) {
                        ForEach(shell.visibleAssets) { asset in
                            AssetRow(asset: asset) {
                                shell.addImage(at: asset.path, time: playheadTime)
                            }
                        }
                    }
                }
            }
        }
    }

    // ─── Scripts ─────────────────────────────────────────────────────────────

    /// The effect library, and what has been placed from it.
    ///
    /// Effects and scripts share this panel because they will be the same
    /// thing: a scripted effect declares the same descriptor a native one does,
    /// and will appear in this list beside them.
    /// The effect library.
    ///
    /// No list of what has been placed: the timeline already shows that, in the
    /// arrangement that matters. Repeating it here spends the panel's height on
    /// a second, worse view of the same thing.
    private var scripts: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.tight) {
                // One row per effect, with its presets folded inside.
                //
                // Every preset is the same emitter with different numbers, so
                // listing them flat would put fifteen rows at one level and
                // hide that they are all one effect — and the list only grows
                // from here.
                ForEach(shell.library.descriptors, id: \.type) { descriptor in
                    EffectGroup(
                        descriptor: descriptor,
                        presets: shell.presets.filter { $0.effectType == descriptor.type },
                        isExpanded: expandedEffect == descriptor.type,
                        toggleExpanded: {
                            expandedEffect = expandedEffect == descriptor.type
                                ? nil
                                : descriptor.type
                        },
                        // Placed where the playhead is, the way a video editor
                        // drops a clip at the cursor.
                        addBlank: { shell.addEffect(descriptor, at: playheadTime) },
                        addPreset: { shell.addPreset($0, at: playheadTime) },
                    )
                }
            }
        }
    }

    // ─── Filters ─────────────────────────────────────────────────────────────

    /// The filter library, in a tab of its own.
    ///
    /// Apart from the effects because they are different things: one makes
    /// something out of nothing, the other needs something to already be there.
    /// Sharing a panel implied a filter could be dropped on an empty timeline.
    private var filtersPanel: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
            Text("Drag onto a clip to apply")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.tertiary)

            ScrollView {
                LazyVStack(spacing: Theme.Spacing.tight) {
                    ForEach(shell.filterDescriptors, id: \.type) { descriptor in
                        FilterLibraryRow(
                            descriptor: descriptor,
                            canApply: shell.selectedEffect != nil,
                            apply: {
                                guard let node = shell.selectedEffect else { return }
                                shell.addFilter(descriptor, to: node.id)
                            },
                        )
                    }
                }
            }
        }
    }

    // ─── Layers ──────────────────────────────────────────────────────────────

    /// The lanes, in the order they draw — topmost first.
    private var layers: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
            HStack {
                Text("\(shell.effects.tracks.count) tracks")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.tertiary)

                Spacer()

                IconButton(
                    systemImage: "plus",
                    size: Theme.Size.controlTiny,
                    help: "New track",
                ) { shell.addTrack() }
            }

            if shell.effects.tracks.isEmpty {
                ComingSoon(
                    title: "No tracks",
                    detail: "Add an effect and a track appears to hold it.",
                    systemImage: "square.3.layers.3d",
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.tight) {
                        // Reversed so the topmost row is the one drawn last,
                        // which is how a layer list reads everywhere; document
                        // order would put the frontmost track at the bottom.
                        ForEach(shell.effects.tracks.reversed()) { track in
                            TrackRow(
                                track: track,
                                isSelected: track.id == shell.selectedTrackID,
                                select: {
                                    shell.selectedTrackID = track.id
                                    shell.selectedNodeID = nil
                                },
                                toggleVisibility: { shell.toggleVisibility(of: track.id) },
                                toggleLock: { shell.toggleLock(of: track.id) },
                            )
                        }
                    }
                }
            }
        }
    }

    // ─── Timing ──────────────────────────────────────────────────────────────

    private var timing: some View {
        ComingSoon(
            title: "Timing points",
            detail: "Edit BPM and offset. Not implemented yet.",
            systemImage: "metronome",
        )
    }
}

// ─── Effect rows ─────────────────────────────────────────────────────────────

/// One effect available to place.
private struct EffectLibraryRow: View {
    let descriptor: EffectDescriptor
    let add: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: add) {
            HStack(spacing: Theme.Spacing.snug) {
                Image(systemName: descriptor.systemImage)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.secondary)
                    .frame(width: Theme.Size.ring * 2)

                VStack(alignment: .leading, spacing: 1) {
                    Text(descriptor.name)
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Palette.primary)
                    Text(descriptor.category)
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.tertiary)
                }

                Spacer(minLength: Theme.Spacing.tight)

                Image(systemName: "plus")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(isHovered ? Theme.Palette.primary : Theme.Palette.tertiary)
            }
            .padding(.horizontal, Theme.Spacing.snug)
            .frame(height: Theme.Size.control)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(isHovered ? Theme.Fill.rowHover : .clear)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(Theme.Motion.quick, value: isHovered)
        .help("Add \(descriptor.name) at the playhead")
    }
}

/// An effect and the presets that configure it, as one collapsible row.
private struct EffectGroup: View {
    let descriptor: EffectDescriptor
    let presets: [EffectPreset]
    let isExpanded: Bool
    let toggleExpanded: () -> Void
    let addBlank: () -> Void
    let addPreset: (EffectPreset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.hair) {
            // An effect with no presets is a single row that places it. The
            // chevron and the count are there to manage a list; with nothing to
            // list they are a control that does nothing and a "0" beside it.
            EffectHeaderRow(
                descriptor: descriptor,
                presetCount: presets.isEmpty ? nil : presets.count,
                isExpanded: isExpanded,
                toggleExpanded: presets.isEmpty ? addBlank : toggleExpanded,
                add: addBlank,
            )

            if isExpanded {
                VStack(spacing: Theme.Spacing.hair) {
                    ForEach(presets) { preset in
                        PresetRow(preset: preset) { addPreset(preset) }
                    }
                }
                // Indented so the presets read as belonging to the effect above
                // rather than as siblings of it.
                .padding(.leading, Theme.Spacing.compact)
            }
        }
        .animation(Theme.Motion.quick, value: isExpanded)
    }
}

/// The effect itself: expands its presets, or places a blank one.
private struct EffectHeaderRow: View {
    let descriptor: EffectDescriptor
    /// `nil` when the effect has no presets, which is what turns the row from a
    /// disclosure into a plain "add this".
    let presetCount: Int?
    let isExpanded: Bool
    let toggleExpanded: () -> Void
    let add: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.snug) {
            // The space is kept either way, so the icons of every row line up
            // whether or not it discloses anything.
            Image(systemName: "chevron.right")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .opacity(presetCount == nil ? 0 : 1)
                .frame(width: Theme.Size.ring * 3)

            Image(systemName: descriptor.systemImage)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.secondary)

            Text(descriptor.name)
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Palette.primary)

            Spacer(minLength: Theme.Spacing.tight)

            if let presetCount {
                Text("\(presetCount)")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.tertiary)
                    .help("\(presetCount) presets")
            }

            // Placing a blank effect stays available beside the presets: it is
            // the one anybody building something of their own reaches for.
            IconButton(
                systemImage: "plus",
                size: Theme.Size.controlTiny,
                help: presetCount == nil
                    ? "Add \(descriptor.name)"
                    : "Add a blank \(descriptor.name)",
                action: add,
            )
        }
        .padding(.horizontal, Theme.Spacing.snug)
        .frame(height: Theme.Size.control)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(isHovered ? Theme.Fill.rowHover : Theme.Fill.subtle)
        }
        .contentShape(.rect)
        .onTapGesture(perform: toggleExpanded)
        .onHover { isHovered = $0 }
        .animation(Theme.Motion.quick, value: isHovered)
    }
}

/// One preset available to place.
private struct PresetRow: View {
    let preset: EffectPreset
    let add: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: add) {
            HStack(spacing: Theme.Spacing.snug) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(preset.name)
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Palette.primary)
                    // The summary is what makes a list of names browsable:
                    // "Snow" and "Rain" are obvious, "Magic" and "Starfield"
                    // are not.
                    Text(preset.summary)
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: Theme.Spacing.tight)

                Image(systemName: "plus")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(isHovered ? Theme.Palette.primary : Theme.Palette.tertiary)
            }
            .padding(.horizontal, Theme.Spacing.snug)
            .padding(.vertical, Theme.Spacing.tight)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(isHovered ? Theme.Fill.rowHover : .clear)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(Theme.Motion.quick, value: isHovered)
        .help("Add \(preset.name) at the playhead")
    }
}

/// One filter available to apply, draggable onto a track.
///
/// Dragged rather than only clicked because that is what the hand does with a
/// library — After Effects, Premiere and Resolve all work this way, and a panel
/// of things you can only click reads as a menu rather than as a shelf.
private struct FilterLibraryRow: View {
    let descriptor: FilterDescriptor
    /// Whether there is a lane to apply to. Clicking applies to the selection;
    /// with nothing selected there is nowhere for it to go.
    let canApply: Bool
    let apply: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.snug) {
            Image(systemName: descriptor.systemImage)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.secondary)
                .frame(width: Theme.Size.ring * 2)

            VStack(alignment: .leading, spacing: 1) {
                Text(descriptor.name)
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Palette.primary)
                Text(descriptor.category)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.tertiary)
            }

            Spacer(minLength: Theme.Spacing.tight)

            Image(systemName: "line.3.horizontal")
                .font(Theme.Typography.micro)
                .foregroundStyle(isHovered ? Theme.Palette.secondary : Theme.Palette.tertiary)
        }
        .padding(.horizontal, Theme.Spacing.snug)
        .frame(height: Theme.Size.control)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(isHovered ? Theme.Fill.rowHover : .clear)
        }
        .contentShape(.rect)
        .onTapGesture { if canApply { apply() } }
        .onHover { isHovered = $0 }
        // The type carried is the filter's own, so a drop can tell a filter
        // from anything else that might be dragged over a lane.
        .draggable(FilterTransfer(type: descriptor.type).payload) {
            Label(descriptor.name, systemImage: descriptor.systemImage)
                .font(Theme.Typography.label)
                .padding(Theme.Spacing.snug)
                .background(.thinMaterial, in: Capsule())
        }
        .help(canApply
            ? "Drag onto a clip, or click to apply to the selected one"
            : "Drag onto a clip")
        .animation(Theme.Motion.quick, value: isHovered)
    }
}

/// One effect already on the timeline.
private struct PlacedEffectRow: View {
    let node: EffectNode
    let isSelected: Bool
    let select: () -> Void
    let remove: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.snug) {
            Circle()
                .fill(node.layer.tint)
                .frame(width: Theme.Size.ring, height: Theme.Size.ring)

            Text(node.name)
                .font(Theme.Typography.label)
                .foregroundStyle(node.isVisible ? Theme.Palette.primary : Theme.Palette.tertiary)
                .lineLimit(1)

            Spacer(minLength: Theme.Spacing.tight)

            // Revealed on hover: a delete button on every row turns a list into
            // a row of buttons, and the one that matters is the row itself.
            if isHovered {
                IconButton(
                    systemImage: "trash",
                    size: Theme.Size.controlTiny,
                    help: "Remove \(node.name)",
                    action: remove,
                )
            }
        }
        .padding(.horizontal, Theme.Spacing.snug)
        .frame(height: Theme.Size.control)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(isSelected ? Theme.Fill.rowSelected : (isHovered ? Theme.Fill.rowHover : .clear))
        }
        .contentShape(.rect)
        .onTapGesture(perform: select)
        .onHover { isHovered = $0 }
        .animation(Theme.Motion.quick, value: isHovered)
    }
}

// ─── Rows ────────────────────────────────────────────────────────────────────

private struct AssetRow: View {
    let asset: AssetItem
    /// Places the asset on the timeline at the playhead.
    let place: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.snug) {
            Image(systemName: asset.isMissing ? "exclamationmark.triangle" : "photo")
                .font(Theme.Typography.micro)
                .foregroundStyle(
                    asset.isMissing ? Theme.Palette.warning : Theme.Palette.tertiary,
                )
                .frame(width: Theme.Size.controlTiny)

            VStack(alignment: .leading, spacing: 0) {
                Text(asset.name)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if asset.isMissing {
                    Text("Missing")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.warning)
                }
            }

            Spacer(minLength: Theme.Spacing.tight)

            Text("\(asset.useCount)")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.tertiary)
                .help("Used by \(asset.useCount) sprites")
        }
        .padding(.horizontal, Theme.Spacing.snug)
        .padding(.vertical, Theme.Spacing.tight)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .fill(isHovered ? Theme.Fill.hover : .clear)
        }
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .help(asset.path)
        // Dragged onto a track, or double-clicked to drop at the playhead —
        // the two ways an asset gets into a timeline in any editor.
        .draggable(AssetTransfer(path: asset.path).payload) {
            Label(asset.name, systemImage: "photo")
                .font(Theme.Typography.label)
                .padding(Theme.Spacing.snug)
                .background(.thinMaterial, in: Capsule())
        }
        .onTapGesture(count: 2, perform: place)
        .help("Drag onto a track, or double-click to add at the playhead")
    }
}

private struct TrackRow: View {
    let track: EffectTrack
    let isSelected: Bool
    let select: () -> Void
    let toggleVisibility: () -> Void
    let toggleLock: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.snug) {
            Circle()
                .fill(track.layer.tint)
                .frame(width: Theme.Spacing.snug, height: Theme.Spacing.snug)

            VStack(alignment: .leading, spacing: 0) {
                Text(track.name)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(
                        track.isVisible ? Theme.Palette.secondary : Theme.Palette.tertiary,
                    )
                    .lineLimit(1)

                Text(track.nodes.count == 1 ? "1 effect" : "\(track.nodes.count) effects")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.tertiary)
            }

            Spacer(minLength: Theme.Spacing.tight)

            IconButton(
                systemImage: track.isVisible ? "eye" : "eye.slash",
                size: Theme.Size.controlTiny,
                prominence: .filled,
                isActive: track.isVisible,
                help: track.isVisible ? "Hide" : "Show",
                action: toggleVisibility,
            )

            IconButton(
                systemImage: track.isLocked ? "lock.fill" : "lock.open",
                size: Theme.Size.controlTiny,
                prominence: .filled,
                isActive: track.isLocked,
                help: track.isLocked ? "Unlock" : "Lock",
                action: toggleLock,
            )
        }
        .padding(.horizontal, Theme.Spacing.snug)
        .padding(.vertical, Theme.Spacing.tight)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .fill(fill)
        }
        .contentShape(.rect)
        .onTapGesture(perform: select)
        .onHover { isHovered = $0 }
        .animation(Theme.Motion.quick, value: isSelected)
        .animation(Theme.Motion.quick, value: isHovered)
    }

    /// Selection wins over hover, so pointing at the selected row does not dim
    /// it back down.
    private var fill: Color {
        if isSelected { return Theme.Fill.selected }
        return isHovered ? Theme.Fill.hover : .clear
    }
}
