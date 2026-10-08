import DesignSystem
import StoryboardCore
import SwiftUI

/// Where a picker gets its pictures: read one, or ask for one to be made.
///
/// Two closures rather than the model, so the picker can be shown in the
/// gallery with pictures from anywhere — and so it never reaches into the
/// editor for anything else.
package struct SpriteThumbnails {
    package let image: (String) -> CGImage?
    package let request: (String) -> Void

    package init(image: @escaping (String) -> CGImage?, request: @escaping (String) -> Void) {
        self.image = image
        self.request = request
    }

    /// No pictures: every tile shows its placeholder.
    package static var none: SpriteThumbnails { SpriteThumbnails(image: { _ in nil }, request: { _ in }) }
}

/// What picking "Custom" puts in the path field.
///
/// A path rather than an empty string: empty *is* the adjustable dot, so a
/// cleared field would bounce the picker back to it. Named after the folder a
/// beatmap's own images live in, so it reads as the shape a path takes.
package let customSpritePlaceholder = "sb/your-image.png"

/// Chooses the image a particle draws: a field showing the current one, and a
/// popover with every built-in as a picture, grouped and searchable.
///
/// Replaces a flat menu of sixty names that had to be learned by heart — and
/// that was a hand-written copy of the built-ins which had already lost a
/// quarter of them. The entries come from `BuiltInSprite.catalogue`, so a
/// built-in that exists is a built-in that can be picked.
package struct SpritePicker: View {
    private let path: String
    private let thumbnails: SpriteThumbnails
    private let onPick: (String) -> Void

    @State private var isOpen = false

    package init(path: String, thumbnails: SpriteThumbnails, onPick: @escaping (String) -> Void) {
        self.path = path
        self.thumbnails = thumbnails
        self.onPick = onPick
    }

    /// What the field calls the current path.
    ///
    /// A path the catalogue does not know is "Custom" — a beatmap's own image
    /// — rather than a guess at the nearest built-in, which would claim the
    /// sprite is something it is not.
    package static func title(for path: String) -> String {
        if path.isEmpty { return "Adjustable Dot" }
        return BuiltInSprite.entry(for: path)?.title ?? "Custom"
    }

    package var body: some View {
        FieldWell {
            Button { isOpen.toggle() } label: {
                HStack(spacing: Theme.Spacing.tight) {
                    SpriteSwatch(path: path, thumbnails: thumbnails, side: Theme.Size.fieldThumbnail)
                    Text(Self.title(for: path))
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.secondary)
                        .lineLimit(1)
                    Spacer(minLength: Theme.Spacing.tight)
                    Image(systemName: "chevron.down")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isOpen, arrowEdge: .leading) {
                SpritePickerPanel(selection: path, thumbnails: thumbnails) { picked in
                    onPick(picked)
                    isOpen = false
                }
            }
        }
    }
}

