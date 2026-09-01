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
                        onChange: { parameter, value in
                            shell.setFilterValue(
                                value, for: parameter, on: filter.id, in: node.id,
                            )
                        },
                    )
                }
            }

            // A loop's pass starts from an empty screen, so a continuous
            // emitter visibly thins at every seam. Said here rather than left
            // for someone to wonder why their fire flickers.
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

    /// The selected effect's declared parameters, grouped as it declared them.
    @ViewBuilder
    private func effectParameters(descriptor: EffectDescriptor, node: EffectNode) -> some View {
        timingRow(node: node)
        selectedKeyframeSection(node)
        transformSection(node)

        ForEach(descriptor.groups, id: \.self) { group in
            FieldGroup(group) {
                ForEach(descriptor.parameters.filter { $0.group == group }, id: \.id) { parameter in
                    ParameterControl(
                        parameter: parameter,
                        value: node.values[parameter.id] ?? parameter.defaultValue,
                        onChange: { shell.setValue($0, for: parameter.id, on: node.id) },
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
    let onChange: (String, EffectValue) -> Void

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
                ForEach(descriptor.parameters, id: \.id) { parameter in
                    ParameterControl(
                        parameter: parameter,
                        value: filter.values[parameter.id] ?? parameter.defaultValue,
                        onChange: { onChange(parameter.id, $0) },
                    )
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

    var body: some View {
        PropertyRow(parameter.name) {
            control
        }
    }

    @ViewBuilder
    private var control: some View {
        switch value {
        case let .number(number):
            if parameter.presentation == .slider, let range = parameter.range {
                SliderField(
                    value: Binding(get: { number }, set: { onChange(.number($0)) }),
                    range: range,
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
                    MenuField(
                        items: SpriteChoice.all,
                        selection: Binding(
                            get: { SpriteChoice(path: string) },
                            set: { choice in
                                guard let path = choice.path else { return }
                                onChange(.text(path))
                            },
                        ),
                        label: \.title,
                    )
                }

                TextInputField(
                    text: Binding(get: { string }, set: { onChange(.text($0)) }),
                )
            }
        }
    }
}

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
        if let known = Self.known.first(where: { $0.path == path }) {
            self = known
        } else {
            self = SpriteChoice(id: "custom", title: "Custom", path: nil)
        }
    }

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

    static let all = known + [SpriteChoice(id: "custom", title: "Custom", path: nil)]
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
                    ForEach(descriptor.parameters, id: \.id) { parameter in
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
