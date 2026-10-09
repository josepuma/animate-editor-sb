import DesignSystem
import SwiftUI

/// One project on the home screen's shelf: its art in the stage's own shape,
/// the words beneath it rather than over it — the way a streaming home lists
/// what to watch next.
///
/// Below rather than over: a caption on the picture needs a scrim to be read,
/// and a row of scrims is a row of dark smudges across the art. Under it, the
/// art is left whole and the text is always legible.
package struct ShelfCard<Artwork: View>: View {
    private let title: String
    private let subtitle: String?
    private let isBusy: Bool
    private let isFeatured: Bool
    private let artwork: Artwork
    private let action: () -> Void

    @State private var isHovered = false

    /// - Parameter isFeatured: the project playing in the hero above, outlined
    ///   so the shelf says which of its cards that is.
    package init(
        title: String,
        subtitle: String?,
        isBusy: Bool = false,
        isFeatured: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder artwork: () -> Artwork,
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isBusy = isBusy
        self.isFeatured = isFeatured
        self.action = action
        self.artwork = artwork()
    }

    package var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
                thumbnail

                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    Text(title)
                        .font(Theme.Typography.shelfTitle)
                        .foregroundStyle(Theme.Palette.primary)
                        .lineLimit(1)

                    if let subtitle {
                        Text(subtitle)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.tertiary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, Theme.Spacing.hair)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        // The edge lights and the card holds still — a scale resamples the art
        // and leaves the click target where it was, the rule every card here
        // follows.
        .animation(Theme.Motion.quick, value: isHovered)
        .animation(Theme.Motion.quick, value: isBusy)
        .onHover { isHovered = $0 }
    }

    private var thumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.bar, style: .continuous)

        // A neutral base the ratio shapes, with the art laid behind it, so the
        // picture cannot size the card by its own pixels.
        return Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .background { artwork.clipped() }
            .overlay {
                if isBusy {
                    // Over a scrim: a spinner on a bright frame is invisible.
                    ZStack {
                        Color.black.opacity(0.55)
                        ProgressView().controlSize(.large).tint(.white)
                    }
                    .transition(.opacity)
                }
            }
            .clipShape(shape)
            .overlay {
                // Featured is outlined in the accent, never filled — what is chosen
                // keeps its own picture. Hover only lightens the hairline.
                shape.strokeBorder(
                    isFeatured ? Theme.Palette.selection
                        : isHovered ? Theme.Border.cardHovered : Theme.Border.card,
                    lineWidth: isFeatured ? Theme.Size.ring : Theme.Size.hairline,
                )
            }
            .elevated(isHovered ? Theme.Elevation.high : Theme.Elevation.medium)
    }
}
