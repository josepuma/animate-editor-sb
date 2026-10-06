import DesignSystem
import EditorShellFeature
import ProjectBrowserFeature
import SwiftUI

/// Components that name something in the domain — a clip, a playhead, a
/// beatmap's poster — shown with the same tokens as everything else.
///
/// They live in their features, not in the design system, because they would
/// not survive being copied to another project. They are here because this is
/// where the tokens meet real content: a palette that works on swatches and
/// fails on a lane full of clips is a palette that fails.
struct CompositesPage: View {
    private let tints: [(String, Color)] = [
        ("blue", Theme.TrackPalette.blue),
        ("violet", Theme.TrackPalette.violet),
        ("pink", Theme.TrackPalette.pink),
        ("teal", Theme.TrackPalette.teal),
        ("amber", Theme.TrackPalette.amber),
        ("green", Theme.TrackPalette.green),
        ("red", Theme.TrackPalette.red),
    ]

    var body: some View {
        Specimen(
            "TrackBlock",
            note: "A clip on a lane, in every track colour — resting, selected and dimmed. The selection has to win against every tint, which is the test the accent is chosen for.",
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
                ForEach(tints, id: \.0) { name, tint in
                    HStack(spacing: Theme.Spacing.snug) {
                        Text(name)
                            .font(Theme.Typography.readout)
                            .foregroundStyle(Theme.Palette.tertiary)
                            .frame(width: 56, alignment: .leading)

                        block(tint, label: "Emitter")
                        block(tint, label: "Selected", isSelected: true)
                        block(tint, label: "Hidden", isDimmed: true)
                    }
                }
            }
            .padding(Theme.Spacing.snug)
            .background(Theme.Tone.panel, in: .rect(cornerRadius: Theme.Radius.control))
        }

        Specimen(
            "Clip with its tail",
            note: "What a clip keeps drawing after its block ends — an emitter's last particles dying out — hatched in the track's colour, flat against the block. Hatched rather than faded: the system draws no decorative gradients, and stripes say \"derived from the clip\" the way editors mark a clip's handles.",
        ) {
            HStack(spacing: -Theme.Radius.bar) {
                block(Theme.TrackPalette.violet, label: "Fire Ring")
                tail(Theme.TrackPalette.violet)
                    .zIndex(-1)
            }
            .padding(Theme.Spacing.snug)
            .background(Theme.Tone.panel, in: .rect(cornerRadius: Theme.Radius.control))
        }

        Specimen("BlockBadge", note: "A clip's type indicator, at the trailing edge of its block.") {
            SpecimenRow {
                ForEach(["sparkles", "textformat", "photo", "curlybraces"], id: \.self) { icon in
                    BlockBadge(systemImage: icon)
                        .padding(Theme.Spacing.tight)
                        .background(Theme.TrackPalette.blue, in: .rect(cornerRadius: Theme.Radius.small))
                }
            }
        }

        Specimen(
            "PlayheadHandle",
            note: "The head of the playhead, drawn over the ruler. The playhead token is white now: it marks where you are, not something you chose.",
        ) {
            SpecimenRow {
                handle("default", PlayheadHandle())
                handle("playhead", PlayheadHandle(tint: Theme.Palette.playhead))
            }
        }

        Specimen("PosterCard", note: "A beatmap in the project browser: artwork, a caption over its gradient, an optional badge, and the busy state.") {
            HStack(alignment: .top, spacing: Theme.Spacing.regular) {
                PosterCard(title: "Toki wo Kizamu Uta", subtitle: "Konomi Suzuki", badge: "Storyboard", action: {}) {
                    PosterArtwork(url: nil)
                }
                .frame(width: 160)

                PosterCard(title: "miracle", subtitle: "Celldweller", action: {}) {
                    PosterArtwork(url: nil, fallbackSymbol: "waveform")
                }
                .frame(width: 160)

                PosterCard(title: "In the Rain", subtitle: "Opening…", isBusy: true, action: {}) {
                    PosterArtwork(url: nil)
                }
                .frame(width: 160)

                Spacer(minLength: 0)
            }
        }

        Specimen("ComingSoon", note: "The empty state of a panel with nothing to show — labelled, because an unlabelled blank reads as a bug.") {
            ComingSoon(
                title: "No selection",
                detail: "Select a clip to edit its parameters.",
                systemImage: "cursorarrow.click",
            )
            .frame(width: 280)
            .background(Theme.Tone.panel, in: .rect(cornerRadius: Theme.Radius.panel))
        }
    }

    private func block(
        _ tint: Color,
        label: String,
        isSelected: Bool = false,
        isDimmed: Bool = false,
    ) -> some View {
        TrackBlock(
            tint: tint,
            label: label,
            isDimmed: isDimmed,
            isSelected: isSelected,
            cornerRadius: Theme.Radius.clip,
        ) {
            RoundedRectangle(cornerRadius: Theme.Radius.small)
                .fill(.white.opacity(0.18))
                .frame(width: 24)
        } badge: {
            BlockBadge(systemImage: "sparkles")
        }
        .frame(width: 150, height: 32)
    }

    private func tail(_ tint: Color) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 0, bottomLeadingRadius: 0,
            bottomTrailingRadius: Theme.Radius.bar, topTrailingRadius: Theme.Radius.bar,
            style: .continuous,
        )
        return shape
            .fill(tint.opacity(0.12))
            .overlay {
                Hatching(spacing: Theme.Spacing.snug)
                    .stroke(tint.opacity(0.45), lineWidth: Theme.Size.hairline)
                    .clipShape(shape)
            }
            .frame(width: 110 + Theme.Radius.bar, height: 32)
    }

    private func handle(_ name: String, _ handle: PlayheadHandle) -> some View {
        VStack(spacing: Theme.Spacing.tight) {
            handle
                .padding(Theme.Spacing.snug)
                .background(Theme.Tone.panel, in: .rect(cornerRadius: Theme.Radius.small))

            Text(name)
                .font(Theme.Typography.readout)
                .foregroundStyle(Theme.Palette.tertiary)
        }
    }
}
