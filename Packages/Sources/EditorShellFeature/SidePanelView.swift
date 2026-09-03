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

    /// What is typed into the search box.
    @State private var query = ""

    /// Categories the user has folded away.
    ///
    /// Held as what is *closed* rather than what is open, so the default —
    /// nothing in the set — is everything visible. A new category added later
    /// appears rather than hiding, which is the right way round for a list that
    /// is still growing.
    @State private var collapsed: Set<LibraryCategory> = []

    /// What the preset list is narrowed to, or nothing for everything.
    @State private var selectedFilter: PresetFilter?

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
        VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
            tools
            search
            packFilter

            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.hair) {
                    ForEach(visiblePresets, id: \.id) { preset in
                        PresetRow(preset: preset) { shell.addPreset(preset, at: playheadTime) }
                            .previewOnHover(title: preset.name, summary: preset.summary) {
                                shell.previewImage?(.preset(preset)) ?? []
                            }
                    }

                    if visiblePresets.isEmpty {
                        Text("Nothing matches")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Palette.tertiary)
                            .padding(.top, Theme.Spacing.compact)
                    }
                }
            }
            // A new scroll view per filter, rather than scrolling the old one
            // back.
            //
            // A scroll view keeps its offset and the next list is usually
            // shorter, so switching tabs while scrolled down left the panel
            // parked past the end of the new one, showing nothing until it was
            // dragged back by hand.
            //
            // `scrollTo` cannot fix it: the anchor lives in a `LazyVStack`,
            // which does not build what is off screen — scrolled to the bottom
            // there is no top view to scroll to. Changing the identity throws
            // the offset away with the view, and a fresh one starts at the top
            // by definition.
            .id("presets-\(String(describing: selectedFilter))-\(query)")
        }
    }

    /// What can be created, as a row of buttons.
    ///
    /// Separated from the presets because they are different kinds of thing: a
    /// tool is *what you can make*, a preset is *something already made*. In one
    /// list they read as peers, and the list grows past reading — which is how
    /// three levels of folding appeared for four packs holding one preset each.
    ///
    /// This is the split every editor makes between a toolbar and an asset
    /// library, and the reason a toolbar is always visible while a library is
    /// browsed.
    private var tools: some View {
        HStack(spacing: Theme.Spacing.tight) {
            ForEach(shell.library.descriptors, id: \.type) { descriptor in
                // `IconButton`, not a `Button` with a frame on its label.
                //
                // The hand-rolled version asked for a `control`-sized frame
                // inside a `small` style, so the two fought: the glyph was
                // drawn for 22pt in a box demanding 34. The primitive derives
                // the glyph size **and** the corner radius from its own size,
                // which is the rule this design system already states.
                IconButton(
                    systemImage: descriptor.systemImage,
                    size: Theme.Size.controlSmall,
                    help: "Add \(descriptor.name)",
                ) {
                    shell.addEffect(descriptor, at: playheadTime)
                }
                .previewOnHover(title: descriptor.name) {
                    shell.previewImage?(.effect(descriptor)) ?? []
                }
            }
        }
        // Centred, and only as wide as the tools themselves: a toolbar pinned
        // to one edge of a panel this narrow reads as the first row of the list
        // below it rather than as its own thing.
        .frame(maxWidth: .infinity)
    }

    /// Which pack the list is showing, as a row of chips.
    ///
    /// A filter rather than a container. Packs nested inside a "Packs" heading
    /// put a category above the categories — three levels deep for a library
    /// this size, and two chevrons that looked identical without meaning the
    /// same thing.
    @ViewBuilder
    private var packFilter: some View {
        // Effects first, then packs.
        //
        // Chips that only named packs reached seven presets out of thirty-seven:
        // everything from the text effect and every plain emitter preset
        // belonged to no pack, so each chip held one or two while "All" held
        // the rest. A filter that leaves most of the library unreachable is one
        // that was not finished.
        //
        // By effect rather than by inventing a "Basics" pack for the leftovers:
        // a text preset genuinely *is* a text preset, while "Basics" would mean
        // "the others" — a name for a gap rather than for a thing.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.hair) {
                chip(nil, label: "All")

                ForEach(shell.library.descriptors, id: \.type) { descriptor in
                    if shell.presets.contains(where: {
                        $0.effectType == descriptor.type && $0.pack == nil
                    }) {
                        chip(.effect(descriptor.type), label: descriptor.name)
                    }
                }

                ForEach(shell.packs.map(\.name), id: \.self) { pack in
                    chip(.pack(pack), label: pack)
                }
            }
        }
        // The row is chips, not a scrolling region: without this it takes
        // whatever height a scroll view asks for, which is all of it.
        .frame(height: Theme.Size.controlSmall)
    }

    private func chip(_ filter: PresetFilter?, label: String) -> some View {
        Button {
            selectedFilter = filter
        } label: {
            Text(label)
                .font(Theme.Typography.micro)
                .padding(.horizontal, Theme.Spacing.compact)
                .frame(height: Theme.Size.controlSmall)
                .background {
                    Capsule().fill(
                        selectedFilter == filter ? Theme.Fill.selected : Theme.Fill.well,
                    )
                }
                .foregroundStyle(
                    selectedFilter == filter ? Theme.Palette.primary : Theme.Palette.secondary,
                )
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ category: LibraryCategory) {
        if collapsed.contains(category) {
            collapsed.remove(category)
        } else {
            collapsed.insert(category)
        }
    }

    /// The presets on show: everything, or one pack, narrowed by the search.
    private var visiblePresets: [EffectPreset] {
        shell.presets.filter { preset in
            let kept = switch selectedFilter {
            case .none: true
            // An effect's chip shows its own presets, not the packs built from
            // it: a pack is a thing in its own right and has a chip of its own.
            case let .effect(type): preset.effectType == type && preset.pack == nil
            case let .pack(name): preset.pack == name
            }
            return kept && matches(preset.name)
        }
    }


    /// Whether a name and its presets match what is typed.
    ///
    /// Matched on the preset names too, not only the effect's: someone hunting
    /// for "portal" is looking for a preset, and a search that only reads the
    /// row above it would come back empty on the thing they can see in the
    /// panel.
    private func matches(_ name: String, presets: [EffectPreset] = []) -> Bool {
        guard !query.isEmpty else { return true }
        let needle = query.lowercased()
        return name.lowercased().contains(needle)
            || presets.contains { $0.name.lowercased().contains(needle) }
    }

    /// Filters the library as you type.
    ///
    /// Search beats hierarchy once a list stops fitting on screen: the groups
    /// are for browsing, this is for when you already know the name. After
    /// Effects puts one at the top of its effects panel for the same reason —
    /// nobody opens six folders to find something they can spell.
    private var search: some View {
        HStack(spacing: Theme.Spacing.snug) {
            Image(systemName: "magnifyingglass")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.tertiary)

            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .font(Theme.Typography.label)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Spacing.compact)
        .frame(height: Theme.Size.controlSmall)
        .surface(.inset, radius: Theme.Radius.control)
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

            search

            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    // Grouped by what a filter does, not by the order they were
                    // written. Nine in a flat list was already past the point
                    // where anyone reads it as a list rather than as a wall.
                    //
                    // Headings are dropped while searching: with the list cut
                    // to two matches, six headings above them are the noise the
                    // search was meant to remove.
                    ForEach(LibraryCategory.displayOrder, id: \.self) { category in
                        let inCategory = shell.filterDescriptors.filter {
                            $0.category == category && matches($0.name)
                        }

                        if !inCategory.isEmpty {
                            if query.isEmpty {
                                CategoryHeader(
                                    category: category,
                                    count: inCategory.count,
                                    isExpanded: !collapsed.contains(category),
                                    toggle: { toggle(category) },
                                )
                            }

                            if query.isEmpty ? !collapsed.contains(category) : true {
                            ForEach(inCategory, id: \.type) { descriptor in
                                FilterLibraryRow(
                                    descriptor: descriptor,
                                    canApply: shell.selectedEffect != nil,
                                    apply: {
                                        guard let node = shell.selectedEffect else { return }
                                        shell.addFilter(descriptor, to: node.id)
                                    },
                                )
                                .previewOnHover(title: descriptor.name) {
                                    shell.previewImage?(.filter(descriptor)) ?? []
                                }
                            }
                            }
                        }
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
                    Text(descriptor.category.rawValue)
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

/// A category heading that folds the rows under it away.
///
/// After Effects' shape, and worth copying once a library outgrows one screen:
/// closing what you are not using is the difference between a list and a wall.
/// What is **not** copied is starting everything collapsed — AE ships two
/// hundred effects, so it has to; twenty means every session would begin with
/// six clicks before anything is visible.
private struct CategoryHeader: View {
    let category: LibraryCategory
    let count: Int
    let isExpanded: Bool
    let toggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Theme.Spacing.snug) {
                Image(systemName: "chevron.right")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: Theme.Size.hairline * 8)

                Image(systemName: category.systemImage)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.tertiary)

                Text(category.rawValue)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.secondary)

                Spacer(minLength: 0)

                // The count stays while the group is shut, which is what makes
                // a closed heading worth reading rather than just a lid.
                Text("\(count)")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.tertiary)
            }
            .padding(.horizontal, Theme.Spacing.compact)
            .frame(height: Theme.Size.controlSmall)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(isHovered ? Theme.Fill.rowHover : .clear)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// A pack of built effects, as one collapsible row.
