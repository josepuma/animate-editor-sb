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
    let playback: PlaybackSnapshot

    /// The bits of playback state the inspector needs, passed in rather than
    /// depended on: this panel belongs to the shell, not to playback.
    struct PlaybackSnapshot {
        let currentTime: Double
        let duration: Double
        let drawnCount: Int
        let spriteCount: Int
        let bpm: Double?
    }


    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
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
                }
                .padding(Theme.Spacing.compact)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .surface(.panel)
    }

    /// The selected effect's declared parameters, grouped as it declared them.
    @ViewBuilder
    private func effectParameters(descriptor: EffectDescriptor, node: EffectNode) -> some View {
        timingRow(node: node)

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
                    .fill(track.layer.tint)
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
