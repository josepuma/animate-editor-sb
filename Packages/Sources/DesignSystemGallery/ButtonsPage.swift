import DesignSystem
import SwiftUI

/// The variant grid — every intent against every size, which is the only way to
/// see that a recipe is missing or that two of them collide.
struct ButtonsPage: View {
    private let variants: [(String, ButtonVariant)] = [
        ("primary", .primary),
        ("secondary", .secondary),
        ("ghost", .ghost),
        ("destructive", .destructive),
    ]

    private let sizes: [(String, ButtonSize)] = [
        ("small", .small),
        ("regular", .regular),
        ("large", .large),
    ]

    var body: some View {
        Specimen(
            "Variants",
            note: "The variant carries the whole recipe, so a call site names an intent rather than assembling one.",
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
                ForEach(sizes, id: \.0) { sizeName, size in
                    HStack(spacing: Theme.Spacing.compact) {
                        Text(sizeName)
                            .font(Theme.Typography.readout)
                            .foregroundStyle(Theme.Palette.tertiary)
                            .frame(width: 64, alignment: .leading)

                        ForEach(variants, id: \.0) { name, variant in
                            Button(name) {}
                                .buttonStyle(.themed(variant, size: size))
                        }

                        Spacer(minLength: 0)
                    }
                }
            }
        }

        Specimen("With a symbol") {
            SpecimenRow {
                Button("Open Folder", systemImage: "plus") {}
                    .buttonStyle(.themed(.secondary))
                Button("Export", systemImage: "square.and.arrow.up") {}
                    .buttonStyle(.themed(.primary))
                Button("Delete", systemImage: "trash") {}
                    .buttonStyle(.themed(.destructive))
            }
        }

        Specimen(
            "Capsule",
            note: "For controls floating over content. Bars read as pills; buttons inside a panel do not.",
        ) {
            SpecimenRow {
                ForEach(variants, id: \.0) { name, variant in
                    Button(name) {}
                        .buttonStyle(.themed(variant, capsule: true))
                }
            }
        }

        Specimen("Disabled", note: "The style dims from the environment, so .disabled() works as it does anywhere.") {
            SpecimenRow {
                ForEach(variants, id: \.0) { name, variant in
                    Button(name) {}
                        .buttonStyle(.themed(variant))
                        .disabled(true)
                }
            }
        }

        Specimen(
            "IconButton",
            note: "Its own component rather than a variant: the shape is the point — a square target sized to its glyph, with no label to pad around.",
        ) {
            SpecimenRow {
                IconButton(systemImage: "play.fill", prominence: .accented, help: "Play") {}
                IconButton(systemImage: "pause.fill", help: "Pause") {}
                IconButton(systemImage: "gobackward", prominence: .surfaced, help: "Restart") {}
            }
        }

        Specimen(
            "Sizes",
            note: "The same glyph at every size — the only way to see that the padding holds. Glyph and corner are both fractions of the target: a fixed 15pt glyph leaves 3pt of air in a 22pt button, which reads as no padding at all.",
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
                sizeRow("controlLarge", Theme.Size.controlLarge)
                sizeRow("control", Theme.Size.control)
                sizeRow("controlSmall", Theme.Size.controlSmall)
                sizeRow("controlTiny", Theme.Size.controlTiny)
            }
        }

        Specimen(
            "Row toggles",
            note: "`.filled` keeps its fill at rest, and `isActive: false` dims the glyph without changing the shape — a control that appears only under the pointer reads as missing from a list.",
        ) {
            SpecimenRow {
                IconButton(
                    systemImage: "eye",
                    size: Theme.Size.controlTiny,
                    prominence: .filled,
                    help: "Visible",
                ) {}
                IconButton(
                    systemImage: "eye.slash",
                    size: Theme.Size.controlTiny,
                    prominence: .filled,
                    isActive: false,
                    help: "Hidden",
                ) {}
                IconButton(
                    systemImage: "lock.fill",
                    size: Theme.Size.controlTiny,
                    prominence: .filled,
                    help: "Locked",
                ) {}
                IconButton(
                    systemImage: "lock.open",
                    size: Theme.Size.controlTiny,
                    prominence: .filled,
                    isActive: false,
                    help: "Unlocked",
                ) {}
            }
        }

        Specimen("FloatingBar", note: "The shared container for transport, stats and switchers.") {
            floatingBarSpecimen
        }
    }

    /// One size across every prominence, so a size that breaks the padding
    /// shows up in all of them at once.
    private func sizeRow(_ name: String, _ size: CGFloat) -> some View {
        HStack(spacing: Theme.Spacing.compact) {
            Text("\(name)  \(Int(size))")
                .font(Theme.Typography.readout)
                .foregroundStyle(Theme.Palette.tertiary)
                .frame(width: 130, alignment: .leading)

            IconButton(systemImage: "eye", size: size) {}
            IconButton(systemImage: "eye", size: size, prominence: .filled) {}
            IconButton(systemImage: "eye", size: size, prominence: .surfaced) {}
            IconButton(systemImage: "eye", size: size, prominence: .accented) {}

            Spacer(minLength: 0)
        }
    }

    private var floatingBarSpecimen: some View {
        FloatingBar {
            IconButton(systemImage: "backward.end.fill", size: Theme.Size.controlSmall) {}
            IconButton(systemImage: "play.fill", prominence: .accented) {}
            IconButton(systemImage: "forward.end.fill", size: Theme.Size.controlSmall) {}
            BarDivider()
            Readout("01:24.500", systemImage: "clock")
            BarDivider()
            Readout("2127", systemImage: "square.stack.3d.up", tint: Theme.Palette.accent)
            Readout("60 fps", systemImage: "gauge", tint: Theme.TrackPalette.green)
        }
    }
}
