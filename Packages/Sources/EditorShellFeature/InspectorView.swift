import Foundation
import DesignSystem
import StoryboardCore
import SwiftUI

/// The right panel: the selected effect's parameters.
///
/// The controls are generated from the effect's declaration, never written per
/// effect. That is the whole point of the descriptor: this panel is told what a
/// parameter is and what it accepts, and is never told whether the effect
/// behind it is native or scripted.
///
/// A track that came from a parsed `.osb` has no descriptor, so those still
/// show the sample properties until there is something real to bind to.
struct InspectorView: View {
    /// Fixed width, so the shell can size the workspace around the canvas.
    static let width: CGFloat = 264

    let shell: EditorShellModel

    /// The playhead, read from the model rather than received as a property.
    ///
    /// Handed down as one, this panel was rebuilt on every frame of playback —
    /// measured at 25 to 35 times a second, for a value used in exactly two
    /// places and shown in none. SwiftUI rebuilds a view when a stored property
    /// changes, and the clock changes sixty times a second.
    ///
    /// `@ObservationIgnored` on the model's side is what makes this work: the
    /// value is there to be read when a keyframe needs placing, and reading it
    /// does not sign the panel up to redraw with the clock.
    private var playheadTime: Double { shell.playheadTime }


    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                // Lazy, so a panel is built as far as it is seen.
                //
                // A plain `VStack` builds every row at once, and an emitter has
                // thirty parameters — several of them `Menu`s and colour wells,
                // which are AppKit controls underneath. Measured: the body
                // returned in 2ms and the panel took 83 to 207ms to appear,
                // which is the cost of instantiating those controls rather than
                // of deciding what to draw. `LazyVStack` builds the rows that
                // are on screen and leaves the rest until they scroll into
                // view.
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.compact) {
                    trackSummary

                    if let node = shell.selectedEffect, let descriptor = shell.selectedDescriptor {
                        effectParameters(descriptor: descriptor, node: node)
                    } else if let track = shell.selectedTrack {
                        trackParameters(track)
                    } else {
                        ComingSoon(
                            title: "Nothing selected",
                            detail: "Pick a clip on the timeline to edit what it does.",
                            systemImage: "sparkles",
                        )
                    }

                    // Filters belong to the lane, so they show whenever there
                    // is one — with or without a clip selected. Tucked inside
                    // the track branch, they vanished the moment a clip was
                    // picked, which is exactly when someone reaches for them.
                    // Only when there is something to show: an empty "Filters"
                    // group is a heading and a button standing in for nothing,
                    // and the library tab is where filters are found anyway.
                    // A clip's filters, under whatever it is. They belong to
                    // the clip now, so they show wherever it does.
                    if let node = shell.selectedEffect, !node.filters.isEmpty {
                        filterSection(node)
                    }
                }
                .padding(Theme.Spacing.compact)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .surface(.panel)
    }

    /// The filters applied to a lane, and a way to add one.
    ///
    /// On the track rather than on each clip: a look belongs to the lane, which
    /// is already the unit of grouping and of draw order.
    /// Where the playhead sits inside a clip, clamped to it.
    ///
    /// Keyframe times are clip-local, and a key past the end names a moment the
    /// clip never reaches. Read from `playheadTime` — the `@ObservationIgnored`
    /// copy — because the inspector must not rebuild with the clock.
    private func localTime(in node: EffectNode) -> Double {
        max(0, min(shell.playheadTime - node.startTime, node.duration))
    }

    @ViewBuilder
    private func filterSection(_ node: EffectNode) -> some View {
        FieldGroup("Filters") {
            ForEach(node.filters) { filter in
                if let descriptor = shell.filters.descriptor(for: filter.type) {
                    FilterCard(
                        descriptor: descriptor,
                        filter: filter,
                        toggle: { shell.toggleFilter(filter.id, in: node.id) },
                        remove: { shell.removeFilter(filter.id, from: node.id) },
                        isDrawingPath: shell.isDrawingPath,
                        onToggleDrawing: { shell.isDrawingPath.toggle() },
                        onEditingChanged: { isEditing in
                            isEditing ? shell.beginGesture() : shell.endGesture()
                        },
                        onChange: { parameter, value in
                            shell.setFilterValue(
                                value, for: parameter, on: filter.id, in: node.id,
                            )
                        },
                        keyTime: localTime(in: node),
                        animation: {
                            shell.filterAnimation($0, on: filter.id, in: node.id)
                        },
                        animatedValue: { parameter in
                            guard shell.filterAnimation(
                                parameter, on: filter.id, in: node.id,
                            )?.isActive == true else { return nil }
                            // The **observed** clock, and only here.
                            //
                            // `playheadTime` is deliberately unobserved so the
                            // panel does not rebuild sixty times a second — and
                            // the cost is that a number read from it is
                            // whatever it was at the last rebuild. A field
                            // showing 5 while the timeline says 20 is the panel
                            // reporting a moment that has passed.
                            //
                            // Read here it costs a rebuild per frame *only for
                            // a clip with an animated filter selected*, which
                            // is exactly when the number has to move.
                            return shell.filterValue(
                                parameter, on: filter.id, in: node.id,
                                at: max(0, min(
                                    shell.observedPlayheadTime - node.startTime,
                                    node.duration,
                                )),
                            )
                        },
                        beginAnimating: { parameter in
                            shell.beginAnimatingFilter(
                                parameter, on: filter.id, in: node.id,
                                at: localTime(in: node),
                            )
                        },
                        setAnimationEnabled: { parameter, isEnabled in
                            shell.setFilterAnimationEnabled(
                                isEnabled, for: parameter, on: filter.id, in: node.id,
                                at: localTime(in: node),
                            )
                        },
                        addKeyframe: { parameter, value in
                            shell.setFilterKeyframe(
                                value, for: parameter, on: filter.id, in: node.id,
                                at: localTime(in: node),
                            )
                        },
                        clearAnimation: { parameter in
                            shell.clearFilterAnimation(
                                for: parameter, on: filter.id, in: node.id,
                                keeping: localTime(in: node),
                            )
                        },
                        // Keyframe times are local to the clip; a seek is song
                        // time. Without the clip's start added back, every jump
                        // would land near the top of the song.
                        goToTime: { shell.seekHandler?(node.startTime + $0) },
                    )
                }
            }

            // A loop's pass starts from an empty screen, so a continuous
            // emitter visibly thins at every seam. Said here rather than left
            // for someone to wonder why their fire flickers.
            // Two mirrors on the same axis cancel out.
            //
            // The second reflects everything the first produced, and a
            // reflection of a reflection lands back on the original — so four
            // sprites occupy two positions and the picture is unchanged while
            // the file has doubled. It reads as the filter having been lost,
            // which is what makes it worth saying rather than leaving someone
            // to work out.
            if let cancelling = cancellingMirrors(node) {
                Text("Two mirrors on the \(cancelling) axis undo each other — "
                    + "the reflections land back on the originals, doubling the "
                    + "file for no visible change.")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            let seam = shell.loopSeamSeverity(for: node.id)
            if seam > 0.25 {
                Text("Most particles are still alive when the loop restarts — "
                    + "expect a visible break at each repeat. A shorter Life, "
                    + "or a longer clip, softens it.")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // A glow over a large emitter is a file osu! will not open. Said
            // here, where it can still be turned down, rather than at export.
            let multiplier = shell.spriteMultiplier(for: node.id)
            if multiplier > 1 {
                Text("Sprites ×\(String(format: "%.0f", multiplier))")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(multiplier >= 5 ? Theme.Palette.warning : Theme.Palette.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Which axis has two enabled mirrors on it, if any.
    private func cancellingMirrors(_ node: EffectNode) -> String? {
        let axes = node.filters
            .filter { $0.isEnabled && $0.type == MirrorFilter.descriptor.type }
            .map { filter -> String in
                if case let .choice(axis) = filter.values[MirrorFilter.Param.axis] { return axis }
                return MirrorFilter.Axis.horizontal.rawValue
            }

        let repeated = Dictionary(grouping: axes, by: { $0 }).first { $0.value.count > 1 }
        return repeated?.key.lowercased()
    }

    /// The selected effect's declared parameters, grouped as it declared them.
    @ViewBuilder
    private func effectParameters(descriptor: EffectDescriptor, node: EffectNode) -> some View {
        timingRow(node: node)
        selectedKeyframeSection(node)
        selectedFilterKeyframeSection(node)
        transformSection(node)

        // A group whose parameters are all conditioned out drops with them.
        //
        // Filtering only the controls left the heading behind — an empty
        // "Shape" sitting under the sprite picker with nothing beneath it,
        // which reads as something failing to load rather than as a group that
        // does not apply.
        ForEach(descriptor.groups.filter { group in
            descriptor.parameters.contains {
                $0.group == group && ($0.shownWhen?.holds(in: node.values) ?? true)
            }
        }, id: \.self) { group in
            FieldGroup(group) {
                // Conditional parameters drop out when their condition does
                // not hold: a ring's thickness on a square is a control that
                // does nothing, and a control that does nothing lies.
                ForEach(
                    descriptor.parameters.filter {
                        $0.group == group && ($0.shownWhen?.holds(in: node.values) ?? true)
                    },
                    id: \.id,
                ) { parameter in
                    ParameterControl(
                        parameter: parameter,
                        value: node.values[parameter.id] ?? parameter.defaultValue,
                        onChange: { shell.setValue($0, for: parameter.id, on: node.id) },
                        onEditingChanged: { isEditing in
                            isEditing ? shell.beginGesture() : shell.endGesture()
                        },
                    )
                }
            }
        }

        layerSections(node)
    }

    /// A compound effect's further layers, each with its own parameters.
    ///
    /// Open rather than behind a picker: a compound is one thing made of
    /// several, and what someone does with it is compare them — brighten the
    /// core against the haze, thin the embers against the flame. A picker makes
    /// that two clicks per glance and hides that the layers exist at all.
    @ViewBuilder
    private func layerSections(_ node: EffectNode) -> some View {
        ForEach(node.layers) { layer in
            if let descriptor = shell.library.descriptor(for: layer.type) {
                LayerSection(
                    layer: layer,
                    descriptor: descriptor,
                    toggle: { shell.toggleLayerVisibility(layer.id, in: node.id) },
                    onChange: { parameter, value in
                        shell.setLayerValue(
                            value, for: parameter, onLayer: layer.id, in: node.id,
                        )
                    },
                )
            }
        }
    }

    /// The selected keyframe: its time, its value, and the curve leaving it.
    ///
    /// Above the transform group, because a selected key is what someone is
    /// working on right now — and because a curve is not something a diamond on
    /// a timeline can show or a drag can set.
    @ViewBuilder
    private func selectedKeyframeSection(_ node: EffectNode) -> some View {
        if let selection = shell.selectedKeyframe,
           selection.nodeID == node.id,
           let key = shell.selectedKeyframeValue
        {
            FieldGroup("Keyframe · \(selection.property.title)") {
                PropertyRow("Time") {
                    NumberField(
                        value: Binding(
                            get: { key.time },
                            set: {
                                shell.moveKeyframe(
                                    key.id, in: selection.property, to: $0, on: node.id,
                                )
                            },
                        ),
                        unit: "ms",
                        step: 10,
                        range: 0...node.duration,
                        format: "%.0f",
                    )
                }

                PropertyRow("Value") {
                    NumberField(
                        value: Binding(
                            get: { key.value },
                            set: {
                                shell.setKeyframeValue(
                                    $0, for: key.id, in: selection.property, on: node.id,
                                )
                            },
                        ),
                        unit: selection.property.unit,
                        step: selection.property.step,
                        range: selection.property.range,
                        format: selection.property.step < 1 ? "%.2f" : "%.0f",
                    )
                }

                // The curve belongs to the key it leaves *from*, which is how a
                // storyboard command carries its own easing.
                PropertyRow("Easing") {
                    MenuField(
                        items: KeyframeEasing.allCases.map(EasingOption.init),
                        selection: Binding(
                            get: { EasingOption(KeyframeEasing.matching(key.easing)) },
                            set: {
                                shell.setKeyframeEasing(
                                    $0.curve.easing,
                                    for: key.id,
                                    in: selection.property,
                                    on: node.id,
                                )
                            },
                        ),
                        label: \.title,
                    )
                }

                Button("Delete Keyframe", systemImage: "trash", role: .destructive) {
                    shell.removeKeyframe(key.id, from: selection.property, on: node.id)
                }
                .font(Theme.Typography.micro)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// The selected filter key: its time, value, curve and a way to delete it.
    ///
    /// The same four controls the transform's selected key gets, because a
    /// keyframe is a keyframe wherever it came from. Without this, a filter key
    /// could be clicked and highlighted and then not edited at all — selected
    /// and inert, which is worse than not selectable.
    @ViewBuilder
    private func selectedFilterKeyframeSection(_ node: EffectNode) -> some View {
        if let selection = shell.selectedFilterKeyframe,
           selection.nodeID == node.id,
           let key = shell.selectedFilterKeyframeValue,
           let filter = node.filters.first(where: { $0.id == selection.filterID }),
           let descriptor = shell.filters.descriptor(for: filter.type),
           let parameter = descriptor.parameter(selection.parameter)
        {
            FieldGroup("Keyframe · \(descriptor.name) · \(parameter.name)") {
                PropertyRow("Time") {
                    NumberField(
                        value: Binding(
                            get: { key.time },
                            set: {
                                shell.moveFilterKeyframe(
                                    key.id, for: selection.parameter,
                                    on: selection.filterID, in: node.id, to: $0,
                                )
                            },
                        ),
                        unit: "ms",
                        step: 10,
                        range: 0...node.duration,
                        format: "%.0f",
                    )
                }

                PropertyRow("Value") {
                    NumberField(
                        value: Binding(
                            get: { key.value },
                            set: {
                                shell.setFilterKeyframeValue(
                                    $0, for: key.id, on: selection.parameter,
                                    filterID: selection.filterID, in: node.id,
                                )
                            },
                        ),
                        // Straight off the declaration, so a key obeys the same
                        // bounds and step as the field that plants it.
                        unit: parameter.unit,
                        step: parameter.step ?? 1,
                        // A parameter without declared bounds accepts anything,
                        // so the field must not invent a limit the value itself
                        // does not have.
                        range: parameter.range ?? -.greatestFiniteMagnitude...(.greatestFiniteMagnitude),
                        format: (parameter.step ?? 1) < 1 ? "%.2f" : "%.0f",
                    )
                }

                PropertyRow("Easing") {
                    MenuField(
                        items: KeyframeEasing.allCases.map(EasingOption.init),
                        selection: Binding(
                            get: { EasingOption(KeyframeEasing.matching(key.easing)) },
                            set: {
                                shell.setFilterKeyframeEasing(
                                    $0.curve.easing, for: key.id,
                                    on: selection.parameter,
                                    filterID: selection.filterID, in: node.id,
                                )
                            },
                        ),
                        label: \.title,
                    )
                }

                Button("Delete Keyframe", systemImage: "trash", role: .destructive) {
                    shell.removeFilterKeyframe(
                        key.id, for: selection.parameter,
                        on: selection.filterID, in: node.id,
                    )
                }
                .font(Theme.Typography.micro)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Position, scale, rotation and opacity — the properties that animate.
    ///
    /// Its own group, above the effect's own parameters. Transform is what
    /// every visual thing has and what people reach for first; mixed in with an
    /// emitter's twenty-eight parameters it would be lost among them.
    @ViewBuilder
    private func transformSection(_ node: EffectNode) -> some View {
        FieldGroup("Transform") {
            // What animating this clip costs.
            //
            // osu! has no nested sprites, so moving a clip means moving each of
            // its sprites and baking a rotation into each one's path. On an
            // emitter with hundreds of particles that is thousands of lines —
            // worth knowing here, where it can still be turned down, rather
            // than when the file will not open.
            transformCost(node)
            alignRow
            ForEach(TransformProperty.allCases, id: \.self) { property in
                // The three channels are one property to anyone using them, so
                // green and blue are not rows of their own: red carries the
                // colour well, and its stopwatch animates all three together.
                if property == .green || property == .blue {
                    EmptyView()
                } else {
                    transformRow(property, node: node)
                    // The link is drawn across the pair rather than between
                    // them: a row of its own took a whole row's height to say
                    // something about its neighbours, and floated free of both.
                    // Overlaid on the second axis, it reads as joining the two.
                    .overlay(alignment: .topTrailing) {
                        if property == .scaleY { scaleLink }
                    }
                    // Room for the link to sit beside the column rather than
                    // over the panel's edge.
                    .padding(.trailing, property == .scaleX || property == .scaleY
                        ? Theme.Size.controlTiny
                        : 0)
                }
            }
        }
    }

    /// Ties the two scale axes together.
    ///
    /// Sits in the gutter beside the stopwatches, aligned with them, and spans
    /// upward into the gap between the rows — the shape a chain link has in
    /// every editor that pairs two fields.
    private var scaleLink: some View {
        IconButton(
            systemImage: shell.scaleIsLinked ? "link" : "link.badge.plus",
            size: Theme.Size.controlTiny,
            isActive: shell.scaleIsLinked,
            help: shell.scaleIsLinked
                ? "Scale axes are linked — drag or type to scale both"
                : "Scale axes move independently",
        ) {
            shell.scaleIsLinked.toggle()
        }
        // Out past the stopwatches and up into the gap between the rows.
        //
        // Sitting in their column it read as a third one, and its background
        // touched the rows above and below — a control that joins two fields
        // has to sit clear of both to look like it spans them.
        .offset(x: Theme.Size.controlTiny, y: -Theme.Size.controlTiny / 2)
    }

    @ViewBuilder
    private func transformRow(_ property: TransformProperty, node: EffectNode) -> some View {
        TransformRow(
                    property: property,
                    track: node.transform[property],
                    current: node.transform.value(
                        property,
                        at: playheadTime - node.startTime,
                    ),
                    // Local to the clip, which is what a keyframe's time means.
                    localTime: playheadTime - node.startTime,
                    duration: node.duration,
                    setValue: { value, time in
                        // The distinction that fixes the bug: with animation
                        // off this is the property's resting value; with it on,
                        // it is a keyframe at the playhead. Always keyframing
                        // meant moving the playhead and typing a number planted
                        // keys on properties nobody was animating.
                        if property == .scaleX || property == .scaleY {
                            // Through the model, which carries the other axis
                            // with it when the two are linked.
                            shell.setScale(value, for: property, on: node.id, at: time)
                        } else if node.transform[property].isEmpty {
                            shell.setTransformValue(value, for: property, on: node.id)
                        } else {
                            shell.setKeyframe(value, for: property, at: time, on: node.id)
                        }
                    },
                    beginAnimating: { time in
                        shell.beginAnimating(property, on: node.id, at: time)
                    },
                    setEnabled: { isEnabled, time in
                        shell.setAnimationEnabled(
                            isEnabled, for: property, on: node.id, keeping: time,
                        )
                    },
            clear: { time in
                shell.clearKeyframes(for: property, on: node.id, keeping: time)
            },
        )
    }

    /// Sends the clip to a stage landmark.
    ///
    /// Beside the position fields rather than in a toolbar, because that is
    /// what it edits: aligning is a way of setting x and y, and putting it
    /// where those live means it is found by anyone already adjusting them.
    ///
    /// Snapping covers this once a hand is already close; these are for "put it
    /// in the middle", which is a thing to state rather than to approximate.
    /// Its own full-width row rather than a `PropertyRow`.
    ///
    /// A property row is the width of one control, and six buttons in it spill
    /// out of the panel — the same overflow a three-control row already caused
    /// once. Given the whole width they space out evenly, which is how every
    /// editor draws this strip.
    @ViewBuilder
    private var alignRow: some View {
        HStack(spacing: Theme.Spacing.snug) {
            // The same label column the property rows use, so the strip lines
            // up with the fields under it rather than starting at the panel
            // edge on its own.
            Text("Align")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.tertiary)
                .frame(width: Theme.Size.propertyLabel, alignment: .leading)

            HStack(spacing: 0) {
                ForEach(StageSnap.Alignment.allCases, id: \.self) { alignment in
                    IconButton(
                        systemImage: alignment.systemImage,
                        size: Theme.Size.controlTiny,
                        help: alignment.rawValue,
                    ) {
                        shell.align(alignment)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// A line saying what an animated transform adds, when it adds enough to
    /// matter.
    @ViewBuilder
    private func transformCost(_ node: EffectNode) -> some View {
        let perSprite = GroupTransform.estimatedCommandsPerSprite(node.transform)
        let sprites = shell.spriteCount(of: node)
        let total = perSprite * sprites

        if total > 0 {
            Text("Adds ~\(total) commands across \(sprites) sprites")
                .font(Theme.Typography.micro)
                .foregroundStyle(total >= 3000 ? Theme.Palette.warning : Theme.Palette.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Where the effect sits and how long it runs.
    ///
    /// Kept out of the declared parameters because every effect has these and
    /// none should have to declare them — and because the timeline edits the
    /// same two values by dragging.
    @ViewBuilder
    private func timingRow(node: EffectNode) -> some View {
        FieldGroup("Timing") {
            PropertyRow("Start") {
                NumberField(
                    value: Binding(
                        get: { node.startTime },
                        set: { shell.moveEffect(node.id, to: $0) },
                    ),
                    unit: "ms",
                    step: 50,
                    range: 0...600_000,
                    format: "%.0f",
                )
            }
            PropertyRow("Duration") {
                NumberField(
                    value: Binding(
                        get: { node.duration },
                        set: {
                            shell.resizeEffect(node.id, startTime: node.startTime, duration: $0)
                        },
                    ),
                    unit: "ms",
                    step: 50,
                    range: 100...600_000,
                    format: "%.0f",
                )
            }
        }
    }

    /// What a lane has, when the lane is the selection.
    ///
    /// Shown for a track holding several clips: there is no single effect to
    /// edit, and the honest answer is the lane's own properties rather than one
    /// of its clips picked arbitrarily.
    @ViewBuilder
    private func trackParameters(_ track: EffectTrack) -> some View {
        FieldGroup("Track") {
            PropertyRow("Name") {
                TextInputField(
                    text: Binding(
                        get: { track.name },
                        set: { shell.renameTrack(track.id, to: $0) },
                    ),
                )
            }
            PropertyRow("Layer") {
                MenuField(
                    items: Layer.allCases.map(LayerOption.init),
                    selection: Binding(
                        get: { LayerOption(track.layer) },
                        set: { shell.setLayer($0.layer, on: track.id) },
                    ),
                    label: \.title,
                )
            }

            // Beside the name and the layer, which is what a track's panel is
            // for. Buried in a context menu it was a setting you had to know
            // was there.
            PropertyRow("Colour") {
                MenuField(
                    items: TrackColourOption.all,
                    selection: Binding(
                        get: { TrackColourOption(track.colour) },
                        set: { shell.setColour($0.colour, on: track.id) },
                    ),
                    label: \.title,
                )
            }
        }

        if track.nodes.count > 1 {
            FieldGroup("Effects") {
                ForEach(track.nodes) { node in
                    Button {
                        shell.selectedNodeID = node.id
                    } label: {
                        HStack {
                            Text(node.name)
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Palette.secondary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Palette.tertiary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // ─── Sections ────────────────────────────────────────────────────────────

    private var header: some View {
        SectionHeader("Script Settings") {
            IconButton(
                systemImage: "ellipsis",
                size: Theme.Size.controlTiny,
                help: "Script actions",
            ) {}
        }
        .padding(.horizontal, Theme.Spacing.compact)
        .padding(.vertical, Theme.Spacing.snug)
    }

    /// What the selected track is, above the parameters that shape it.
    @ViewBuilder
    private var trackSummary: some View {
        if let track = shell.selectedTrack {
            HStack(spacing: Theme.Spacing.snug) {
                Circle()
                    .fill(track.tint)
                    .frame(width: Theme.Spacing.snug, height: Theme.Spacing.snug)

                Text(track.name)
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(Theme.Palette.primary)

                Spacer(minLength: Theme.Spacing.tight)

                Text("\(track.nodes.count)")
                    .font(Theme.Typography.readout)
                    .foregroundStyle(Theme.Palette.tertiary)
                    .help("Effects on this track")
            }
        }
    }

}

// ─── Transform row ───────────────────────────────────────────────────────────

/// One animatable property: its value here and now, and a switch for animating.
///
/// The stopwatch is After Effects' idea and it is the right one — a property is
/// a number until you say otherwise, and saying otherwise is one click. Before
/// that there are no keys to manage and no row to read.
private struct TransformRow: View {
    let property: TransformProperty
    // Qualified: SwiftUI ships a `KeyframeTrack` of its own for view
    // animation, and this target imports both.
    let track: StoryboardCore.KeyframeTrack
    /// What the property is worth right now — its resting value, or its
    /// animation sampled at the playhead.
    let current: Double
    /// Where the playhead is inside the clip.
    let localTime: Double
    let duration: Double
    let setValue: (Double, Double) -> Void
    let beginAnimating: (Double) -> Void
    let setEnabled: (Bool, Double) -> Void
    let clear: (Double) -> Void

    private var hasKeys: Bool { !track.isEmpty }
    private var isAnimating: Bool { track.isActive }

    /// Where a new key would land, clamped into the clip.
    private var keyTime: Double { max(0, min(localTime, duration)) }

    /// Whether there is a key at the playhead right now.
    private var isOnAKey: Bool {
        track.keyframes.contains { abs($0.time - keyTime) < 1 }
    }

    var body: some View {
        PropertyRow(property.title) {
            HStack(spacing: Theme.Spacing.tight) {
                NumberField(
                    value: Binding(
                        get: { current },
                        // Typing while animating sets a key at the playhead —
                        // the same move as dragging a property in any editor
                        // with a timeline. Otherwise it sets the value.
                        set: { setValue($0, keyTime) },
                    ),
                    unit: property.unit,
                    step: property.step,
                    range: property.range,
                    format: property.step < 1 ? "%.2f" : "%.0f",
                )

                // The stopwatch: starts animating, and afterwards switches the
                // animation on and off *without* discarding it. Deleting a
                // stopwatch's worth of work on the same click that started it
                // is a trap, and there is no undo to climb out of it with.
                IconButton(
                    systemImage: isAnimating ? "stopwatch.fill" : "stopwatch",
                    size: Theme.Size.controlTiny,
                    isActive: isAnimating,
                    help: stopwatchHelp,
                ) {
                    if hasKeys {
                        setEnabled(!isAnimating, keyTime)
                    } else {
                        beginAnimating(keyTime)
                    }
                }

                // A key at the playhead, so the timeline is not the only place
                // one can be added or removed.
                if isAnimating {
                    IconButton(
                        systemImage: isOnAKey ? "diamond.fill" : "diamond",
                        size: Theme.Size.controlTiny,
                        isActive: isOnAKey,
                        help: isOnAKey ? "On a keyframe" : "Add a keyframe here",
                    ) {
                        setValue(current, keyTime)
                    }
                }

                keyCount
            }
        }
        .contextMenu {
            if hasKeys {
                Button(isAnimating ? "Disable Animation" : "Enable Animation") {
                    setEnabled(!isAnimating, keyTime)
                }
                Divider()
                // Destructive, so it is a deliberate menu item rather than a
                // side effect of the switch beside the field.
                Button("Delete All Keyframes", systemImage: "trash", role: .destructive) {
                    clear(keyTime)
                }
            }
        }
    }

    /// How many keys the property holds, dimmed when they are switched off.
    @ViewBuilder
    private var keyCount: some View {
        if hasKeys {
            Text("\(track.keyframes.count)")
                .font(Theme.Typography.micro)
                .foregroundStyle(isAnimating ? Theme.Palette.secondary : Theme.Palette.tertiary)
                .frame(width: Theme.Spacing.compact, alignment: .trailing)
                .help(isAnimating
                    ? "\(track.keyframes.count) keyframes"
                    : "\(track.keyframes.count) keyframes, switched off")
        } else {
            Color.clear.frame(width: Theme.Spacing.compact)
        }
    }

    private var stopwatchHelp: String {
        if !hasKeys { return "Animate \(property.title)" }
        return isAnimating
            ? "Switch off \(property.title) animation (keys are kept)"
            : "Switch \(property.title) animation back on"
    }
}

// ─── Filter card ─────────────────────────────────────────────────────────────

/// One filter on a track: its name, a switch, and its parameters.
private struct FilterCard: View {
    let descriptor: FilterDescriptor
    let filter: FilterNode
    let toggle: () -> Void
    let remove: () -> Void
    /// Only a Motion Path has a pen to arm; defaulted so nothing else has to
    /// know about it.
    var isDrawingPath = false
    var onToggleDrawing: () -> Void = {}
    /// Passed down so a filter's sliders coalesce like an effect's.
    var onEditingChanged: (Bool) -> Void = { _ in }
    let onChange: (String, EffectValue) -> Void

    /// Everything the stopwatches need. Defaulted, so a card can still be built
    /// without them — a preview or a test has no playhead to speak of.
    var keyTime: Double = 0
    var animation: (String) -> StoryboardCore.KeyframeTrack? = { _ in nil }
    var animatedValue: (String) -> Double? = { _ in nil }
    var beginAnimating: (String) -> Void = { _ in }
    var setAnimationEnabled: (String, Bool) -> Void = { _, _ in }
    var addKeyframe: (String, Double) -> Void = { _, _ in }
    var clearAnimation: (String) -> Void = { _ in }
    /// Moves the playhead to a clip-local moment, for the keyframe arrows.
    var goToTime: (Double) -> Void = { _ in }

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            HStack(spacing: Theme.Spacing.snug) {
                Image(systemName: "chevron.right")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))

                Image(systemName: descriptor.systemImage)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.secondary)

                Text(descriptor.name)
                    .font(Theme.Typography.label)
                    // Dimmed rather than hidden when off: a filter switched off
                    // is still part of the look someone is building.
                    .foregroundStyle(filter.isEnabled ? Theme.Palette.primary : Theme.Palette.tertiary)

                Spacer(minLength: Theme.Spacing.tight)

                IconButton(
                    systemImage: filter.isEnabled ? "eye" : "eye.slash",
                    size: Theme.Size.controlTiny,
                    help: filter.isEnabled ? "Disable" : "Enable",
                    action: toggle,
                )

                IconButton(
                    systemImage: "trash",
                    size: Theme.Size.controlTiny,
                    help: "Remove \(descriptor.name)",
                    action: remove,
                )
            }
            .contentShape(.rect)
            .onTapGesture { isExpanded.toggle() }

            if isExpanded {
                ForEach(
                    descriptor.parameters.filter { $0.shownWhen?.holds(in: filter.values) ?? true },
                    id: \.id,
                ) { parameter in
                    // The keyframe controls go *under* the field, not beside it.
                    //
                    // A `PropertyRow` is the width of one control, and three
                    // buttons alongside it squeezed a number field down to its
                    // own stepper — no room left to read or type the value.
                    // The same lesson `ColorField` already taught with three
                    // controls in one row, and the alignment buttons after it.
                    VStack(alignment: .leading, spacing: Theme.Spacing.hair) {
                        ParameterControl(
                            parameter: parameter,
                            // While animating, the field shows the value at the
                            // playhead — so scrubbing moves the number, exactly
                            // as a transform's does.
                            value: animatedValue(parameter.id).map { EffectValue.number($0) }
                                ?? filter.values[parameter.id] ?? parameter.defaultValue,
                            onChange: { value in
                                // Typing while animating plants a key here
                                // rather than moving the resting value, which
                                // is what a timeline editor means by editing an
                                // animated property.
                                if case let .number(number) = value,
                                   animation(parameter.id)?.isActive == true
                                {
                                    addKeyframe(parameter.id, number)
                                } else {
                                    onChange(parameter.id, value)
                                }
                            },
                            onEditingChanged: onEditingChanged,
                            isDrawingPath: isDrawingPath,
                            onToggleDrawing: onToggleDrawing,
                        )

                        if parameter.animation.isAnimatable {
                            // Indented to the field it belongs to, so a column
                            // of parameters does not read as a column of
                            // unattached buttons.
                            FilterKeyframeControls(
                                track: animation(parameter.id),
                                keyTime: keyTime,
                                current: animatedValue(parameter.id)
                                    ?? number(of: parameter, in: filter),
                                costWarning: costWarning(for: parameter),
                                beginAnimating: { beginAnimating(parameter.id) },
                                setEnabled: { setAnimationEnabled(parameter.id, $0) },
                                addKey: {
                                    addKeyframe(
                                        parameter.id,
                                        animatedValue(parameter.id)
                                            ?? number(of: parameter, in: filter),
                                    )
                                },
                                clear: { clearAnimation(parameter.id) },
                                goToTime: goToTime,
                            )
                            .padding(.leading, Theme.Spacing.compact)
                        }
                    }
                }
                .disabled(!filter.isEnabled)
                .opacity(filter.isEnabled ? 1 : 0.5)
            }
        }
        .padding(Theme.Spacing.snug)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(Theme.Fill.well)
        }
        .animation(Theme.Motion.quick, value: isExpanded)
    }

    /// A parameter's resting number, for the key a first click plants.
    private func number(of parameter: EffectParameter, in filter: FilterNode) -> Double {
        switch filter.values[parameter.id] ?? parameter.defaultValue {
        case let .number(value): value
        case let .integer(value): Double(value)
        default: 0
        }
    }

    /// What animating a parameter will cost, when it is not free.
    ///
    /// Only `.textures` has anything to say: it mints an image per level the
    /// value passes through, so the count is knowable in advance and has to be
    /// said before somebody writes a file osu! will not open. A parameter that
    /// lands in a command costs nothing and stays quiet.
    private func costWarning(for parameter: EffectParameter) -> String? {
        guard case let .textures(step) = parameter.animation, step > 0 else { return nil }
        guard let range = parameter.range else { return "Animate this — one sprite per level" }

        let levels = Int(((range.upperBound - range.lowerBound) / step).rounded()) + 1
        return "Animate this — one sprite per level, up to \(levels) across the full range"
    }
}

// ─── Parameter control ───────────────────────────────────────────────────────

/// Renders one declared parameter using whichever control its kind calls for.
///
/// The mapping lives here and only here: an effect declares what a parameter
/// is, and this is the single place that decides what that looks like. An
/// effect that adds a parameter needs no view work at all.
private struct ParameterControl: View {
    let parameter: EffectParameter
    let value: EffectValue
    let onChange: (EffectValue) -> Void
    /// Told when a continuous gesture starts and ends, so the edits it makes
    /// fold into one undo step instead of one per pixel travelled.
    var onEditingChanged: (Bool) -> Void = { _ in }
    /// Only a `.path` row uses these, so they are defaulted rather than
    /// threaded through every other call site.
    var isDrawingPath = false
    var onToggleDrawing: () -> Void = {}

    var body: some View {
        PropertyRow(parameter.name) {
            control
        }
    }

    @ViewBuilder
    private var control: some View {
        switch value {
        // Drawn on the canvas, not here.
        //
        // A path written as numbers is a table, so the inspector reports what
        // is there and leaves the shaping to the stage. Saying how many points
        // it has rather than nothing at all: an empty row reads as a control
        // that failed to load.
        case let .path(path):
            PathControl(
                path: path,
                isDrawing: isDrawingPath,
                onToggleDrawing: onToggleDrawing,
                onChange: { onChange(.path($0)) },
            )

        case let .number(number):
            if parameter.presentation == .slider, let range = parameter.range {
                SliderField(
                    value: Binding(get: { number }, set: { onChange(.number($0)) }),
                    range: range,
                    onEditingChanged: onEditingChanged,
                )
            } else {
                NumberField(
                    value: Binding(get: { number }, set: { onChange(.number($0)) }),
                    unit: parameter.unit,
                    step: parameter.step ?? 1,
                    range: parameter.range ?? -1_000_000...1_000_000,
                    format: (parameter.step ?? 1) < 1 ? "%.2f" : "%.0f",
                )
            }

        case let .integer(number):
            NumberField(
                value: Binding(
                    get: { Double(number) },
                    set: { onChange(.integer(Int($0.rounded()))) },
                ),
                unit: parameter.unit,
                step: parameter.step ?? 1,
                range: parameter.range ?? 0...1_000_000,
                format: "%.0f",
            )

        case let .toggle(isOn):
            Toggle("", isOn: Binding(get: { isOn }, set: { onChange(.toggle($0)) }))
                .labelsHidden()
                .controlSize(.mini)
                .frame(maxWidth: .infinity, alignment: .leading)

        case let .choice(selected):
            MenuField(
                items: parameter.options.map(ChoiceOption.init),
                selection: Binding(
                    get: { ChoiceOption(selected) },
                    set: { onChange(.choice($0.id)) },
                ),
                label: \.id,
            )

        case let .color(colour):
            ColorField(
                color: Binding(
                    get: { colour.swiftUIColor },
                    set: { onChange(.color(EffectColor($0))) },
                ),
                hex: colour.hex,
            )

        case let .text(string):
            // A menu of the built-in shapes above the field, not instead of it:
            // the shapes cover most cases, and a beatmap's own image has to
            // stay typeable.
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                if parameter.id == EmitterEffect.Param.sprite {
                    let choice = SpriteChoice(path: string)
                    MenuField(
                        items: SpriteChoice.all,
                        selection: Binding(
                            get: { choice },
                            // "Custom" has no path of its own — it means "let
                            // me type one". Picking it used to `return` and do
                            // nothing at all, so the entry looked broken.
                            // Seeding a placeholder puts a path in the field to
                            // edit, which is the whole point of choosing it.
                            set: { onChange(.text($0.path ?? customPlaceholder)) },
                        ),
                        label: \.title,
                    )

                    // The field only where there is a path to edit.
                    //
                    // The built particle stores an empty path by design — its
                    // shape comes from three numbers — so an empty box beneath
                    // it invites typing into something that is deliberately
                    // blank, and anything typed silently turns the shape
                    // parameters off.
                    if !string.isEmpty {
                        TextInputField(
                            text: Binding(get: { string }, set: { onChange(.text($0)) }),
                        )
                    }
                } else {
                    TextInputField(
                        text: Binding(get: { string }, set: { onChange(.text($0)) }),
                    )
                }
            }
        }
    }
}

/// What picking "Custom" puts in the field.
///
/// A path rather than an empty string: empty *is* the built particle, so
/// clearing the field would silently bounce the menu back to it. A visible
/// stand-in says "replace this" and keeps the choice where it was put.
///
/// Named after the folder a beatmap's own images live in, so it reads as an
/// example of the shape a path takes rather than as a file anyone expects to
/// find. A path that resolves to nothing draws a plain quad, which is the same
/// thing any mistyped path already does.
private let customPlaceholder = "sb/your-image.png"

/// The built-in shapes, plus an entry standing in for a path typed by hand.
private struct SpriteChoice: Hashable, Identifiable {
    let id: String
    let title: String
    /// `nil` for the custom entry, which is a label rather than a choice.
    let path: String?

    init(id: String, title: String, path: String?) {
        self.id = id
        self.title = title
        self.path = path
    }

    /// What the menu shows for a stored path.
    ///
    /// A path the shapes do not cover displays as "Custom" rather than falling
    /// back to a shape, which would silently claim the sprite is something it
    /// is not.
    init(path: String) {
        if path.isEmpty {
            self = Self.built
        } else if let known = Self.known.first(where: { $0.path == path }) {
            self = known
        } else {
            self = SpriteChoice(id: "custom", title: "Custom", path: nil)
        }
    }

    /// The particle built from the three shape numbers.
    ///
    /// An entry of its own rather than the *absence* of a sprite: it is the
    /// first thing in the list, it says what the group below is for, and it is
    /// the only way back once a file has been picked. Stored as an empty path,
    /// which is what "nothing overrides the numbers" means.
    ///
    /// Named for what it *is* and what sets it apart, not for the machinery
    /// behind it. "Built from Shape" promised any shape while it only ever
    /// draws a radial gradient — and "Circle" would sit directly above Soft
    /// Dot, Glow and Ring, which are circles too, saying nothing about the
    /// difference. The difference is that this one is yours to dial.
    static let built = SpriteChoice(id: "built", title: "Adjustable Dot", path: "")

    /// Drawn in code: soft, generic, tinted by the effect.
    private static let shapes: [SpriteChoice] = [
        SpriteChoice(id: "soft", title: "Soft Dot", path: BuiltInSprite.soft),
        SpriteChoice(id: "glow", title: "Glow", path: BuiltInSprite.glow),
        SpriteChoice(id: "smoke", title: "Smoke Puff", path: BuiltInSprite.smoke),
        SpriteChoice(id: "star", title: "Star", path: BuiltInSprite.star),
        SpriteChoice(id: "square", title: "Square", path: BuiltInSprite.square),
        SpriteChoice(id: "streak", title: "Streak", path: BuiltInSprite.streak),
        SpriteChoice(id: "ring", title: "Ring", path: BuiltInSprite.ring),
    ]

    /// Shipped as files: the shapes code cannot draw.
    ///
    /// Ordered by what they are for rather than alphabetically — someone
    /// reaching for lightning is not looking under "s" for "spark".
    private static let textures: [SpriteChoice] = [
        SpriteChoice(id: "lightning", title: "Lightning", path: BuiltInSprite.lightning),
        SpriteChoice(id: "lightningWide", title: "Lightning Wide", path: BuiltInSprite.lightningWide),
        SpriteChoice(id: "bolt", title: "Bolt", path: BuiltInSprite.bolt),
        SpriteChoice(id: "boltThin", title: "Bolt Thin", path: BuiltInSprite.boltThin),
        SpriteChoice(id: "flame", title: "Flame", path: BuiltInSprite.flame),
        SpriteChoice(id: "flameTall", title: "Flame Tall", path: BuiltInSprite.flameTall),
        SpriteChoice(id: "flameWisp", title: "Flame Wisp", path: BuiltInSprite.flameWisp),
        SpriteChoice(id: "ember", title: "Embers", path: BuiltInSprite.ember),
        SpriteChoice(id: "muzzle", title: "Muzzle Flash", path: BuiltInSprite.muzzle),
        SpriteChoice(id: "muzzleWide", title: "Muzzle Wide", path: BuiltInSprite.muzzleWide),
        SpriteChoice(id: "arc", title: "Arc", path: BuiltInSprite.arc),
        SpriteChoice(id: "crescent", title: "Crescent", path: BuiltInSprite.crescent),
        SpriteChoice(id: "scratch", title: "Scratch", path: BuiltInSprite.scratch),
        SpriteChoice(id: "slash", title: "Slash", path: BuiltInSprite.slash),
        SpriteChoice(id: "flare", title: "Flare", path: BuiltInSprite.flare),
        SpriteChoice(id: "flareSoft", title: "Flare Soft", path: BuiltInSprite.flareSoft),
        SpriteChoice(id: "runeRing", title: "Rune Ring", path: BuiltInSprite.runeRing),
        SpriteChoice(id: "cloud", title: "Cloud", path: BuiltInSprite.cloud),
        SpriteChoice(id: "cloudWisp", title: "Cloud Wisp", path: BuiltInSprite.cloudWisp),
        SpriteChoice(id: "sparkle", title: "Sparkle", path: BuiltInSprite.sparkle),
        SpriteChoice(id: "debris", title: "Debris", path: BuiltInSprite.debris),
        SpriteChoice(id: "pane", title: "Pane", path: BuiltInSprite.pane),
    ]

    private static let known = shapes + textures

    /// The parametric particle first, then the drawn shapes and the files.
    ///
    /// "Custom" stays last and keeps its `nil` path — it is a *label* for a
    /// path typed into the field below, not something to choose. Every other
    /// entry sets a path, including the built one, so the menu can always be
    /// used to get back.
    static let all = [built] + known + [SpriteChoice(id: "custom", title: "Custom", path: nil)]
}

// ─── Colour bridging ─────────────────────────────────────────────────────────

/// `StoryboardCore` cannot import SwiftUI, and the value ends up in a `_C`
/// command where the channel range is 0–255. The conversion belongs at the
/// edge, which is here.
private extension EffectColor {
    var swiftUIColor: Color {
        Color(red: r / 255, green: g / 255, blue: b / 255)
    }

    var hex: String {
        String(format: "%02X%02X%02X", Int(r.rounded()), Int(g.rounded()), Int(b.rounded()))
    }

    init(_ color: Color) {
        let components = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(
            r: Double(components.redComponent) * 255,
            g: Double(components.greenComponent) * 255,
            b: Double(components.blueComponent) * 255,
        )
    }
}

/// Wraps a curve so it can drive an identifiable menu.
private struct EasingOption: Hashable, Identifiable {
    let curve: KeyframeEasing

    init(_ curve: KeyframeEasing) {
        self.curve = curve
    }

    var id: String { curve.rawValue }
    var title: String { curve.title }
}

/// Wraps a layer so it can drive an identifiable menu.
private struct LayerOption: Hashable, Identifiable {
    let layer: Layer

    init(_ layer: Layer) {
        self.layer = layer
    }

    var id: String { layer.rawValue }
    var title: String { layer.rawValue }
}

/// Wraps a plain string so it can drive an identifiable menu.
private struct ChoiceOption: Hashable, Identifiable {
    let id: String

    init(_ id: String) {
        self.id = id
    }
}


/// A colour choice for a track, with an entry for following the layer.
///
/// `nil` is one of the options rather than a separate control: "match the
/// layer" is a choice among the colours, not a switch beside them.
private struct TrackColourOption: Hashable, Identifiable {
    let colour: TrackColour?

    init(_ colour: TrackColour?) { self.colour = colour }

    var id: String { colour?.rawValue ?? "layer" }
    var title: String { colour?.title ?? "Match Layer" }

    static let all: [TrackColourOption] =
        [TrackColourOption(nil)] + TrackColour.allCases.map(TrackColourOption.init)
}


/// One layer of a compound effect, with its parameters laid out below it.
///
/// Its groups are flattened into one block: a layer already sits inside the
/// parent's list, and nesting a second level of headed groups under it makes
/// three levels of indentation for a handful of fields.
private struct LayerSection: View {
    let layer: EffectNode
    let descriptor: EffectDescriptor
    let toggle: () -> Void
    let onChange: (String, EffectValue) -> Void

    /// Collapsed by default.
    ///
    /// Every layer open at once is thirty rows before the first one anybody
    /// wants — the parent's own parameters are already above. Open is one
    /// click, and which layer is open is the question being asked.
    @State private var isExpanded = false

    var body: some View {
        FieldGroup {
            VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
                header

                if isExpanded {
                    ForEach(
                        descriptor.parameters.filter { $0.shownWhen?.holds(in: layer.values) ?? true },
                        id: \.id,
                    ) { parameter in
                        ParameterControl(
                            parameter: parameter,
                            value: layer.values[parameter.id] ?? parameter.defaultValue,
                            onChange: { onChange(parameter.id, $0) },
                        )
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.snug) {
            Button(action: { isExpanded.toggle() }) {
                HStack(spacing: Theme.Spacing.snug) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.tertiary)
                    Text(layer.name)
                        .font(Theme.Typography.label)
                        .foregroundStyle(
                            layer.isVisible ? Theme.Palette.primary : Theme.Palette.tertiary,
                        )
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            // Switching one layer off is the fastest way to learn what it
            // contributes, which is most of what tuning a compound is.
            Button(action: toggle) {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.tertiary)
            }
            .buttonStyle(.plain)
            .help(layer.isVisible ? "Hide layer" : "Show layer")
        }
    }
}

/// The row a motion path gets in the inspector.
///
/// The path itself is drawn on the canvas — written as numbers it would be a
/// table, not a path. What belongs here is the switch that arms the pen and a
/// count, so the row says what is there rather than sitting empty, which reads
/// as a control that failed to load.
private struct PathControl: View {
    let path: MotionPath
    let isDrawing: Bool
    let onToggleDrawing: () -> Void
    let onChange: (MotionPath) -> Void

    var body: some View {
        // One button and a count, not three controls fighting for a row's
        // width: a property row is sized for a single control, and three of
        // them came out as "Do ne" and "Cl e…" — labels broken across lines,
        // which is a row saying it has more in it than it can hold.
        //
        // Clearing moves to the pen itself: it belongs to editing the path, and
        // it is the rarer action of the two.
        HStack(spacing: Theme.Spacing.snug) {
            Button(isDrawing ? "Done" : "Draw", action: onToggleDrawing)
                .buttonStyle(.themed(isDrawing ? .primary : .secondary, size: .small))
                .contextMenu {
                    Button("Clear Path") { onChange(MotionPath()) }
                }

            Text(path.isEmpty ? "empty" : "\(path.points.count) pts")
                .font(Theme.Typography.micro)
                .foregroundStyle(path.isEmpty ? Theme.Palette.tertiary : Theme.Palette.secondary)
                .fixedSize()

            Spacer(minLength: 0)
        }
    }
}


