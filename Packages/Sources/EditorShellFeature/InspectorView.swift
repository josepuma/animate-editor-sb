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
    ///
    /// 300 rather than the 264 it was. Groups became surfaces with their own
    /// padding, and a transform row still needs its stopwatch and diamond
    /// columns: at 264 that left a number field about 70 points — "3654 ms"
    /// cut off behind its stepper. The window's minimum is derived from this,
    /// so it follows.
    static let width: CGFloat = 300

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


    /// The clip the tabs are for, when the panel is showing one.
    ///
    /// Not in camera mode — the timeline is showing the camera then, and the
    /// panel describes that instead.
    private var clip: (node: EffectNode, descriptor: EffectDescriptor)? {
        guard !shell.isEditingCamera,
              let node = shell.selectedEffect,
              let descriptor = shell.selectedDescriptor
        else { return nil }
        return (node, descriptor)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            // Outside the scroll view, so the tabs stay put while their
            // content scrolls under them — a tab row that scrolls away is a
            // tab row that has to be scrolled back to.
            if let clip {
                let isScript = clip.node.type == ScriptEffect.descriptor.type
                let draws = clip.descriptor.drawsSprites
                ToolTabs(
                    items: InspectorTab.tabs(isScript: isScript, drawsSprites: draws),
                    selection: Binding(
                        get: { shell.inspectorTab.shown(isScript: isScript, drawsSprites: draws) },
                        set: { shell.inspectorTab = $0 },
                    ),
                    icon: \.systemImage,
                    label: \.title,
                )
                .padding(.horizontal, Theme.Spacing.snug)
                .padding(.bottom, Theme.Spacing.tight)
            }

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
                // `loose` between groups, matching the lyrics panel: `compact`
                // is the spacing *within* a group, so using it between them
                // gave the panel no hierarchy — every heading read as one more
                // field label in a single long list.
                // `FieldGroups` puts the rule between its children, so a
                // group generated in a `ForEach` gets one without anybody
                // remembering to add it.
                //
                // Not lazy any more, and that is a real trade: `LazyVStack`
                // was here because an emitter has thirty parameters, several
                // of them AppKit menus and colour wells, and building them all
                // at once measured 83 to 207ms. A variadic container has to
                // see its children to separate them, so they are all built.
                // Watch this if a thirty-parameter effect feels slow to
                // select — the fix would be grouping lazily *inside* each
                // group rather than going back to no separators.
                FieldGroups {
                    trackSummary

                    if shell.isEditingCamera {
                        // The timeline is showing the camera, so that is what
                        // this panel describes — two halves of the window
                        // disagreeing about the selection is the bug this
                        // panel already had once, with keyframe mode.
                        cameraSections
                            .propertyGrid(
                                leading: Theme.Size.keyframeGutter,
                                trailing: CameraProperty.allCases.contains { shell.effects.camera[$0].isActive }
                                    ? Theme.Size.keyframeSlot : nil,
                            )
                    } else if let clip {
                        clipTabs(descriptor: clip.descriptor, node: clip.node)
                    } else if let track = shell.selectedTrack {
                        trackParameters(track)
                    } else {
                        ComingSoon(
                            title: "Nothing selected",
                            detail: "Pick a clip on the timeline to edit what it does.",
                            systemImage: "sparkles",
                        )
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
        // Not surfaced: each filter is a card of its own, and a card on a
        // surface of the same tone is a box in a box.
        FieldGroup("Filters", surfaced: false) {
            ForEach(node.filters) { filter in
                if let descriptor = shell.filters.descriptor(for: filter.type) {
                    FilterNodeCard(
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

    /// A selected clip, split into the tab the panel is on.
    @ViewBuilder
    private func clipTabs(descriptor: EffectDescriptor, node: EffectNode) -> some View {
        // Above whichever tab is open, not inside one: a selected key is what
        // someone is working on right now, and picking a diamond on the
        // timeline must not leave them hunting for its fields behind a tab.
        selectedKeyframeSection(node)
        selectedFilterKeyframeSection(node)

        switch shell.inspectorTab.shown(
            isScript: node.type == ScriptEffect.descriptor.type,
            drawsSprites: descriptor.drawsSprites,
        ) {
        case .effect:
            // Said where the file is chosen: the preview stays silent for a
            // sound this machine cannot decode, and the author should know
            // before they wonder whether the clip is misplaced. The export
            // still ships the file.
            if shell.cannotPreview(node) {
                Label("Can't preview this file here. It is still exported.", systemImage: "speaker.slash")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.warning)
            }
            effectParameters(descriptor: descriptor, node: node)
        case .clip:
            // The keyframe grid on Transform only, whose rows carry a stopwatch
            // and a diamond. Not on Timing, nor on the Effect tab: nothing there
            // animates, and reserving the two columns cost every row 44 points
            // and pushed its label a column inward. Lining Timing up with
            // Transform was the reason it once shared the grid — but each group
            // is its own surface now, and alignment is owed within a group, not
            // across two.
            timingRow(node: node)
            // Nothing to move or animate for a clip that draws nothing.
            if descriptor.drawsSprites {
                transformSection(node)
                    .propertyGrid(
                        leading: Theme.Size.keyframeGutter,
                        trailing: TransformProperty.allCases.contains { node.transform[$0].isActive }
                            ? Theme.Size.keyframeSlot : nil,
                    )
            }
        case .filters:
            if node.filters.isEmpty {
                // Said rather than left blank: an empty tab reads as broken,
                // and this one has an obvious next step.
                ComingSoon(
                    title: "No filters",
                    detail: "Drag a filter from the library onto this clip.",
                    systemImage: InspectorTab.filters.systemImage,
                )
            } else {
                filterSection(node)
            }
        case .output:
            // Reading `evaluatingNodes` is also what redraws this when a run
            // lands: the report itself comes through a closure SwiftUI cannot
            // observe, so a saved script's new output would otherwise wait for
            // some unrelated change to show.
            ScriptOutputView(
                report: shell.scriptReport?(node.id),
                isRunning: shell.evaluatingNodes.contains(node.id),
            )
        }
    }

    /// The selected effect's declared parameters, grouped as it declared them,
    /// and a compound's layers.
    @ViewBuilder
    private func effectParameters(descriptor: EffectDescriptor, node: EffectNode) -> some View {
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
                        thumbnails: shell.spriteThumbnailSource,
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
            // A layer is an `EffectNode`, so its descriptor resolves per node
            // for the same reason the parent's does.
            if let descriptor = shell.library.descriptor(for: layer) {
                LayerSection(
                    layer: layer,
                    descriptor: descriptor,
                    toggle: { shell.toggleLayerVisibility(layer.id, in: node.id) },
                    onChange: { parameter, value in
                        shell.setLayerValue(
                            value, for: parameter, onLayer: layer.id, in: node.id,
                        )
                    },
                    thumbnails: shell.spriteThumbnailSource,
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
                    .overlay(alignment: .topLeading) {
                        if property == .scaleY { scaleLink }
                    }
                }
            }
        }
    }

    /// Ties the two scale axes together.
    ///
    /// Sits at the end of the label column and spans upward into the gap
    /// between the rows — the shape a chain link has in every editor that
    /// pairs two fields.
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
        // At the trailing edge of the label column, centred on the gap between
        // the two rows — between the names and the values, where After Effects
        // puts its constrain-proportions link.
        //
        // It used to sit out past the panel's columns, which meant padding the
        // two scale rows to make room: their fields came out 22 points
        // narrower than every other field, a ragged edge in the one place the
        // grid exists to keep straight. The label column has room to spare —
        // "Scale X" fills about half of it — so the link costs no field any
        // width.
        .offset(
            x: Theme.Size.keyframeGutter + Theme.Spacing.snug
                + Theme.Size.propertyLabel - Theme.Size.controlTiny,
            // Half the gap between the rows plus half the link: centred on the
            // gap. The gap is `FieldGroup`'s row spacing — change one, change
            // both.
            y: -(Theme.Spacing.tight + Theme.Size.controlTiny) / 2,
        )
    }

    @ViewBuilder
    private func transformRow(_ property: TransformProperty, node: EffectNode) -> some View {
        TransformRow(
                    title: property.title,
                    unit: property.unit,
                    step: property.step,
                    range: property.range,
                    keyTimes: node.transform[property].keyframes.map(\.time),
                    isAnimating: node.transform[property].isActive,
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
            // The seek takes song time; a key's is the clip's own.
            goToTime: { shell.seekHandler?(node.startTime + $0) },
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
        // A `PropertyRow`, so it takes the group's columns: as a hand-built
        // row it had the label width but not the stopwatch gutter, and its
        // label started a column left of every label under it.
        PropertyRow("Align") {
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
            // The name comes first, because it is what the block on the
            // timeline says.
            //
            // `EffectNode.name` was written once, at placement, and never
            // again — so several scripts were "Script 3" through "Script 6",
            // named by the order they were dropped in. That is the one thing a
            // name must not be: it carries no information about which clip
            // draws what.
            PropertyRow("Name") {
                TextInputField(
                    text: Binding(
                        get: { node.name },
                        set: { shell.renameEffect(node.id, to: $0) },
                    ),
                )
            }
            // Swapping the movement without rebuilding the clip.
            //
            // It sits with the name rather than in the library panel because
            // this acts on the clip already selected — the library places new
            // things, and reaching there to change this one would read as
            // placing another.
            //
            // Hidden when the effect ships none, rather than shown empty.
            if !shell.presets(forEffectType: node.type).isEmpty {
                PropertyRow("Preset") {
                    // A `Menu` of actions rather than `MenuField`, which needs
                    // a selection to bind to.
                    //
                    // Nothing records which preset a clip came from, and once
                    // one parameter is tuned the answer would be wrong anyway
                    // — a field naming a preset the clip no longer matches is
                    // worse than one naming none. So this is a verb, not a
                    // value.
                    Menu {
                        ForEach(shell.presets(forEffectType: node.type)) { preset in
                            Button(preset.name) { shell.applyPreset(preset, to: node.id) }
                        }
                    } label: {
                        HStack(spacing: Theme.Spacing.tight) {
                            Text("Change\u{2026}")
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Palette.secondary)
                            Spacer(minLength: Theme.Spacing.tight)
                            Image(systemName: "chevron.down")
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Palette.tertiary)
                        }
                        // Widening the label is what makes the menu grow: a
                        // `Menu` keeps its intrinsic width otherwise, so the
                        // `Spacer` would have nothing to push against.
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(maxWidth: .infinity)
                }
            }
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

            // Where the lane is in the scene the storyboard camera looks at.
            // Beside the layer because it is the same kind of statement —
            // where this row sits — and the switch is the one to reach for on
            // lyrics or a HUD, which must stay on screen whatever the camera
            // does.
            PropertyRow("Follows Camera") {
                SwitchControl(isOn: Binding(
                    get: { track.followsCamera },
                    set: { shell.setFollowsCamera($0, on: track.id) },
                ))
            }

            if track.followsCamera {
                PropertyRow("Depth (Z)") {
                    NumberField(
                        value: Binding(
                            get: { track.z },
                            set: { shell.setDepth($0, on: track.id) },
                        ),
                        unit: "px",
                        step: CameraProperty.z.step,
                        range: CameraProperty.z.range,
                        format: "%.0f",
                    )
                    .help("0 is drawn as it is; 1000 back is half size and pans half as far; negative is closer")
                }
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

    // ─── Camera ──────────────────────────────────────────────────────────────

    /// The storyboard camera: where it looks and how close, and the key being
    /// edited if one is selected.
    @ViewBuilder
    private var cameraSections: some View {
        let camera = shell.camera

        FieldGroup("Camera") {
            ForEach(CameraProperty.allCases, id: \.self) { property in
                TransformRow(
                    title: property.title,
                    unit: property.unit,
                    step: property.step,
                    range: property.range,
                    keyTimes: camera[property].keyframes.map(\.time),
                    isAnimating: camera[property].isActive,
                    current: camera.value(property, at: playheadTime),
                    // Song time: the camera belongs to no clip.
                    localTime: playheadTime,
                    duration: .greatestFiniteMagnitude,
                    setValue: { value, time in
                        if camera[property].isEmpty {
                            shell.setCameraValue(value, for: property)
                        } else {
                            shell.setCameraKeyframe(value, for: property, at: time)
                        }
                    },
                    beginAnimating: { shell.beginAnimatingCamera(property, at: $0) },
                    setEnabled: { shell.setCameraAnimationEnabled($0, for: property, keeping: $1) },
                    clear: { shell.clearCameraKeyframes(for: property, keeping: $0) },
                    // Already song time, like the camera's keys.
                    goToTime: { shell.seekHandler?($0) },
                )
            }

            Text("Each track sits at its own Depth (Z): farther tracks draw smaller and move less.")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        if let selection = shell.selectedCameraKeyframe, let key = shell.selectedCameraKeyframeValue {
            FieldGroup("Keyframe · \(selection.property.title)") {
                PropertyRow("Time") {
                    NumberField(
                        value: Binding(
                            get: { key.time },
                            set: { shell.moveCameraKeyframe(key.id, in: selection.property, to: $0) },
                        ),
                        unit: "ms",
                        step: 10,
                        range: 0...(.greatestFiniteMagnitude),
                        format: "%.0f",
                    )
                }

                PropertyRow("Value") {
                    NumberField(
                        value: Binding(
                            get: { key.value },
                            set: { shell.setCameraKeyframeValue($0, for: key.id, in: selection.property) },
                        ),
                        unit: selection.property.unit,
                        step: selection.property.step,
                        range: selection.property.range,
                        format: selection.property.step < 1 ? "%.2f" : "%.0f",
                    )
                }

                PropertyRow("Easing") {
                    MenuField(
                        items: KeyframeEasing.allCases.map(EasingOption.init),
                        selection: Binding(
                            get: { EasingOption(KeyframeEasing.matching(key.easing)) },
                            set: { shell.setCameraKeyframeEasing($0.curve.easing, for: key.id, in: selection.property) },
                        ),
                        label: \.title,
                    )
                }

                Button("Delete Keyframe", systemImage: "trash", role: .destructive) {
                    shell.removeCameraKeyframe(key.id, from: selection.property)
                }
                .font(Theme.Typography.micro)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // ─── Sections ────────────────────────────────────────────────────────────


    /// What the panel is about: the clip, when there is one.
    ///
    /// It used to read "Script Settings" over every effect — an emitter, a
    /// line of text, a shape — which named a feature rather than the thing
    /// selected. With tabs below, the heading is what tells you which clip the
    /// tabs belong to.
    @ViewBuilder
    private var header: some View {
        if let clip {
            HStack(spacing: Theme.Spacing.snug) {
                GlyphTile(
                    systemImage: clip.descriptor.systemImage,
                    tint: shell.selectedTrack?.tint,
                    size: Theme.Size.controlSmall,
                )

                VStack(alignment: .leading, spacing: 0) {
                    Text(clip.node.name)
                        .font(Theme.Typography.cardTitle)
                        .foregroundStyle(Theme.Palette.primary)
                        .lineLimit(1)

                    Text(clip.descriptor.name)
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.compact)
            .padding(.top, Theme.Spacing.compact)
            .padding(.bottom, Theme.Spacing.snug)
        } else {
            SectionHeader(shell.isEditingCamera ? "Camera" : "Inspector")
                .padding(.horizontal, Theme.Spacing.compact)
                .padding(.vertical, Theme.Spacing.snug)
        }
    }

    /// What the selected track is, above the parameters that shape it.
    @ViewBuilder
    private var trackSummary: some View {
        // Only for a lane on its own: with a clip selected the header already
        // names it, and a second title above the tabs says it twice.
        if !shell.isEditingCamera, clip == nil, let track = shell.selectedTrack {
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

// ─── Filter card ─────────────────────────────────────────────────────────────

/// One filter on a track, with its parameters generated from its descriptor.
///
/// The chrome — the name, the switch, the fold — is `FilterCard`; this owns
/// what goes inside it, which needs the descriptor and the model's callbacks.
private struct FilterNodeCard: View {
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

    var body: some View {
        FilterCard(
            name: descriptor.name,
            systemImage: descriptor.systemImage,
            isEnabled: filter.isEnabled,
            toggle: toggle,
            remove: remove,
        ) {
            ForEach(
                descriptor.parameters.filter { $0.shownWhen?.holds(in: filter.values) ?? true },
                id: \.id,
            ) { parameter in
                // An animatable parameter's stopwatch sits before its label and
                // its diamond after its field — the same columns a transform
                // row uses — so the field keeps its width.
                ParameterControl(
                    parameter: parameter,
                    // While animating, the field shows the value at the
                    // playhead — so scrubbing moves the number, exactly
                    // as a transform's does.
                    value: animatedValue(parameter.id).map { EffectValue.number($0) }
                        ?? filter.values[parameter.id] ?? parameter.defaultValue,
                    onChange: { value in
                        // Typing while animating plants a key here rather
                        // than moving the resting value, which is what a
                        // timeline editor means by editing an animated
                        // property.
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
                    // In the row's own columns, as in a transform row: the
                    // stopwatch before the label, navigation after the field.
                    //
                    // It used to sit on a line of its own, and five parameters
                    // read as ten rows of alternating field and orphaned
                    // button; then all of it after the field, where its width
                    // came and went with the animation and shrank the field.
                    trailing: keyframeControls(for: parameter, in: filter).map { AnyView($0.navigator) },
                    leading: keyframeControls(for: parameter, in: filter).map { AnyView($0.stopwatch) },
                )
            }
            .disabled(!filter.isEnabled)
            .opacity(filter.isEnabled ? 1 : 0.5)
        }
        // The keyframe columns only on a filter that has something to animate.
        // Decided per card, not for the whole Filters tab: Echo animates
        // nothing, and the two empty columns it was given pushed its labels
        // inward and narrowed every field — the same cost the Effect tab and
        // Timing were already spared. `nil` reserves nothing.
        .propertyGrid(
            leading: hasAnimatableParameters ? Theme.Size.keyframeGutter : nil,
            trailing: isAnimating ? Theme.Size.keyframeSlot : nil,
        )
    }

    /// Whether any of this filter's parameters animates now — the diamond's
    /// column is only worth its width while there is a diamond in it.
    private var isAnimating: Bool {
        descriptor.parameters.contains { animation($0.id)?.isActive == true }
    }

    private var hasAnimatableParameters: Bool {
        descriptor.parameters.contains { $0.animation.isAnimatable }
    }

    /// The stopwatch and navigation for a parameter, or `nil` when its
    /// descriptor says it cannot animate.
    private func keyframeControls(
        for parameter: EffectParameter,
        in filter: FilterNode,
    ) -> FilterKeyframeControls? {
        guard parameter.animation.isAnimatable else { return nil }
        return FilterKeyframeControls(
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
    /// Drawn after the control, in the same row.
    ///
    /// For a stopwatch, which belongs to the field rather than beside it: on a
    /// line of its own it aligned with nothing, and five parameters became ten
    /// rows of alternating field and orphaned button.
    var trailing: AnyView?
    /// Drawn before the label — the stopwatch's column, as in a transform row.
    var leading: AnyView?
    /// Pictures for the sprite picker. Only an emitter's sprite row uses it,
    /// so it is defaulted rather than threaded through every call site.
    var thumbnails: SpriteThumbnails = .none

    var body: some View {
        PropertyRow(parameter.name, leading: {
            leading
        }, control: {
            control
        }, trailing: {
            trailing
        })
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
            SwitchControl(isOn: Binding(get: { isOn }, set: { onChange(.toggle($0)) }))

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
                    SpritePicker(path: string, thumbnails: thumbnails) { onChange(.text($0)) }

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
/// A plain string, made pickable.
///
/// `MenuField` wants an `Identifiable` item and a `String` is not one. Shared
/// rather than private now that two panels need it.
struct ChoiceOption: Hashable, Identifiable {
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
    var thumbnails: SpriteThumbnails = .none

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
                            thumbnails: thumbnails,
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


