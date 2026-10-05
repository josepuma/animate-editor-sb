import SwiftUI

/// A picture with its name over a gradient at the foot — a preview in a grid.
///
/// The gradient is what keeps the name readable: artwork is arbitrary, and a
/// caption laid straight over a bright frame disappears. Dark at the foot and
/// clear above, so the picture stays visible where the eye goes first.
///
/// Chosen tiles are **outlined** in the accent, like every other chosen thing,
/// rather than dimmed or tinted — the picture is the content, and colouring it
/// to show selection would say two things at once.
public struct MediaTile<Artwork: View, Accessory: View>: View {
    private let title: String?
    private let isSelected: Bool
    private let aspectRatio: CGFloat
    private let artwork: Artwork
    private let accessory: Accessory
    private let action: () -> Void

    @State private var isHovered = false

    /// - Parameters:
    ///   - aspectRatio: width over height. 16:9 by default, the shape of the
    ///     stage a preview is a picture of.
    ///   - accessory: a small mark at the top trailing corner — a type glyph,
    ///     a cost badge.
    public init(
        title: String? = nil,
        isSelected: Bool = false,
        aspectRatio: CGFloat = 16.0 / 9.0,
        action: @escaping () -> Void = {},
        @ViewBuilder artwork: () -> Artwork,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() },
    ) {
        self.title = title
        self.isSelected = isSelected
        self.aspectRatio = aspectRatio
        self.action = action
        self.artwork = artwork()
        self.accessory = accessory()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.bar, style: .continuous)

        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                // The ratio shapes a neutral base and the artwork is laid into
                // it, so a picture cannot impose its own size on the tile.
                Color.clear

                if title != nil {
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0), location: 0.35),
                            .init(color: .black.opacity(0.75), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom,
                    )
                }

                if let title {
                    Text(title)
                        .font(Theme.Typography.label)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(Theme.Spacing.snug)
                }
            }
            .aspectRatio(aspectRatio, contentMode: .fit)
            .background { artwork.clipped() }
            .overlay(alignment: .topTrailing) {
                accessory.padding(Theme.Spacing.tight)
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(border, lineWidth: isSelected ? Theme.Size.ring * 1.5 : Theme.Size.hairline)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(Theme.Motion.quick, value: isHovered)
        .animation(Theme.Motion.quick, value: isSelected)
    }

    private var border: Color {
        if isSelected { return Theme.Palette.accent }
        return isHovered ? Theme.Border.cardHovered : Theme.Border.card
    }
}
