import DesignSystem
import EditorShellFeature
import ProjectBrowserFeature
import StoryboardCore
import StoryboardRendering
import SwiftUI

/// Real pictures for the sprite picker, decoded once: the same thumbnails the
/// app feeds it, so the specimen is judged against what the editor shows.
@MainActor private let galleryThumbnails: SpriteThumbnails = {
    let pictures = Dictionary(uniqueKeysWithValues: BuiltInSprite.catalogue.compactMap { entry in
        BuiltInTextures.thumbnail(for: entry.path).map { (entry.path, $0) }
    })
    return SpriteThumbnails(image: { pictures[$0] }, request: { _ in })
}()

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
                        // A sound: its own speaker glyph in place of the
                        // sparkles, and no thumbnail plate — it draws nothing.
                        block(tint, label: "clap.wav", isSound: true)
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

        Specimen(
            "SpritePicker",
            note: "Choosing a particle's image: the field shows the current one beside its name — the adjustable dot, a built-in, a beatmap's own path — and opens a grid of every built-in, grouped and searchable. White shapes on the dark well they were drawn for; the chosen one outlined in the accent. Entries come from Core's catalogue, so nothing that exists is missing.",
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
                SpritePicker(path: "", thumbnails: galleryThumbnails) { _ in }
                SpritePicker(path: BuiltInSprite.hudSegments, thumbnails: galleryThumbnails) { _ in }
                SpritePicker(path: "sb/my-own.png", thumbnails: galleryThumbnails) { _ in }
            }
            .frame(width: 240)
            .padding(Theme.Spacing.snug)
            .background(Theme.Tone.panel, in: .rect(cornerRadius: Theme.Radius.control))

            SpritePickerPanel(selection: BuiltInSprite.flame, thumbnails: galleryThumbnails) { _ in }
                .clipShape(.rect(cornerRadius: Theme.Radius.control))
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

        Specimen("PosterCard", note: "A beatmap in the project browser: artwork, its title and a quiet line of artist · tempo over a black scrim, and the busy state. Hover lights the edge; the card does not grow.") {
            HStack(alignment: .top, spacing: Theme.Spacing.regular) {
                PosterCard(title: "Toki wo Kizamu Uta", subtitle: "Konomi Suzuki · 128 BPM", action: {}) {
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

        Specimen("ShelfCard", note: "A project on the home shelf: 16:9 art with the title and artist · tempo beneath it, never over it — a row of scrims is a row of smudges. Featured is outlined in the accent; hover lightens the hairline; busy shows a spinner over a scrim.") {
            HStack(alignment: .top, spacing: Theme.Spacing.loose) {
                ShelfCard(title: "Toki wo Kizamu Uta", subtitle: "Konomi Suzuki · 128 BPM", isFeatured: true, action: {}) {
                    PosterArtwork(url: nil)
                }
                .frame(width: Theme.Size.shelfCard)
                ShelfCard(title: "miracle", subtitle: "Celldweller", action: {}) {
                    PosterArtwork(url: nil, fallbackSymbol: "waveform")
                }
                .frame(width: Theme.Size.shelfCard)
                ShelfCard(title: "In the Rain", subtitle: "Opening…", isBusy: true, action: {}) {
                    PosterArtwork(url: nil)
                }
                .frame(width: Theme.Size.shelfCard)
                Spacer(minLength: 0)
            }
        }

        Specimen("FeaturedHero", note: "The home screen's poster: the featured project's storyboard plays behind its name (here only the artwork placeholder — the trailer is a live render the app supplies). Full bleed: a black scrim from the side the words sit on, and the foot dissolving into the page tone so the first row of projects starts on the poster. Muted until asked.") {
            FeaturedHero(
                title: "Toki wo Kizamu Uta",
                artist: "Konomi Suzuki",
                detail: "Mapped by someone · 128 BPM",
                artworkURL: nil,
                isMuted: true,
                isOpening: false,
                open: {},
                toggleMute: {},
            ) {
                EmptyView()
            }
            .frame(height: Theme.Size.heroMinimum)
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
        isSound: Bool = false,
    ) -> some View {
        TrackBlock(
            tint: tint,
            label: label,
            isDimmed: isDimmed,
            isSelected: isSelected,
            cornerRadius: Theme.Radius.clip,
        ) {
            if !isSound {
                RoundedRectangle(cornerRadius: Theme.Radius.small)
                    .fill(.white.opacity(0.18))
                    .frame(width: 24)
            }
        } badge: {
            BlockBadge(systemImage: isSound ? SampleEffect.descriptor.systemImage : "sparkles")
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