///
/// Shaped like `EffectGroup` on purpose: a pack is browsed the same way an
/// effect's presets are, and giving it its own visual language would make two
/// things that behave alike look unrelated.
private struct PackGroup: View {
    let name: String
    let presets: [EffectPreset]
    let isExpanded: Bool
    let toggleExpanded: () -> Void
    let addPreset: (EffectPreset) -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.hair) {
            Button(action: toggleExpanded) {
                HStack(spacing: Theme.Spacing.snug) {
                    Image(systemName: "chevron.right")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))

                    Image(systemName: "shippingbox")
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Palette.secondary)
                        .frame(width: Theme.Size.ring * 2)

                    // No "Pack" subtitle: the heading above already says it,
                    // and a row that repeats its own group costs twice the
                    // height to say nothing new.
                    Text(name)
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Palette.primary)

                    Spacer(minLength: 0)

                    Text("\(presets.count)")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.tertiary)
                }
                .padding(.horizontal, Theme.Spacing.compact)
                .frame(height: Theme.Size.control)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(isHovered ? Theme.Fill.rowHover : .clear)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }

            if isExpanded {
                VStack(spacing: Theme.Spacing.hair) {
                    ForEach(presets) { preset in
                        PresetRow(preset: preset) { addPreset(preset) }
                    }
                }
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
            // Indented past where the heading's chevron sits, so a row reads as
            // belonging to the group above it rather than as a sibling of it.
            // The width matches the chevron's exactly: eyeballing the gap is
            // how a list ends up almost aligned, which is worse than not.
            Color.clear.frame(width: Theme.Size.hairline * 8, height: 0)

            Image(systemName: descriptor.systemImage)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.secondary)

            // No category subtitle: the heading above already says it, and a
            // row repeating its own group costs twice the height to say nothing
            // new. The same redundancy the pack rows had.
            Text(descriptor.name)
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Palette.primary)

            Spacer(minLength: Theme.Spacing.tight)

            Image(systemName: "line.3.horizontal")
                .font(Theme.Typography.micro)
                .foregroundStyle(isHovered ? Theme.Palette.secondary : Theme.Palette.tertiary)
        }
        // The heading's padding, so the two line up down the left edge.
        .padding(.horizontal, Theme.Spacing.compact)
        .frame(height: Theme.Size.controlSmall)
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
                .fill(track.tint)
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

