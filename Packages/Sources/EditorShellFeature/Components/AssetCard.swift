import DesignSystem
import SwiftUI

/// One asset, shown as its own picture.
///
/// A panel that lists filenames makes you place a file to find out what it is.
/// The thumbnail answers that at a glance, which is the whole reason an assets
/// panel exists rather than a folder in Finder.
///
/// Built as a tile — the picture to the edges, the name over a gradient at the
/// foot — like the library's previews. It used to be a picture in a box with
/// three lines of small text under it, which read as a form field rather than
/// as an image, and sat beside the preview cards like a different app.
///
/// The tile recipe rather than `MediaTile` itself: an asset is **dragged** onto
/// a track and **double-clicked** to place, and the tile's `Button` would take
/// the press before either gesture saw it.
package struct AssetCard: View {
    private let asset: AssetItem
    private let thumbnail: CGImage?
    /// Places the asset on the timeline at the playhead.
    private let place: () -> Void

    @State private var isHovered = false

    package init(asset: AssetItem, thumbnail: CGImage?, place: @escaping () -> Void) {
        self.asset = asset
        self.thumbnail = thumbnail
        self.place = place
    }

    /// One shape for every tile, whatever the image's own aspect: a grid where
    /// every cell is a different height is a grid nobody can scan down, and
    /// scanning is what this panel is for. 4:3 rather than the stage's 16:9,
    /// because most of a storyboard's assets are sprites, not backgrounds.
    private static let aspectRatio: CGFloat = 4.0 / 3.0

    package var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.bar, style: .continuous)

        ZStack(alignment: .bottomLeading) {
            Color.clear

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0), location: 0.4),
                    .init(color: .black.opacity(0.8), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom,
            )

            caption
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
        .background { picture }
        .clipShape(shape)
        .overlay { shape.strokeBorder(border, lineWidth: borderWidth) }
        .contentShape(shape)
        .onHover { isHovered = $0 }
        .animation(Theme.Motion.quick, value: isHovered)
        // Dragged onto a track, or double-clicked to drop at the playhead —
        // the two ways an asset gets into a timeline in any editor.
        .draggable(AssetTransfer(path: asset.path).payload) {
            Label(asset.name, systemImage: "photo")
                .font(Theme.Typography.label)
                .padding(Theme.Spacing.snug)
                .background(.thinMaterial, in: Capsule())
        }
        .onTapGesture(count: 2, perform: place)
        .help("\(asset.path)\nDrag onto a track, or double-click to add at the playhead")
    }

    /// The image itself, or a placeholder saying why there is none.
    @ViewBuilder
    private var picture: some View {
        if let thumbnail {
            ZStack {
                // Behind a transparent PNG, so its empty parts read as the
                // tile rather than as a hole through it.
                Theme.Tone.well

                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    // Filled to the edges, like every other tile. An image
                    // fitted inside the tile left a second frame within the
                    // first; filled, the tile *is* the picture. The cost is
                    // named: a very long sprite — a bar, a line of text — shows
                    // its middle, and the name underneath says what it is.
                    .scaledToFill()
            }
        } else if asset.isMissing {
            ArtworkPlaceholder(systemImage: "exclamationmark.triangle", tint: Theme.Palette.warning)
        } else {
            ArtworkPlaceholder(systemImage: "photo")
        }
    }

    /// The name, and under it the folder — *where* a file lives is part of what
    /// it is here: osu! reads the root for the map's own art and `sb/` for the
    /// storyboard's, so a background in the wrong one is broken in a way nothing
    /// else shows until export.
    private var caption: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(asset.name)
                .font(Theme.Typography.label)
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)

            // Folder and usage as one quiet line of text. They were pills in
            // the corner for a while — a bright badge on every tile shouts
            // over the pictures it sits on, which is the opposite of what a
            // count is for.
            HStack(spacing: Theme.Spacing.hair) {
                Text(asset.folder)
                    .lineLimit(1)
                    .truncationMode(.head)
                Text("·")
                Text(usage)
                    .foregroundStyle(asset.isMissing ? Theme.Palette.warning : .white.opacity(0.6))
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            .font(Theme.Typography.micro)
            .foregroundStyle(.white.opacity(0.6))
        }
        .padding(Theme.Spacing.snug)
    }

    /// The problem if there is one, else how often the asset is used.
    private var usage: String {
        if asset.isMissing { return "Missing" }
        return asset.useCount == 1 ? "1 use" : "\(asset.useCount) uses"
    }

    /// A missing file outlines itself in amber, so a grid of thumbnails shows
    /// the broken one without anyone reading the captions.
    private var border: Color {
        if asset.isMissing { return Theme.Palette.warning }
        return isHovered ? Theme.Border.cardHovered : Theme.Border.card
    }

    private var borderWidth: CGFloat {
        asset.isMissing ? Theme.Size.ring : Theme.Size.hairline
    }
}
