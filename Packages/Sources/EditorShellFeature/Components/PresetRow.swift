import CoreGraphics
import DesignSystem
import SwiftUI

/// One preset available to place.
package struct PresetRow: View {
    private let name: String
    private let summary: String
    private let add: () -> Void
    /// The colour of the placeholder's glyph while there are no frames.
    private let tint: Color?
    /// The renderer's preview of the preset, when one has been made.
    private let frames: [CGImage]

    @State private var isHovered = false

    package init(
        name: String,
        summary: String,
        add: @escaping () -> Void,
        tint: Color? = nil,
        frames: [CGImage] = [],
    ) {
        self.name = name
        self.summary = summary
        self.add = add
        self.tint = tint
        self.frames = frames
    }

    package var body: some View {
        Button(action: add) {
            HStack(spacing: Theme.Spacing.compact) {
                thumbnail

                VStack(alignment: .leading, spacing: Theme.Spacing.hair) {
                    Text(name)
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Palette.primary)
                    // The summary is what makes a list of names browsable:
                    // "Snow" and "Rain" are obvious, "Magic" and "Starfield"
                    // are not.
                    Text(summary)
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: Theme.Spacing.tight)

                AddBadge(isHighlighted: isHovered)
            }
            .padding(Theme.Spacing.tight)
            .padding(.trailing, Theme.Spacing.tight)
            .rowSurface(isHovered: isHovered, radius: Theme.Radius.bar)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(Theme.Motion.quick, value: isHovered)
        .help("Add \(name) at the playhead")
    }

    /// A small moving picture of the preset, or a placeholder until one exists.
    ///
    /// The row's picture is the preset itself when the renderer has made one —
    /// playing only under the pointer, for the reason the library's cards give:
    /// a column of moving thumbnails is noise.
    private var thumbnail: some View {
        let shape = RoundedRectangle(
            cornerRadius: Theme.Radius.nested(in: Theme.Radius.bar, inset: Theme.Spacing.tight),
            style: .continuous,
        )

        return ZStack {
            if frames.isEmpty {
                ArtworkPlaceholder(systemImage: "sparkles", tint: tint)
            } else {
                Theme.Palette.stage
                FrameSequence(frames, isPlaying: isHovered)
            }
        }
        .frame(width: Theme.Size.controlLarge * 1.25, height: Theme.Size.controlLarge * 0.75)
        .clipShape(shape)
        .overlay { shape.strokeBorder(Theme.Border.card, lineWidth: Theme.Size.hairline) }
    }
}