/// A picture of what something does, shown on hover.
///
/// A library of names alone is one you have to place things out of to find out
/// what they are. The image answers "what is this?" in the time it takes to
/// look, which is the question someone browsing has — and it is rendered by the
/// same engine that draws the canvas, so it cannot drift from what the thing
/// actually produces.
private struct PreviewPopover: View {
    let title: String
    let summary: String?
    let frames: [CGImage]

    /// Which frame is showing.
    @State private var index = 0

    /// Twelve frames over a second and a half, looping.
    ///
    /// A still could not tell two text presets apart: the difference between a
    /// typewriter and a fade is **when** each letter arrives, and every frame
    /// after the entrance shows the same settled word. Motion is the answer to
    /// a question a picture cannot be asked.
    private let interval = 0.125

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
            if !frames.isEmpty {
                Image(decorative: frames[min(index, frames.count - 1)], scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 240, height: 135)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    .task {
                        // Driven while the popover is up and cancelled with it,
                        // so a closed preview costs nothing.
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .seconds(interval))
                            index = (index + 1) % frames.count
                        }
                    }
            }

            Text(title)
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Palette.primary)

            if let summary, !summary.isEmpty {
                Text(summary)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.tertiary)
                    .frame(width: 240, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Spacing.compact)
    }
}

