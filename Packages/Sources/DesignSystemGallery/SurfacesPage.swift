import DesignSystem
import SwiftUI

/// Which surfaces are glass and which are not, and why.
///
/// The deciding question is what sits behind. Glass earns its cost only over
/// the canvas; a panel at the window edge has nothing behind it but the
/// desktop, so refracting there buys no depth and costs contrast.
struct SurfacesPage: View {
    private let opaque: [(String, SurfaceRole, String)] = [
        ("panel", .panel, "Holds content: cards, side panel, inspector."),
        ("raised", .raised, "Above its siblings — a popover, an active selection."),
        ("inset", .inset, "Reads as sunken: the well a control sits in."),
        ("bar", .bar, "A strip anchored to the window: the toolbar, the rail."),
    ]

    private let glass: [(String, SurfaceRole, String)] = [
        ("floating", .floating, "Over the canvas: transport, coordinate readout."),
    ]

    var body: some View {
        Specimen(
            "Opaque — anchored to the window",
            note: "Four of the five roles. Nothing worth refracting sits behind them.",
        ) {
            SpecimenRow {
                ForEach(opaque, id: \.0) { name, role, _ in
                    surfaceTile(name, role)
                }
            }
        }

        Specimen(
            "Glass — floating over the canvas",
            note: "One role. This is the only place the storyboard shows through.",
        ) {
            SpecimenRow {
                ForEach(glass, id: \.0) { name, role, _ in
                    surfaceTile(name, role)
                }
            }
        }

        Specimen(
            "The same roles over bright artwork",
            note: "This is the test that matters — the canvas can be any colour. Only .floating carries a scrim, and only it stays legible.",
        ) {
            ZStack {
                LinearGradient(
                    colors: [.white, Theme.TrackPalette.amber.opacity(0.9), .white],
                    startPoint: .leading,
                    endPoint: .trailing,
                )
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))

                HStack(spacing: Theme.Spacing.regular) {
                    ForEach(opaque + glass, id: \.0) { name, role, _ in
                        Text(name)
                            .font(Theme.Typography.label)
                            .foregroundStyle(.white)
                            .padding(.horizontal, Theme.Spacing.compact)
                            .frame(height: Theme.Size.control)
                            .capsuleSurface(role)
                    }
                }
            }
        }

        Specimen("What each role is for") {
            VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
                ForEach(opaque + glass, id: \.0) { name, role, note in
                    HStack(alignment: .top, spacing: Theme.Spacing.compact) {
                        Text(".\(name)")
                            .font(Theme.Typography.readout)
                            .foregroundStyle(Theme.Palette.accent)
                            .frame(width: 84, alignment: .leading)

                        Text(role.isGlass ? "glass" : "opaque")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(
                                role.isGlass ? Theme.TrackPalette.teal : Theme.Palette.tertiary,
                            )
                            .frame(width: 56, alignment: .leading)

                        Text(note)
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Palette.secondary)
                    }
                }
            }
        }

        Specimen(
            "Capsule versus rounded rectangle",
            note: "A radius smaller than half the height reads as a soft-cornered box, not a pill.",
        ) {
            SpecimenRow {
                Text("capsuleSurface")
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Palette.secondary)
                    .padding(.horizontal, Theme.Spacing.regular)
                    .frame(height: Theme.Size.pill)
                    .capsuleSurface(.bar)

                Text("surface(.bar)")
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Palette.secondary)
                    .padding(.horizontal, Theme.Spacing.regular)
                    .frame(height: Theme.Size.pill)
                    .surface(.bar)
            }
        }
    }

    private func surfaceTile(_ name: String, _ role: SurfaceRole) -> some View {
        Text(name)
            .font(Theme.Typography.label)
            .foregroundStyle(Theme.Palette.secondary)
            .frame(width: 110, height: 72)
            .surface(role)
    }
}
