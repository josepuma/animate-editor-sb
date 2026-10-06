import CoreGraphics
import DesignSystem
import EditorShellFeature
import SwiftUI

/// How the library shows what things look like: tiles, placeholders, moving previews
/// and script cards.
///
/// The reference language lives here more than anywhere — pictures with their
/// names over a black scrim, flat placeholders where there is no picture, and
/// the accent outlining whichever one is chosen.
struct PreviewsPage: View {
    /// Rendered after the page appears, so opening it is not held up by the
    /// renderer; until then every card shows its placeholder, which is the
    /// state the library shows too while a preview is on its way.
    @State private var previews: [String: [CGImage]] = [:]

    /// The presets shown, by id — text among them, which is what the stand-in
    /// frames this replaced could not draw.
    private static let shown: [(id: String, title: String, systemImage: String, tint: Color)] = [
        ("fire-ring", "Fire Ring", "flame", Theme.TrackPalette.amber),
        ("sparks", "Sparks", "sparkles", Theme.Palette.accent),
        ("portal", "Portal", "circle.dashed", Theme.TrackPalette.violet),
        ("typewriter", "Typewriter", "textformat", Theme.TrackPalette.teal),
        ("glitch", "Glitch", "textformat", Theme.TrackPalette.pink),
        ("bokeh", "Bokeh", "circle.hexagongrid", Theme.TrackPalette.blue),
    ]

    private func frames(_ id: String) -> [CGImage] { previews[id] ?? [] }

    @State private var selectedTile = "portal"
    @State private var selectedTag = "Video Effects"
    @State private var renamedScript = "wave-mesh"

    /// The poster frame of each preview, for tiles that show a still.
    private var stills: [(id: String, title: String, frame: CGImage)] {
        Self.shown.compactMap { item in
            let all = frames(item.id)
            // The poster, not the first frame — which is the empty instant
            // before anything has entered.
            return all.isEmpty ? nil : (item.id, item.title, all[FrameSequence.posterIndex(count: all.count)])
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: Theme.Spacing.compact)]

    var body: some View {
        Group { content }
            .task { previews = RealPreviews.frames(for: Self.shown.map(\.id)) }
    }

    @ViewBuilder
    private var content: some View {
        Specimen(
            "Tag",
            note: "A thing rather than an action — a clip's name, a category. Chosen ones are outlined in the accent, never filled. Without an action it is a label and ignores the pointer.",
        ) {
            SpecimenRow {
                ForEach(["Video Effects", "Flow Lifestyle", "Lyrics"], id: \.self) { name in
                    Tag(
                        name,
                        systemImage: name == "Lyrics" ? "textformat" : (name == "Video Effects" ? "wand.and.stars" : "sparkles"),
                        isSelected: selectedTag == name,
                    ) {
                        selectedTag = name
                    }
                }
                Tag("Label only", systemImage: "tag")
            }
        }

        Specimen(
            "ArtworkPlaceholder",
            note: "Where a picture will be, or cannot be: a flat plate and a glyph. The tint colours only the glyph. No decorative gradients anywhere in the system — the only ones drawn are black scrims under text over a picture.",
        ) {
            SpecimenRow {
                placeholder(nil, nil)
                placeholder("photo", nil)
                placeholder("curlybraces", Theme.Palette.accent)
                placeholder("exclamationmark.triangle", Theme.Palette.warning)
            }
        }

        Specimen(
            "MediaTile",
            note: "A picture with its name over a gradient at the foot. Click to select — the outline is the accent, the picture is never tinted.",
        ) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.compact) {
                ForEach(stills, id: \.id) { item in
                    let (id, name, frame) = item
                    MediaTile(
                        title: name,
                        isSelected: selectedTile == id,
                        action: { selectedTile = id },
                    ) {
                        ZStack {
                            Theme.Palette.stage
                            Image(decorative: frame, scale: 1).resizable().scaledToFill()
                        }
                    }
                }
            }
        }

        Specimen(
            "FrameSequence",
            note: "Twelve frames on a loop — the Typewriter preset, rendered. Playing on the left, held on its poster frame on the right — two thirds through, since the first frame is the empty instant before anything enters. The timer only runs while playing.",
        ) {
            SpecimenRow {
                FrameSequence(frames("typewriter"), isPlaying: true)
                    .frame(width: 192, height: 108)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.bar, style: .continuous))
                FrameSequence(frames("typewriter"), isPlaying: false)
                    .frame(width: 192, height: 108)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.bar, style: .continuous))
            }
        }

        Specimen(
            "EffectPreviewCard",
            note: "The library's tile for an effect, filter or preset, with the renderer's real preview — text presets included. Still at rest and playing under the pointer — forty previews all moving is noise. The last card has no frames, to show the placeholder a preview sits on while it renders.",
        ) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.compact) {
                ForEach(Self.shown, id: \.id) { item in
                    EffectPreviewCard(
                        title: item.title,
                        systemImage: item.systemImage,
                        tint: item.tint,
                        frames: frames(item.id),
                        isSelected: item.id == "sparks",
                    )
                }
                EffectPreviewCard(title: "Not rendered yet", systemImage: "sun.max", tint: Theme.TrackPalette.pink)
            }
        }

        Specimen(
            "ScriptCard",
            note: "A script shows its code: the shape of the code is what you recognise, the file name is what you read. Its state is a dot — accent, red, amber — with the detail on hover. ×N appears when several clips share the file — editing it reloads all of them. The first card can be renamed: double-click its name, or right-click → Rename….",
        ) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: Theme.Spacing.compact)],
                alignment: .leading,
                spacing: Theme.Spacing.compact,
            ) {
                ScriptCard(
                    fileName: renamedScript + ".js",
                    editableName: renamedScript,
                    snippet: Self.waveMesh,
                    status: .ready,
                    clipCount: 3,
                    tint: Theme.TrackPalette.blue,
                    rename: { renamedScript = $0 },
                    openInEditor: {},
                )
                ScriptCard(
                    fileName: "lyrics-intro.js",
                    snippet: Self.lyrics,
                    status: .ready,
                    clipCount: 1,
                    tint: Theme.TrackPalette.pink,
                    isSelected: true,
                )
                ScriptCard(
                    fileName: "particles.js",
                    snippet: Self.waveMesh,
                    status: .failed("Line 42: Ease.outQuad does not exist"),
                    clipCount: 1,
                    tint: Theme.TrackPalette.amber,
                )
                ScriptCard(
                    fileName: "old-intro.js",
                    snippet: [],
                    status: .missing,
                    clipCount: 2,
                    tint: Theme.TrackPalette.violet,
                )
            }
        }
    }

    private func placeholder(_ systemImage: String?, _ tint: Color?) -> some View {
        ArtworkPlaceholder(systemImage: systemImage, tint: tint)
            .frame(width: 120, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.bar, style: .continuous))
    }

    private static let waveMesh = [
        "const rows = param('Rows', 12)",
        "for (let y = 0; y < rows; y++) {",
        "  for (let x = 0; x < cols; x++) {",
        "    const s = sprite(Image.glow)",
        "    s.move(Ease.quadOut, 0, 900, x, y)",
    ]

    private static let lyrics = [
        "const line = text('Toki wo kizamu')",
        "line.forEach((glyph, i) => {",
        "  glyph.fade(0, 40 * i, 200, 0, 1)",
        "})",
    ]
}