/// Shows a preview beside a row after the pointer has settled on it.
///
/// Delayed, because a preview that appears the instant the pointer crosses a
/// row flashes open and shut all the way down a list — the same reason a
/// tooltip waits. Long enough to mean "I stopped here", short enough not to
/// feel like waiting.
private struct PreviewOnHover: ViewModifier {
    let title: String
    let summary: String?
    let frames: () -> [CGImage]

    @State private var isShowing = false
    @State private var task: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                task?.cancel()
                guard inside else {
                    isShowing = false
                    return
                }
                task = Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    guard !Task.isCancelled else { return }
                    isShowing = true
                }
            }
            // Dismissed on the way down, before the click lands.
            //
            // A popover takes every click over its own area and opens across
            // the row that summoned it, so the button underneath stopped
            // answering the moment a preview appeared — adding an effect took
            // several tries. Closing it as the mouse goes down hands the click
            // straight back to the row.
            //
            // An overlay would sidestep the problem and bring a worse one: the
            // panel clips its contents, so a preview wide enough to be useful
            // would be cut off at the edge.
            // Shown only while the pointer is still, and gone the moment it
            // moves again.
            //
            // A popover takes every click over its own area and opens across
            // the row that summoned it, so the button underneath stopped
            // answering as soon as a preview appeared — adding an effect took
            // several tries. Dismissing on the click was the obvious patch and
            // the wrong one: it costs a click to close and another to act.
            //
            // Tying it to stillness fixes the cause instead. Nobody clicks
            // without moving to what they are clicking, so by the time the
            // press lands the preview is already out of the way — and a preview
            // that answers "what is this?" is wanted while looking, not while
            // reaching.
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    guard !isShowing else { break }
                    task?.cancel()
                    task = Task {
                        try? await Task.sleep(for: .milliseconds(500))
                        guard !Task.isCancelled else { return }
                        isShowing = true
                    }
                case .ended:
                    task?.cancel()
                    isShowing = false
                @unknown default:
                    break
                }
            }
            .popover(isPresented: $isShowing, arrowEdge: .trailing) {
                PreviewPopover(title: title, summary: summary, frames: frames())
            }
    }
}

private extension View {
    func previewOnHover(
        title: String,
        summary: String? = nil,
        frames: @escaping () -> [CGImage],
    ) -> some View {
        modifier(PreviewOnHover(title: title, summary: summary, frames: frames))
    }
}

/// What the preset list is narrowed to.
private enum PresetFilter: Hashable {
    case effect(String)
    case pack(String)
}
