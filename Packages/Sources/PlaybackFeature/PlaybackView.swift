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

    @State private var isHovered = false

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
    public var canvas: some View {
        GeometryReader { proxy in
            let size = fittedSize(in: proxy.size)

            ZStack {
                MetalCanvasView(model: model, source: source)
                    .frame(width: size.width, height: size.height)
                    .clipShape(
                        RoundedRectangle(cornerRadius: Theme.Radius.stage, style: .continuous),
                    )
                    .elevated(Theme.Elevation.high)

                overlay(canvasSize: size)
                    .frame(width: size.width, height: size.height)
                    .clipShape(
                        RoundedRectangle(cornerRadius: Theme.Radius.stage, style: .continuous),
                    )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .onHover { isHovered = $0 }
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
                RenderStats(model: model)
                    .opacity(isHovered ? 1 : 0)
                    .animation(Theme.Motion.standard, value: isHovered)
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
        let aspect = CGFloat(OsuCanvas.width / OsuCanvas.height)
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
        .surface(.bar, radius: Theme.Radius.small)
    }
}
