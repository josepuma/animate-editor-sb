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

    @State private var panel: Panel = .assets
    @State private var filter: Filter = .all

    var body: some View {
        Specimen("SidebarRail", note: "Only the selected item carries a fill, so the rail reads as one control rather than a row of buttons.") {
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

        Specimen("ChipPicker", note: "Mutually exclusive filters, as above a list.") {
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
