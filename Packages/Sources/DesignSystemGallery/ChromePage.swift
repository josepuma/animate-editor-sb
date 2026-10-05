import DesignSystem
import SwiftUI

/// The pieces that give a window its structure.
struct ChromePage: View {
    private enum Panel: String, CaseIterable, Identifiable, Hashable {
        case scripts = "Scripts"
        case assets = "Assets"
        case timing = "Timing"
        var id: Self { self }

        var icon: String {
            switch self {
            case .scripts: "curlybraces"
            case .assets: "photo.on.rectangle"
            case .timing: "metronome"
            }
        }
    }

    private enum Filter: String, CaseIterable, Identifiable, Hashable {
        case all = "All"
        case used = "Used"
        case missing = "Missing"
        var id: Self { self }
    }

    private enum Tool: String, CaseIterable, Identifiable, Hashable {
        case adjust = "Adjust"
        case filter = "Filter"
        case effect = "Effect"
        case blur = "Blur"
        case copy = "Copy"
        var id: Self { self }

        var icon: String {
            switch self {
            case .adjust: "slider.horizontal.3"
            case .filter: "camera.filters"
            case .effect: "wand.and.stars"
            case .blur: "drop"
            case .copy: "square.on.square"
            }
        }
    }

    @State private var tool: Tool = .filter
    @State private var panel: Panel = .assets
    @State private var filter: Filter = .all

    var body: some View {
        Specimen(
            "ToolTabs",
            note: "Icon over name, the active one in the accent with a pill beneath that slides between tabs. One thing at a time: a panel that stacks every group makes people scroll past five sections to reach the sixth.",
        ) {
            ToolTabs(items: Tool.allCases, selection: $tool, icon: \.icon, label: \.rawValue)
                .padding(.horizontal, Theme.Spacing.snug)
                .padding(.bottom, Theme.Spacing.tight)
                .frame(width: 380)
                .background(Theme.Tone.panel, in: .rect(cornerRadius: Theme.Radius.panel))
        }

        Specimen("SidebarRail", note: "No fills: the chosen item lights up in the accent with a pill at the edge, so the rail stays a column of icons rather than a column of tiles.") {
            HStack(alignment: .top, spacing: Theme.Spacing.regular) {
                SidebarRail(items: Panel.allCases, selection: $panel, icon: \.icon, label: \.rawValue)
                    .frame(width: Theme.Size.controlLarge)
                    .surface(.panel)

                Text("Showing: \(panel.rawValue)")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.tertiary)

                Spacer(minLength: 0)
            }
        }

        Specimen("SectionHeader") {
            VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
                SectionHeader("Recent")
                SectionHeader("Assets") {
                    IconButton(systemImage: "plus", size: Theme.Size.controlTiny) {}
                }
            }
            .frame(maxWidth: 320)
        }

        Specimen("ChipPicker", note: "Mutually exclusive filters, as above a list. Separate pills; the chosen one outlined in the accent, not filled.") {
            SpecimenRow {
                ChipPicker(items: Filter.allCases, selection: $filter, label: \.rawValue)
            }
        }

        Specimen("Card", note: "An optional status dot, a title, a subtitle, a trailing accessory, and content beneath.") {
            HStack(alignment: .top, spacing: Theme.Spacing.regular) {
                Card(title: "intro.ts", subtitle: "142 sprites", statusTint: Theme.TrackPalette.green) {
                    IconButton(systemImage: "ellipsis", size: Theme.Size.controlTiny) {}
                } content: {
                    Text("Ran in 24 ms")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.tertiary)
                }
                .frame(width: 260)

                Card(title: "particles.ts", subtitle: "Failed to compile", statusTint: Theme.Palette.danger) {
                    Text("Line 42")
                        .font(Theme.Typography.readout)
                        .foregroundStyle(Theme.Palette.danger)
                }
                .frame(width: 260)

                Spacer(minLength: 0)
            }
        }
    }
}
