import DesignSystem
import SwiftUI

/// The home screen's poster: one project, its storyboard playing behind its
/// name, the way a streaming service opens on the thing it wants you to watch.
///
/// Presentational: it is handed the words, the artwork and a view to play —
/// what that view is (a live storyboard) is the app's business, which is what
/// keeps this feature from knowing a renderer exists.
package struct FeaturedHero<Trailer: View>: View {
    private let title: String
    private let artist: String
    private let detail: String?
    private let artworkURL: URL?
    private let isMuted: Bool
    private let isOpening: Bool
    private let open: () -> Void
    private let toggleMute: () -> Void
    /// How much of the hero's foot the page lays content over, so the words
    /// sit above it rather than under the first row of projects.
    private let bottomInset: CGFloat
    private let trailer: Trailer

    package init(
        title: String,
        artist: String,
        detail: String?,
        artworkURL: URL?,
        isMuted: Bool,
        isOpening: Bool,
        open: @escaping () -> Void,
        toggleMute: @escaping () -> Void,
        bottomInset: CGFloat = 0,
        @ViewBuilder trailer: () -> Trailer,
    ) {
        self.title = title
        self.artist = artist
        self.detail = detail
        self.artworkURL = artworkURL
        self.isMuted = isMuted
        self.isOpening = isOpening
        self.open = open
        self.toggleMute = toggleMute
        self.bottomInset = bottomInset
        self.trailer = trailer()
    }

    package var body: some View {
        ZStack(alignment: .bottomLeading) {
            // The size comes from the frame the page gives, never from the
            // picture: an image as a child of the stack would size the hero by
            // its own pixels.
            Color.clear
                .overlay {
                    // The cover art first, so the hero is the map's poster from
                    // the first frame — a project with scripts takes a moment to
                    // evaluate, and a black slab while it does reads as broken.
                    PosterArtwork(url: artworkURL)
                }
                .overlay {
                    // At the stage's own shape, filled and cropped: the hero is
                    // wider than 16:9, and fitted it would sit in black bars.
                    trailer
                        .aspectRatio(16 / 9, contentMode: .fill)
                }
                .clipped()

            // Black under the words, from the side they sit on, so they read
            // over whatever frame is playing; the rest of the picture is left
            // alone.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.8), location: 0),
                    .init(color: .black.opacity(0.4), location: 0.35),
                    .init(color: .black.opacity(0), location: 0.65),
                ],
                startPoint: .leading,
                endPoint: .trailing,
            )
            .allowsHitTesting(false)

            // The foot dissolves into the page's own tone, so the projects
            // below start on the poster instead of under a hard edge — the one
            // named exception to "no gradients": it is where the hero ends,
            // asked for by the design, not light added for its own sake.
            LinearGradient(
                stops: [
                    .init(color: Theme.Tone.base.opacity(0), location: 0.45),
                    .init(color: Theme.Tone.base.opacity(0.75), location: 0.8),
                    .init(color: Theme.Tone.base, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom,
            )
            .allowsHitTesting(false)

            info
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.bottom, bottomInset + Theme.Spacing.section)
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
            if !artist.isEmpty {
                Text(artist.uppercased())
                    .font(Theme.Typography.overline)
                    .tracking(Theme.Typography.overlineTracking)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Text(title)
                .font(Theme.Typography.display)
                .foregroundStyle(.white)
                .lineLimit(2)

            if let detail {
                Text(detail)
                    .font(Theme.Typography.body)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }

            HStack(spacing: Theme.Spacing.compact) {
                // The spinner takes the icon's slot rather than sitting beside
                // it, so the label does not shift while the folder is checked.
                Button(action: open) {
                    Label {
                        Text("Open Project")
                    } icon: {
                        ZStack {
                            Image(systemName: "play.fill")
                                .opacity(isOpening ? 0 : 1)
                            if isOpening {
                                ProgressView().controlSize(.mini)
                            }
                        }
                    }
                }
                .buttonStyle(.themed(.primary, size: .large, capsule: true))
                .disabled(isOpening)

                IconButton(
                    systemImage: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    size: Theme.Size.controlLarge,
                    prominence: .surfaced,
                    help: isMuted ? "Play the trailer's sound" : "Mute the trailer",
                    // Round beside the capsule, the way a player's sound
                    // control sits next to its play button.
                    isCircular: true,
                    action: toggleMute,
                )
            }
            .padding(.top, Theme.Spacing.snug)
        }
        .frame(maxWidth: Theme.Size.heroText, alignment: .leading)
    }
}
