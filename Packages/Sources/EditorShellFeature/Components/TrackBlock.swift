import DesignSystem
import SwiftUI

/// A clip on a timeline track: a rounded pill carrying a thumbnail, a label and
/// an optional trailing badge.
///
/// A flat fill with a hairline and a shadow: the shadow is what lifts it off
/// the lane, and the hairline is what keeps two neighbouring clips apart.
package struct TrackBlock<Thumbnail: View, Badge: View>: View {
    private let tint: Color
    private let label: String?
    private let isDimmed: Bool
    private let isSelected: Bool
    private let cornerRadius: CGFloat
    private let thumbnail: Thumbnail
    private let badge: Badge

    package init(
        tint: Color,
        label: String? = nil,
        isDimmed: Bool = false,
        isSelected: Bool = false,
        cornerRadius: CGFloat = Theme.Radius.bar,
        @ViewBuilder thumbnail: () -> Thumbnail = { EmptyView() },
        @ViewBuilder badge: () -> Badge = { EmptyView() },
    ) {
        self.tint = tint
        self.label = label
        self.isDimmed = isDimmed
        self.isSelected = isSelected
        self.cornerRadius = cornerRadius
        self.thumbnail = thumbnail()
        self.badge = badge()
    }

    package var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        HStack(spacing: Theme.Spacing.snug) {
            thumbnail
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: Theme.Radius.nested(
                            in: cornerRadius,
                            inset: Theme.Spacing.tight,
                        ),
                        style: .continuous,
                    ),
                )

            if let label {
                Text(label)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(.white.opacity(isDimmed ? 0.5 : 0.95))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            badge
        }
        .padding(Theme.Spacing.tight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Flat fill and a hairline. This used to be a gradient with a lit top
        // edge, "a light source above" — decoration, and the app draws none.
        .background { shape.fill(tint.opacity(isDimmed ? 0.3 : 0.9)) }
        .overlay {
            shape.strokeBorder(.white.opacity(isDimmed ? 0.06 : 0.14), lineWidth: Theme.Size.hairline)
        }
        .clipShape(shape)
        .overlay {
            // Selection reads as a solid ring rather than a change of fill: the
            // fill is the layer's colour and carries meaning of its own, so
            // tinting it to show selection would say two things at once. Drawn
            // after the clip so the full stroke width shows — inside it, half
            // of the line is cut away by the block's own edge.
            if isSelected {
                // The accent, like every chosen thing: white read as one more
                // highlight on the block's own bright top edge.
                shape.strokeBorder(Theme.Palette.selection, lineWidth: Theme.Size.hairline * 2)
            }
        }
        .elevated(isDimmed ? Theme.Elevation.low : Theme.Elevation.medium)
    }
}

/// A small rounded glyph at the trailing edge of a block, as used for a clip's
/// type indicator.
package struct BlockBadge: View {
    private let systemImage: String

    package init(systemImage: String) {
        self.systemImage = systemImage
    }

    package var body: some View {
        Image(systemName: systemImage)
            .font(Theme.Typography.micro)
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: Theme.Size.controlTiny, height: Theme.Size.controlTiny)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .fill(Theme.Fill.badge)
            }
    }
}
