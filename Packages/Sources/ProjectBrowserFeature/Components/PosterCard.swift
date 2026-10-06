import DesignSystem
import SwiftUI

/// A large artwork tile with its title over a gradient, as a streaming app
/// presents a show.
///
/// The gradient is what makes the text readable: artwork is arbitrary, and a
/// caption laid straight over it disappears against a bright frame.
package struct PosterCard<Artwork: View, Footer: View>: View {
    private let title: String
    private let subtitle: String?
    private let aspectRatio: CGFloat
    private let isBusy: Bool
    private let artwork: Artwork
    private let footer: Footer
    private let action: () -> Void

    @State private var isHovered = false

    /// - Parameters:
    ///   - aspectRatio: width over height. Match the source artwork: a poster
    ///     shape crops a wide image down to its middle.
    ///   - isBusy: shows a spinner over the artwork and stops responding to
    ///     taps. Work that takes a moment has to say so, or the card reads as
    ///     a click that did nothing.
    package init(
        title: String,
        subtitle: String? = nil,
        aspectRatio: CGFloat =  9.0 / 16.0,
        isBusy: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder artwork: () -> Artwork,
        @ViewBuilder footer: () -> Footer = { EmptyView() },
    ) {
        self.title = title
        self.subtitle = subtitle
        self.aspectRatio = aspectRatio
        self.isBusy = isBusy
        self.action = action
        self.artwork = artwork()
        self.footer = footer()
    }

    package var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
                poster
                footer
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        // Hover lights the edge; the card does not grow. A scale resamples
        // the artwork off the pixel grid and leaves the clickable area where
        // it was rather than where the card is drawn — the rule `IconButton`
        // already follows.
        .animation(Theme.Motion.quick, value: isHovered)
        .animation(Theme.Motion.quick, value: isBusy)
        .onHover { isHovered = $0 }
    }

    private var poster: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)

        return ZStack(alignment: .bottomLeading) {
            // A neutral base the ratio is applied to, with the artwork behind
            // it. As a child of the stack the image brings its own size, and
            // the ratio then shapes whatever that turned out to be — so a card
            // ends up sized by its picture rather than the picture by its card.
            Color.clear

            // Dark at the foot, clear at the head, so the artwork stays visible
            // while the caption keeps its contrast.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0), location: 0),
                    .init(color: .black.opacity(0.35), location: 0.55),
                    .init(color: .black.opacity(0.85), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom,
            )

            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text(title)
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.micro)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
            }
            .padding(Theme.Spacing.compact)
            .frame(maxWidth: .infinity, alignment: .leading)

            if isBusy {
                // Over a scrim rather than over the artwork: a spinner on a
                // bright frame is as invisible as white text would be.
                ZStack {
                    Color.black.opacity(0.55)
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                }
                .transition(.opacity)
            }
        }
        // Shape first, then fill it: the ratio settles the card's size against
        // a neutral base, and the artwork is laid into whatever that turned out
        // to be. `background` rather than a stack child, so an image cannot
        // impose its own dimensions on the card holding it.
        .aspectRatio(aspectRatio, contentMode: .fit)
        .background {
            artwork
                .clipped()
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(
                isHovered ? Theme.Border.cardHovered : Theme.Border.card,
                lineWidth: Theme.Size.hairline,
            )
        }
        .elevated(isHovered ? Theme.Elevation.high : Theme.Elevation.medium)
    }
}

// ─── Artwork ─────────────────────────────────────────────────────────────────

/// Loads a card's image from disk, showing a tinted placeholder until it
/// arrives and in place of one that will not load.
package struct PosterArtwork: View {
    private let url: URL?
    private let fallbackSymbol: String

    package init(url: URL?, fallbackSymbol: String = "music.note") {
        self.url = url
        self.fallbackSymbol = fallbackSymbol
    }

    package var body: some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ArtworkPlaceholder(systemImage: fallbackSymbol)
    }
}
