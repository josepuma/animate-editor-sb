import SwiftUI

public extension View {
    /// Lifts the view off its surface with a drop shadow.
    func elevated(_ shadow: Theme.Elevation.Shadow = Theme.Elevation.low) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, y: shadow.y)
    }
}

/// A clip on a timeline track: a rounded pill carrying a thumbnail, a label and
/// an optional trailing badge.
///
/// The gradient, bright inner edge and shadow are what make it read as a solid
/// object; a flat fill on a dark surface looks like a gap in the background.
public struct TrackBlock<Thumbnail: View, Badge: View>: View {
    private let tint: Color
    private let label: String?
    private let isDimmed: Bool
    private let cornerRadius: CGFloat
    private let thumbnail: Thumbnail
    private let badge: Badge

    public init(
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

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        HStack(spacing: Theme.Spacing.snug) {
            thumbnail
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: cornerRadius - Theme.Spacing.tight,
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
                lineWidth: 1,
            )
        }
        .clipShape(shape)
        .elevated(isDimmed ? Theme.Elevation.low : Theme.Elevation.medium)
    }
}

/// A small rounded glyph at the trailing edge of a block, as used for a clip's
/// type indicator.
public struct BlockBadge: View {
    private let systemImage: String

    public init(systemImage: String) {
        self.systemImage = systemImage
    }

    public var body: some View {
        Image(systemName: systemImage)
            .font(Theme.Typography.micro)
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: Theme.Size.controlTiny, height: Theme.Size.controlTiny)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .fill(.white.opacity(0.18))
            }
    }
}

/// The draggable head of a playhead, sitting above its line.
public struct PlayheadHandle: View {
    private let tint: Color

    public init(tint: Color = Theme.Palette.accent) {
        self.tint = tint
    }

    public var body: some View {
        Capsule()
            .fill(tint)
            .frame(width: 10, height: 14)
            .overlay {
                Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1)
            }
            .elevated(Theme.Elevation.medium)
    }
}
