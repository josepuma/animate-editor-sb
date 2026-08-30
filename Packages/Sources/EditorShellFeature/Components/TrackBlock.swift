import DesignSystem
import SwiftUI

/// A clip on a timeline track: a rounded pill carrying a thumbnail, a label and
/// an optional trailing badge.
///
/// The gradient, bright inner edge and shadow are what make it read as a solid
/// object; a flat fill on a dark surface looks like a gap in the background.
struct TrackBlock<Thumbnail: View, Badge: View>: View {
    private let tint: Color
    private let label: String?
    private let isDimmed: Bool
    private let cornerRadius: CGFloat
    private let thumbnail: Thumbnail
    private let badge: Badge

    init(
        tint: Color,
        label: String? = nil,
        isDimmed: Bool = false,
        cornerRadius: CGFloat = Theme.Radius.bar,
        @ViewBuilder thumbnail: () -> Thumbnail = { EmptyView() },
        @ViewBuilder badge: () -> Badge = { EmptyView() },
    ) {
        self.tint = tint
        self.label = label
        self.isDimmed = isDimmed
        self.cornerRadius = cornerRadius
        self.thumbnail = thumbnail()
        self.badge = badge()
    }

    var body: some View {
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
        .background {
            shape.fill(
                LinearGradient(
                    colors: [
                        tint.opacity(isDimmed ? 0.3 : 1),
                        tint.opacity(isDimmed ? 0.2 : 0.78),
                    ],
                    startPoint: .top,
                    endPoint: .bottom,
                ),
            )
        }
        .overlay {
            // A brighter top edge suggests a light source above, the same cue
            // that makes a physical button look raised.
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        .white.opacity(isDimmed ? 0.1 : 0.4),
                        .white.opacity(0.06),
                    ],
                    startPoint: .top,
                    endPoint: .bottom,
                ),
                lineWidth: Theme.Size.hairline,
            )
        }
        .clipShape(shape)
        .elevated(isDimmed ? Theme.Elevation.low : Theme.Elevation.medium)
    }
}

/// A small rounded glyph at the trailing edge of a block, as used for a clip's
/// type indicator.
struct BlockBadge: View {
    private let systemImage: String

    init(systemImage: String) {
        self.systemImage = systemImage
    }

    var body: some View {
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