/// The popover's contents: search, group chips and the grid.
///
/// Its own view, `package`, so the gallery can show it open without a click.
package struct SpritePickerPanel: View {
    private let selection: String
    private let thumbnails: SpriteThumbnails
    private let onPick: (String) -> Void

    @State private var search = ""
    @State private var group: BuiltInSprite.Group?

    package init(selection: String, thumbnails: SpriteThumbnails, onPick: @escaping (String) -> Void) {
        self.selection = selection
        self.thumbnails = thumbnails
        self.onPick = onPick
    }

    private var entries: [BuiltInSprite.Entry] {
        BuiltInSprite.entries(matching: search, in: group)
    }

    /// The two entries that are not pictures of a file: the dot built from
    /// numbers, and a beatmap's own image. Shown only while browsing
    /// everything — a search or a group is a question they do not answer.
    private var showsSpecial: Bool {
        search.trimmingCharacters(in: .whitespaces).isEmpty && group == nil
    }

    /// A path that is not a built-in: a beatmap's own image.
    private var isCustom: Bool {
        !selection.isEmpty && BuiltInSprite.entry(for: selection) == nil
    }

    private func grid<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: Theme.Size.pickerTile), spacing: Theme.Spacing.tight)],
            alignment: .leading,
            spacing: Theme.Spacing.compact,
            content: content,
        )
    }

    private func tiles(_ list: [BuiltInSprite.Entry]) -> some View {
        ForEach(list) { entry in
            SpritePickerTile(
                title: entry.title, isSelected: entry.path == selection,
                picture: { SpriteSwatch(path: entry.path, thumbnails: thumbnails, side: Theme.Size.pickerTile) },
            ) { onPick(entry.path) }
        }
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
            FieldWell {
                HStack(spacing: Theme.Spacing.tight) {
                    Image(systemName: "magnifyingglass")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.tertiary)
                    TextField("Search sprites", text: $search)
                        .textFieldStyle(.plain)
                        .font(Theme.Typography.micro)
                }
            }

            ScrollView(.horizontal) {
                HStack(spacing: Theme.Spacing.tight) {
                    FilterChip("All", isSelected: group == nil) { group = nil }
                    ForEach(BuiltInSprite.Group.displayOrder, id: \.self) { candidate in
                        FilterChip(candidate.rawValue, isSelected: group == candidate) {
                            group = group == candidate ? nil : candidate
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)

            ScrollView {
                if showsSpecial {
                    // Browsing everything: one headed section per group, so
                    // sixty pictures read as Fire, Light, HUD… rather than as
                    // one wall. A search or a chosen group is already a
                    // narrowed list and stays flat.
                    VStack(alignment: .leading, spacing: Theme.Spacing.regular) {
                        grid {
                            SpritePickerTile(
                                title: "Adjustable Dot", isSelected: selection.isEmpty,
                                picture: { GlyphPlaceholder(systemName: "circle.dotted") },
                            ) { onPick("") }
                            SpritePickerTile(
                                title: "Custom", isSelected: isCustom,
                                picture: { GlyphPlaceholder(systemName: "doc") },
                            ) {
                                // Keeps a path already typed; seeds a stand-in
                                // otherwise, so there is something in the field
                                // to replace.
                                onPick(isCustom ? selection : customSpritePlaceholder)
                            }
                        }
                        ForEach(BuiltInSprite.Group.displayOrder, id: \.self) { section in
                            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                                Text(section.rawValue.uppercased())
                                    .font(Theme.Typography.overline)
                                    .tracking(Theme.Typography.overlineTracking)
                                    .foregroundStyle(Theme.Palette.tertiary)
                                grid { tiles(BuiltInSprite.catalogue.filter { $0.group == section }) }
                            }
                        }
                    }
                    .padding(.vertical, Theme.Spacing.hair)
                } else {
                    grid { tiles(entries) }
                        .padding(.vertical, Theme.Spacing.hair)
                }
            }

            if entries.isEmpty {
                Text("No sprite matches “\(search)”")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.tertiary)
            }
        }
        .padding(Theme.Spacing.compact)
        .frame(width: Theme.Size.pickerWidth, height: Theme.Size.pickerHeight)
        .background(Theme.Tone.panel)
    }
}

/// One choice in the grid: a picture and its name.
///
/// The chosen one is outlined in the accent, never filled — a fill says
/// "pressed", an outline says "this one", and the picture keeps its own tone.
private struct SpritePickerTile<Picture: View>: View {
    let title: String
    let isSelected: Bool
    @ViewBuilder let picture: () -> Picture
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.hair) {
                picture()
                    .frame(width: Theme.Size.pickerTile, height: Theme.Size.pickerTile)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                            .fill(isHovered ? Theme.Fill.hover : Color.clear),
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                            .strokeBorder(isSelected ? Theme.Palette.selection : .clear, lineWidth: Theme.Size.ring)
                    }
                Text(title)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(isSelected ? Theme.Palette.primary : Theme.Palette.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: Theme.Size.pickerTile)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(title)
        .onHover { isHovered = $0 }
        .animation(Theme.Motion.quick, value: isHovered)
    }
}

/// A built-in's picture on the dark well it was drawn for.
///
/// Every built-in is white with its shape in alpha — the colour comes from
/// the effect — so it needs a dark plate to be seen at all. Asks for its
/// picture as it appears, so a grid of sixty decodes only what scrolls in.
private struct SpriteSwatch: View {
    let path: String
    let thumbnails: SpriteThumbnails
    let side: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .fill(Theme.Tone.well)
            if let image = thumbnails.image(path) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(side * 0.1)
            } else if path.isEmpty {
                Image(systemName: "circle.dotted")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.tertiary)
            } else if BuiltInSprite.entry(for: path) == nil {
                Image(systemName: "doc")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.tertiary)
            }
        }
        .frame(width: side, height: side)
        .onAppear {
            // Only the catalogue's own images have a picture to make.
            if BuiltInSprite.entry(for: path) != nil { thumbnails.request(path) }
        }
    }
}

/// The picture for an entry that has no file: a glyph on the well.
private struct GlyphPlaceholder: View {
    let systemName: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .fill(Theme.Tone.well)
            Image(systemName: systemName)
                .font(Theme.Typography.controlIcon)
                .foregroundStyle(Theme.Palette.secondary)
        }
    }
}
