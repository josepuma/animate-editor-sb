import DesignSystem
import StoryboardCore
import SwiftUI

/// The right panel: the selected script's parameters.
///
/// Scripting is not implemented, so the properties shown are samples standing
/// in for what a script will declare. The controls are real — the values simply
/// have nothing to drive yet.
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

    @State private var groups = ScriptPropertyGroup.samples()
    @State private var alignment = TextAlignmentOption.leading

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
                    trackSummary
                    alignmentRow

                    ForEach($groups) { $group in
                        FieldGroup(group.name) {
                            ForEach($group.properties) { $property in
                                PropertyControl(property: $property)
                            }
                        }
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

                Text("\(track.spriteCount)")
                    .font(Theme.Typography.readout)
                    .foregroundStyle(Theme.Palette.tertiary)
                    .help("Sprites this script produces")
            }
        }
    }

    /// Alignment as its own row of icons, as the reference lays out.
    private var alignmentRow: some View {
        IconSegments(
            items: TextAlignmentOption.allCases,
            selection: $alignment,
            icon: \.systemImage,
            label: \.title,
        )
    }
}

// ─── Property control ────────────────────────────────────────────────────────

/// Renders whichever control a property's kind calls for.
private struct PropertyControl: View {
    @Binding var property: ScriptProperty

    var body: some View {
        PropertyRow(property.name) {
            control
        }
    }

    @ViewBuilder
    private var control: some View {
        switch property.value {
        case let .number(value, unit, range, step):
            NumberField(
                value: Binding(
                    get: { value },
                    set: { property.value = .number($0, unit: unit, range: range, step: step) },
                ),
                unit: unit,
                step: step,
                range: range,
                format: step < 1 ? "%.1f" : "%.0f",
            )

        case let .slider(value, range):
            SliderField(
                value: Binding(
                    get: { value },
                    set: { property.value = .slider($0, range: range) },
                ),
                range: range,
            )

        case let .color(color, hex):
            ColorField(
                color: Binding(
                    get: { color },
                    set: { property.value = .color($0, hex: hex) },
                ),
                hex: hex,
            )

        case let .choice(selected, options):
            MenuField(
                items: options.map(ChoiceOption.init),
                selection: Binding(
                    get: { ChoiceOption(selected) },
                    set: { property.value = .choice($0.id, options: options) },
                ),
                label: \.id,
            )

        case let .toggle(isOn):
            Toggle(
                "",
                isOn: Binding(
                    get: { isOn },
                    set: { property.value = .toggle($0) },
                ),
            )
            .labelsHidden()
            .controlSize(.mini)
            .frame(maxWidth: .infinity, alignment: .leading)

        case let .text(value):
            FieldWell {
                Text(value)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Wraps a plain string so it can drive an identifiable menu.
private struct ChoiceOption: Hashable, Identifiable {
    let id: String

    init(_ id: String) {
        self.id = id
    }
}

// ─── Alignment ───────────────────────────────────────────────────────────────

private enum TextAlignmentOption: String, CaseIterable, Identifiable {
    case leading
    case centre
    case trailing
    case justified
    case italic
    case underline

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .leading: "text.alignleft"
        case .centre: "text.aligncenter"
        case .trailing: "text.alignright"
        case .justified: "text.justify"
        case .italic: "italic"
        case .underline: "underline"
        }
    }

    var title: String {
        switch self {
        case .leading: "Align left"
        case .centre: "Align centre"
        case .trailing: "Align right"
        case .justified: "Justify"
        case .italic: "Italic"
        case .underline: "Underline"
        }
    }
}
