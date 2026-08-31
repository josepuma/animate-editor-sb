import DesignSystem
import StoryboardRendering
import SwiftUI

/// Storyboard playback: a Metal canvas with its controls floating on top.
///
/// The controls live on the canvas rather than in a bar below, which leaves the
/// bottom of the window to the timeline. They fade in on hover so a still frame
/// reads as the storyboard alone.
public struct PlaybackView: View {
    @Bindable private var model: PlaybackModel
    @Bindable private var timeline: TimelineModel
    private let source: any StoryboardSource

    public init(
        model: PlaybackModel,
        timeline: TimelineModel,
        source: any StoryboardSource,
    ) {
        _model = Bindable(model)
        _timeline = Bindable(timeline)
        self.source = source
    }

    public var body: some View {
        canvas
            .padding(Theme.Spacing.snug)
            .background(Theme.Palette.stage)
    }

    /// The Metal canvas, letterboxed to osu!'s 16:9 ratio, with statistics in
    /// one corner and playback controls along the bottom.
    ///
    /// A view rather than a computed property, because it owns hover state.
    /// Handed out as `someView.canvas`, the state would belong to a
    /// `PlaybackView` that never enters the view tree — and `@State` on a view
    /// SwiftUI never installs has no identity, so writes to it go nowhere.
    public var canvas: PlaybackCanvas {
        PlaybackCanvas(model: model, timeline: timeline, source: source)
    }
}

/// The canvas and everything drawn over it.
public struct PlaybackCanvas: View {
    @Bindable var model: PlaybackModel
    @Bindable var timeline: TimelineModel
    let source: any StoryboardSource

    /// The pointer is over the picture.
    ///
    /// Reported by an AppKit tracking area laid over the canvas rather than by
    /// `onHover`: the Metal view handles its own mouse tracking and does not
    /// pass those events up, so SwiftUI never sees them.
    @State private var isHovered = false

    public var body: some View {
        GeometryReader { proxy in
            let size = fittedSize(in: proxy.size)

            ZStack {
                MetalCanvasView(model: model, source: source)
                    .frame(width: size.width, height: size.height)
                    .clipShape(
                        RoundedRectangle(cornerRadius: Theme.Radius.stage, style: .continuous),
                    )
                    // The stage reads as black on black, so without an edge
                    // there is no telling where the storyboard stops and the
                    // letterbox behind it starts — a sprite parked just off
                    // screen looks the same as one that is simply dark.
                    // Matches the panels around it, since the canvas is a
                    // surface among them.
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.stage, style: .continuous)
                            .strokeBorder(Theme.Border.panel, lineWidth: 1),
                    )
                    .elevated(Theme.Elevation.high)

                // Watches the whole picture, including the space the controls
                // sit in. Tracking the Metal view itself reports the pointer
                // leaving the moment it crosses onto a button, which would hide
                // the controls exactly when they are being reached for.
                HoverReporter { isHovered = $0 }
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)

                overlay(canvasSize: size)
                    .frame(width: size.width, height: size.height)
                    .clipShape(
                        RoundedRectangle(cornerRadius: Theme.Radius.stage, style: .continuous),
                    )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onChange(of: model.timing) { _, timing in
            timeline.setTiming(timing)
        }
    }

    /// Everything drawn over the canvas, inset so it never touches the edges.
    private func overlay(canvasSize: CGSize) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Spacer()
                RenderStats(model: model, isRevealed: isHovered)
            }

            Spacer()

            HStack(alignment: .bottom) {
                CanvasOverlayControls(model: model, isRevealed: isHovered)
                Spacer()
                if model.hasAudio, canvasSize.height > 260 {
                    CanvasVolumeControl(model: model, isRevealed: isHovered)
                }
            }
            // Extra room beneath the controls: sitting hard against the canvas
            // edge makes them look clipped rather than placed.
            .padding(.bottom, Theme.Spacing.snug)
        }
        .padding(Theme.Spacing.regular)
    }

    private func fittedSize(in available: CGSize) -> CGSize {
        let size = OsuCanvas.size(widescreen: model.isWidescreen)
        let aspect = CGFloat(size.width / size.height)
        let byWidth = CGSize(width: available.width, height: available.width / aspect)
        return byWidth.height <= available.height
            ? byWidth
            : CGSize(width: available.height * aspect, height: available.height)
    }
}

// ─── Render statistics ───────────────────────────────────────────────────────

/// Sprite counts and frame rate, for diagnosing performance rather than for
/// reading while working — so they appear only on hover.
private struct RenderStats: View {
    let model: PlaybackModel
    let isRevealed: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.snug) {
            if let warning = model.audioWarning {
                Image(systemName: "speaker.slash")
                    .foregroundStyle(Theme.Palette.warning)
                    .help(warning)
            }

            Text("\(model.drawnCount)/\(model.spriteCount)")
                .help("Sprites drawn this frame, of the storyboard's total")

            Text(String(format: "%.0f fps", model.framesPerSecond))
        }
        .font(Theme.Typography.micro)
        .foregroundStyle(Theme.Palette.tertiary)
        .padding(.horizontal, Theme.Spacing.snug)
        .padding(.vertical, Theme.Spacing.hair)
        .revealed(isRevealed, role: .bar, capsule: false, radius: Theme.Radius.small)
    }
}
