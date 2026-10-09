import CoreGraphics
import DesignSystem
import EditorShellFeature
import SwiftUI

/// The rows and cards the editor's panels are made of, with the same content in
/// every state so two of them can be compared by eye.
///
/// Each takes plain values and closures — the panel that owns the model decides
/// what to pass — which is what lets them sit here without a document behind
/// them. Hover cannot be forced from a page, so a row that changes on hover says
/// so in its note.
struct PanelsPage: View {
    /// Real previews, rendered after the page appears — see `RealPreviews`.
    @State private var previews: [String: [CGImage]] = [:]

    private var fire: [CGImage] { previews["fire-ring"] ?? [] }
    private var portal: [CGImage] { previews["portal"] ?? [] }
    private var typewriter: [CGImage] { previews["typewriter"] ?? [] }

    var body: some View {
        Group { content }
            .task { previews = RealPreviews.frames(for: ["fire-ring", "portal", "typewriter"]) }
    }

    @ViewBuilder
    private var content: some View {
        pieces
        composed
        layers
        library
        filters
        assets
        lyrics
        inspector
    }

    // ─── Pieces ──────────────────────────────────────────────────────────────

    @ViewBuilder
    private var pieces: some View {
        Specimen(
            "Row pieces",
            note: "What every row is built from. A GlyphTile is the row's picture — a dot says \"this has a colour\", a tile says \"this is a thing\". CountBadge for counts (accented when live), AddBadge lights in the accent under the pointer, and rowSurface gives every list the same three states.",
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
                SpecimenRow {
                    GlyphTile(systemImage: "sparkles", tint: Theme.TrackPalette.violet)
                    GlyphTile(systemImage: "waveform", tint: Theme.TrackPalette.pink)
                    GlyphTile(systemImage: "textformat", tint: Theme.TrackPalette.teal)
                    GlyphTile(systemImage: "photo", tint: nil)
                    GlyphTile(initialOf: "Lyrics", tint: Theme.TrackPalette.amber)
                    GlyphTile(initialOf: "Background", tint: Theme.TrackPalette.blue, size: Theme.Size.controlLarge)
                    GlyphTile(systemImage: "sun.max", tint: Theme.KeyframePalette.filter, size: Theme.Size.controlTiny)
                }
                SpecimenRow {
                    CountBadge(14)
                    CountBadge(3, isAccented: true)
                    CountBadge("×2")
                    AddBadge(isHighlighted: false)
                    AddBadge(isHighlighted: true)
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    StateRow("rest") { surfaceSample("Resting") }
                    StateRow("hover") { surfaceSample("Hovered").rowSurface(isHovered: true) }
                    StateRow("selected") { surfaceSample("Selected").rowSurface(isSelected: true) }
                }
            }
        }
    }

    private func surfaceSample(_ title: String) -> some View {
        Text(title)
            .font(Theme.Typography.label)
            .foregroundStyle(Theme.Palette.primary)
            .padding(.horizontal, Theme.Spacing.compact)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.control, alignment: .leading)
    }

    // ─── Composed ────────────────────────────────────────────────────────────

    /// The rows together on a panel, the way the side panel stacks them.
    ///
    /// One at a time every row can look right and still disagree with its
    /// neighbours — a tile one size off, two ideas of hover. Stacked, it shows.
    private var composed: some View {
        Specimen(
            "A library panel, assembled",
            note: "Chips, effect, presets with previews, and the next effect — on the panel tone. Hover a preset to play it.",
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                chipRow(["All", "Emitter", "Text", "Audio"], selected: "Emitter")
                EffectHeaderRow(
                    name: "Emitter",
                    systemImage: "sparkles",
                    presetCount: 54,
                    isExpanded: true,
                    toggleExpanded: {},
                    add: {},
                    tint: Theme.TrackPalette.violet,
                )
                VStack(alignment: .leading, spacing: Theme.Spacing.hair) {
                    PresetRow(name: "Fire Ring", summary: "A circle of flame with embers and a halo", add: {}, tint: Theme.TrackPalette.amber, frames: fire)
                    PresetRow(name: "Portal", summary: "Counter-rotating rings over a haze", add: {}, tint: Theme.TrackPalette.violet, frames: portal)
                    PresetRow(name: "Bokeh", summary: "Soft discs drifting out of focus", add: {}, tint: Theme.TrackPalette.pink)
                }
                .padding(.leading, Theme.Spacing.compact)
                EffectHeaderRow(
                    name: "Text",
                    systemImage: "textformat",
                    presetCount: 14,
                    isExpanded: false,
                    toggleExpanded: {},
                    add: {},
                    tint: Theme.TrackPalette.teal,
                )
            }
            .padding(Theme.Spacing.snug)
            .frame(width: Self.columnWidth + Theme.Spacing.loose)
            .background(Theme.Tone.panel, in: .rect(cornerRadius: Theme.Radius.panel))
        }
    }

    // ─── Layers ──────────────────────────────────────────────────────────────

    @ViewBuilder
    private var layers: some View {
        Specimen(
            "TrackRow",
            note: "A lane in the Layers panel, its colour as a tile with its initial. Selection is the accent ring; hidden dims the tile; a lock lights amber.",
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                StateRow("resting") { track() }
                StateRow("selected") { track(isSelected: true) }
                StateRow("hidden") { track(isVisible: false) }
                StateRow("locked") { track(isLocked: true) }
                StateRow("one effect") { track(name: "Lyrics", tint: Theme.TrackPalette.pink, effects: 1) }
                StateRow("empty") { track(name: "Background", tint: Theme.TrackPalette.blue, effects: 0) }
            }
        }

        Specimen(
            "PlacedEffectRow",
            note: "An effect already on the timeline. The trash button is revealed on hover, so a list of these stays a list rather than a column of buttons.",
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                StateRow("resting") { placed() }
                StateRow("selected") { placed(isSelected: true) }
                StateRow("hidden") { placed(isVisible: false) }
            }
        }
    }

    // ─── Library ─────────────────────────────────────────────────────────────

    @ViewBuilder
    private var library: some View {
        Specimen(
            "EffectHeaderRow",
            note: "The effect itself: a disclosure over its presets, or a plain \"add this\" when it has none. The chevron's space is kept either way so the icons line up.",
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                StateRow("collapsed") { effectHeader(presetCount: 14, isExpanded: false) }
                StateRow("expanded") { effectHeader(presetCount: 14, isExpanded: true) }
                StateRow("no presets") { effectHeader(name: "Image", systemImage: "photo", presetCount: nil, isExpanded: false) }
            }
        }

        Specimen(
            "PresetRow",
            note: "One preset available to place, with its own preview as the row's picture — playing under the pointer — or a glow of its colour until one is rendered. The plus lights in the accent on hover.",
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                PresetRow(name: "Fire Ring", summary: "A circle of flame with embers and a halo", add: {}, tint: Theme.TrackPalette.amber, frames: fire)
                PresetRow(name: "Typewriter", summary: "Letters arrive one after another", add: {}, tint: Theme.TrackPalette.teal, frames: typewriter)
                PresetRow(name: "Shockwave", summary: "A single ring that opens and dissolves", add: {})
            }
            .frame(width: Self.columnWidth)
        }

        Specimen(
            "EffectLibraryRow",
            note: "One effect available to place, with its category beneath. A flat alternative to the header row.",
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                EffectLibraryRow(name: "Emitter", systemImage: "sparkles", category: "Generate", add: {}, tint: Theme.TrackPalette.violet)
                EffectLibraryRow(name: "Audio Bars", systemImage: "waveform", category: "Audio", add: {}, tint: Theme.TrackPalette.pink)
                EffectLibraryRow(name: "Text", systemImage: "textformat", category: "Generate", add: {})
            }
            .frame(width: Self.columnWidth)
        }
    }

    // ─── Filters ─────────────────────────────────────────────────────────────

    /// The chip row of the Filters tab, at specimen size.
    private func chipRow(_ labels: [String], selected: String) -> some View {
        HStack(spacing: Theme.Spacing.tight) {
            ForEach(labels, id: \.self) { label in
                FilterChip(label, isSelected: label == selected) {}
            }
        }
    }

    @ViewBuilder
    private var filters: some View {
        Specimen(
            "Filter chips + FilterLibraryRow",
            note: "The category chips the Filters tab narrows by, and the draggable filter rows under them. Rows dim their grip when nothing is selected to apply to (hover to see the grip light).",
        ) {
            HStack(alignment: .top, spacing: Theme.Spacing.section) {
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    Text("can apply")
                        .font(Theme.Typography.readout)
                        .foregroundStyle(Theme.Palette.tertiary)
                    chipRow(["All", "Look", "Light", "Motion"], selected: "Light")
                    filterRow("Glow", "sun.max", canApply: true)
                    filterRow("Blur", "circle.dotted", canApply: true)
                    filterRow("Shadow", "shadow", canApply: true)
                }
                .frame(width: Self.columnWidth)

                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    Text("nothing selected")
                        .font(Theme.Typography.readout)
                        .foregroundStyle(Theme.Palette.tertiary)
                    chipRow(["All", "Look", "Light", "Motion"], selected: "Light")
                    filterRow("Glow", "sun.max", canApply: false)
                    filterRow("Blur", "circle.dotted", canApply: false)
                    filterRow("Shadow", "shadow", canApply: false)
                }
                .frame(width: Self.columnWidth)
            }
        }

        Specimen(
            "KeyframeGroupHeader",
            note: "The same heading shape inside the keyframe editor: the count of animated properties shows only when there is one.",
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                StateRow("collapsed") {
                    KeyframeGroupHeader(title: "Transform", systemImage: "move.3d", animatedCount: 3, isExpanded: false, toggle: {})
                }
                StateRow("expanded") {
                    KeyframeGroupHeader(title: "Transform", systemImage: "move.3d", animatedCount: 3, isExpanded: true, toggle: {})
                }
                StateRow("none animated") {
                    KeyframeGroupHeader(title: "Glow", systemImage: "sun.max", animatedCount: 0, isExpanded: false, toggle: {})
                }
            }
        }
    }

    // ─── Assets ──────────────────────────────────────────────────────────────

    private var assets: some View {
        Specimen(
            "AssetCard",
            note: "One asset as a tile: the picture filled to the edges, the name and a quiet line of folder · usage over a black scrim. A very long sprite shows its middle. With no picture it shows a placeholder; a missing file says so in amber and outlines the tile.",
        ) {
            HStack(alignment: .top, spacing: Theme.Spacing.snug) {
                AssetCard(
                    asset: AssetItem(id: "1", name: "particle.png", path: "sb/particle.png", kind: .image, useCount: 1),
                    thumbnail: Self.sampleImage,
                    place: {},
                )
                .frame(width: 130)

                AssetCard(
                    asset: AssetItem(id: "2", name: "background.jpg", path: "background.jpg", kind: .image, useCount: 4),
                    thumbnail: Self.sampleImage,
                    place: {},
                )
                .frame(width: 130)

                AssetCard(
                    asset: AssetItem(id: "3", name: "overlay.png", path: "sb/overlay.png", kind: .image, useCount: 0),
                    thumbnail: nil,
                    place: {},
                )
                .frame(width: 130)

                AssetCard(
                    asset: AssetItem(id: "4", name: "logo.png", path: "sb/logo.png", kind: .image, useCount: 2, isMissing: true),
                    thumbnail: nil,
                    place: {},
                )
                .frame(width: 130)

                // A sound has no picture to decode: a waveform glyph on the
                // placeholder, and its uses are the samples that name it.
                AssetCard(
                    asset: AssetItem(id: "5", name: "clap.wav", path: "sb/clap.wav", kind: .audio, useCount: 3),
                    thumbnail: nil,
                    place: {},
                )
                .frame(width: 130)

                AssetCard(
                    asset: AssetItem(id: "6", name: "kick.ogg", path: "sb/kick.ogg", kind: .audio, useCount: 0, isMissing: true),
                    thumbnail: nil,
                    place: {},
                )
                .frame(width: 130)

                Spacer(minLength: 0)
            }
        }
    }

    // ─── Lyrics ──────────────────────────────────────────────────────────────

    private var lyrics: some View {
        Specimen(
            "LyricLineRow",
            note: "One transcribed line: a placed disc (accent once placed), the time in a pill, the text, and a place badge. An amber dot and text mark a line the transcription was unsure of; an overlong line says how long it ran.",
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                StateRow("pending") { lyric() }
                StateRow("placed") { lyric(isPlaced: true) }
                StateRow("unsure") { lyric(needsReview: true) }
                StateRow("overlong") { lyric(isOverlong: true, duration: 14_500) }
            }
        }
    }

    // ─── Inspector ───────────────────────────────────────────────────────────

    @ViewBuilder
    private var inspector: some View {
        Specimen(
            "TransformRow",
            note: "Fixed columns, as the inspector lays them out: stopwatch before the label, the field, then one slot for the key diamond — reserved even when empty, so no field shrinks when animation starts. The Start row has no stopwatch and still lines up. Key count and previous/next key are on the stopwatch's tooltip and the diamond's menu.",
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                StateRow("plain row") {
                    PropertyRow("Start") {
                        NumberField(value: .constant(15_811), unit: "ms", step: 10, range: 0...600_000)
                    }
                }
                StateRow("no keys") { transform(keyTimes: [], isAnimating: false) }
                StateRow("animating") { transform(keyTimes: [0, 1500, 3000], isAnimating: true) }
                StateRow("on a key") { transform(keyTimes: [0, 1500, 3000], isAnimating: true, localTime: 1_500) }
                StateRow("keys, off") { transform(keyTimes: [0, 3000], isAnimating: false) }
            }
            // The inspector's own grid, at the inspector's own width less its
            // padding: judged any wider, the field looks roomier than it is.
            .propertyGrid(leading: Theme.Size.keyframeGutter, trailing: Theme.Size.keyframeSlot)
        }

        Specimen(
            "FilterCard",
            note: "One filter on a clip, as a card: its tile in the filter colour, a switch, remove, and a body under a hairline that folds away. Switched off, the tile goes grey and the parameters dim. Click the heading to fold.",
        ) {
            HStack(alignment: .top, spacing: Theme.Spacing.section) {
                filterCard(isEnabled: true)
                    .frame(width: 300)
                filterCard(isEnabled: false)
                    .frame(width: 300)
            }
        }
    }

    // ─── Builders ────────────────────────────────────────────────────────────

    private static let columnWidth: CGFloat = 280

    private func track(
        name: String = "Particles",
        tint: Color = Theme.TrackPalette.violet,
        effects: Int = 3,
        isSelected: Bool = false,
        isVisible: Bool = true,
        isLocked: Bool = false,
    ) -> some View {
        TrackRow(
            name: name,
            tint: tint,
            effectCount: effects,
            isVisible: isVisible,
            isLocked: isLocked,
            isSelected: isSelected,
            select: {},
            toggleVisibility: {},
            toggleLock: {},
        )
    }

    private func placed(isSelected: Bool = false, isVisible: Bool = true) -> some View {
        PlacedEffectRow(
            name: "Fire Ring",
            tint: Theme.TrackPalette.violet,
            isVisible: isVisible,
            isSelected: isSelected,
            select: {},
            remove: {},
        )
    }

    private func effectHeader(
        name: String = "Emitter",
        systemImage: String = "sparkles",
        presetCount: Int?,
        isExpanded: Bool,
    ) -> some View {
        EffectHeaderRow(
            name: name,
            systemImage: systemImage,
            presetCount: presetCount,
            isExpanded: isExpanded,
            toggleExpanded: {},
            add: {},
            tint: presetCount == nil ? nil : Theme.TrackPalette.violet,
        )
    }

    private func filterRow(_ name: String, _ systemImage: String, canApply: Bool) -> some View {
        FilterLibraryRow(
            name: name,
            systemImage: systemImage,
            filterType: name.lowercased(),
            canApply: canApply,
            apply: {},
        )
    }

    private func lyric(
        isPlaced: Bool = false,
        needsReview: Bool = false,
        isOverlong: Bool = false,
        duration: Double = 2_400,
    ) -> some View {
        LyricLineRow(
            text: "I'm still in love with you",
            start: 83_240,
            duration: duration,
            isOverlong: isOverlong,
            needsReview: needsReview,
            isPlaced: isPlaced,
            seek: {},
            place: {},
        )
    }

    private func transform(keyTimes: [Double], isAnimating: Bool, localTime: Double = 750) -> some View {
        TransformRow(
            title: "Position X",
            unit: "px",
            step: 1,
            range: -1000...1000,
            keyTimes: keyTimes,
            isAnimating: isAnimating,
            current: 320,
            localTime: localTime,
            duration: 3_000,
            setValue: { _, _ in },
            beginAnimating: { _ in },
            setEnabled: { _, _ in },
            clear: { _ in },
            goToTime: { _ in },
        )
    }

    private func filterCard(isEnabled: Bool) -> some View {
        FilterCard(
            name: "Glow",
            systemImage: "sun.max",
            isEnabled: isEnabled,
            toggle: {},
            remove: {},
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                PropertyRow("Radius") {
                    NumberField(value: .constant(12), unit: "px", step: 1, range: 0...64)
                }
                PropertyRow("Intensity") {
                    NumberField(value: .constant(0.6), step: 0.05, range: 0...2, format: "%.2f")
                }
            }
            // Dimmed and inert when off, as the inspector does to a filter's
            // parameters: the card draws the chrome, the caller decides this.
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.5)
        }
    }

    /// A stand-in thumbnail: a flat plate with a bright disc, drawn once.
    private static let sampleImage: CGImage? = {
        guard let context = CGContext(
            data: nil,
            width: 160,
            height: 90,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else { return nil }

        // Flat, like a real sprite sheet's art would be on its own; the
        // gallery shows content, and invented gradients would be the decoration
        // the system no longer draws.
        context.setFillColor(CGColor(red: 0.36, green: 0.30, blue: 0.62, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 160, height: 90))
        context.setFillColor(CGColor(gray: 1, alpha: 0.9))
        context.fillEllipse(in: CGRect(x: 60, y: 20, width: 50, height: 50))
        return context.makeImage()
    }()
}

/// A labelled slot, so the same content can be shown in each of its states and
/// compared down a column.
struct StateRow<Content: View>: View {
    private let name: String
    private let content: Content

    init(_ name: String, @ViewBuilder content: () -> Content) {
        self.name = name
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.snug) {
            Text(name)
                .font(Theme.Typography.readout)
                .foregroundStyle(Theme.Palette.tertiary)
                .frame(width: 84, alignment: .leading)

            content
                // The inspector's content width: 264 less its padding.
                .frame(width: 240)
        }
    }
}
