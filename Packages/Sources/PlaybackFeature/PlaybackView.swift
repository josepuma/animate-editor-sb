import DesignSystem
import StoryboardCore
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

    /// What a drag on the selection box should do, if anything.
    ///
    /// Supplied from outside because moving a clip is an edit to a document
    /// this feature knows nothing about — the same seam the canvas already sits
    /// on. Absent, the box is not drawn at all.
    private let onClipDrag: ((ClipDrag) -> Void)?

    /// Clicking the stage away from the selection clears it.
    private let onDeselect: (() -> Void)?

    /// Whether the framed clip refuses edits.
    private let isClipLocked: Bool

    /// The motion path being edited, asked for rather than passed: read as a
    /// property in the window's body it would rebuild the window on every edit.
    private let editablePath: (() -> MotionPath?)?
    private let isDrawingPath: (() -> Bool)?
    private let onPathChange: ((MotionPath) -> Void)?

    public init(
        model: PlaybackModel,
        timeline: TimelineModel,
        source: any StoryboardSource,
        isClipLocked: Bool = false,
        onClipDrag: ((ClipDrag) -> Void)? = nil,
        onDeselect: (() -> Void)? = nil,
        editablePath: (() -> MotionPath?)? = nil,
        isDrawingPath: (() -> Bool)? = nil,
        onPathChange: ((MotionPath) -> Void)? = nil,
    ) {
        _model = Bindable(model)
        _timeline = Bindable(timeline)
        self.source = source
        self.isClipLocked = isClipLocked
        self.onClipDrag = onClipDrag
        self.onDeselect = onDeselect
        self.editablePath = editablePath
        self.isDrawingPath = isDrawingPath
        self.onPathChange = onPathChange
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
        PlaybackCanvas(
            model: model,
            timeline: timeline,
            source: source,
            isClipLocked: isClipLocked,
            onClipDrag: onClipDrag,
            onDeselect: onDeselect,
            editablePath: editablePath,
            isDrawingPath: isDrawingPath,
            onPathChange: onPathChange,
        )
    }
}

/// The canvas and everything drawn over it.
public struct PlaybackCanvas: View {
    /// Which stage lines the dragged clip is currently caught on.
    ///
    /// Held here rather than in `SelectionBox` because the guides are drawn
    /// beside the box, not inside it: they run the whole stage while the box is
    /// only as large as its clip.
    @State private var snappedX: Double?
    @State private var snappedY: Double?

    @Bindable var model: PlaybackModel
    @Bindable var timeline: TimelineModel
    let source: any StoryboardSource
    var isClipLocked = false
    var onClipDrag: ((ClipDrag) -> Void)?
    var onDeselect: (() -> Void)?
    /// The path being edited, or nil when there is nothing to edit.
    var editablePath: (() -> MotionPath?)?
    var isDrawingPath: (() -> Bool)?
    var onPathChange: ((MotionPath) -> Void)?

    public var body: some View {
        GeometryReader { proxy in
            // The stage is fitted into what is left after the bar takes its
            // share, so the two are stacked rather than one laid over the
            // other: a control floating on the canvas covers picture, and the
            // canvas is now the surface being edited.
            let available = CGSize(
                width: proxy.size.width,
                height: proxy.size.height - Self.barHeight,
            )
            let size = fittedSize(in: available)

            VStack(spacing: 0) {
            ZStack {
                // Clicking the picture away from a selection clears it, the
                // way clicking empty space does in any editor. Beneath the
                // selection box, so the frame's own gestures win where they
                // overlap — the box is what the pointer was aiming at there.
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

                // Clicking the picture away from a selection clears it, the
                // way clicking empty space does in any editor.
                //
                // Above the Metal view, which would otherwise swallow the
                // click, and below the selection box, so the frame's own
                // gestures win where they overlap — there the box is what the
                // pointer was aiming at.
                if let onDeselect {
                    Color.clear
                        .frame(width: size.width, height: size.height)
                        .contentShape(.rect)
                        .onTapGesture(perform: onDeselect)
                }

                if let onClipDrag {
                    let stage = OsuCanvas.size(widescreen: model.isWidescreen)
                    SelectionBox(
                        bounds: model.selectionBounds,
                        stageSize: (Double(stage.width), Double(stage.height)),
                        viewSize: size,
                        isLocked: isClipLocked,
                        onDrag: onClipDrag,
                        onSnap: { snapX, snapY in
                            snappedX = snapX
                            snappedY = snapY
                        },
                    )
                    .frame(width: size.width, height: size.height)
                    // One identity for the life of the canvas.
                    //
                    // Behind an `if let` on the measurement, SwiftUI tore the
                    // box down and built a new one every time the bounds
                    // changed — losing the gesture's local offset with it, and
                    // briefly showing the outgoing view beside the incoming
                    // one. Two borders, flickering. The box decides for itself
                    // when it has nothing to draw.
                    .id("selection-box")
                }

                // Outside the drag branch, because a standing centre line has to
                // be visible with nothing selected — which is exactly when
                // someone is deciding where to put something.
                //
                // Above the frame: a guide the box covers cannot say what the
                // clip landed on.
                if model.showsGuides || snappedX != nil || snappedY != nil {
                    let stage = OsuCanvas.size(widescreen: model.isWidescreen)
                    SnapGuides(
                        x: snappedX,
                        y: snappedY,
                        showsCentre: model.showsGuides,
                        stageSize: (Double(stage.width), Double(stage.height)),
                        viewSize: size,
                    )
                    .frame(width: size.width, height: size.height)
                }

                // The pen tool, above the frame so its points win where they
                // overlap — there the point is what the pointer was aiming at.
                //
                // Asked for on demand rather than passed in, for the same
                // reason `isClipLocked` is: read as a property in the window's
                // body, every edit to the path would rebuild the whole window.
                if let editablePath, let onPathChange {
                    let stage = OsuCanvas.size(widescreen: model.isWidescreen)
                    PathEditor(
                        path: Binding(
                            get: { editablePath() ?? MotionPath() },
                            set: { onPathChange($0) },
                        ),
                        stageSize: (Double(stage.width), Double(stage.height)),
                        viewSize: size,
                        isDrawing: isDrawingPath?() ?? false,
                    )
                    .frame(width: size.width, height: size.height)
                    .id("path-editor")
                }



            }
            .frame(width: available.width, height: available.height)

            controlBar(canvasSize: size)
                .frame(height: Self.barHeight)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onChange(of: model.timing) { _, timing in
            timeline.setTiming(timing)
        }
    }

    /// Everything drawn over the canvas, inset so it never touches the edges.
    /// The controls, in the band between the stage and the timeline.
    ///
    /// Under the canvas rather than floating on it. Hovering to summon a
    /// control means it is absent until you go looking, and it puts buttons on
    /// top of the one surface that is now editable — the selection frame and a
    /// transport pill were competing for the same pixels and the same clicks.
    /// The gap below the stage was already there; this fills it.
    private func controlBar(canvasSize: CGSize) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.compact) {
            CanvasOverlayControls(model: model)

            Spacer(minLength: Theme.Spacing.regular)

            RenderStats(model: model)

            if model.hasAudio {
                CanvasVolumeControl(model: model)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Spacing.regular)
        // Nothing animates its arrival. The bar takes its share of the layout,
        // so SwiftUI animated it into place on load and the controls slid up
        // from the bottom of the window every time a project opened. Appearing
        // is not a transition: there is no earlier state to come from.
        .transaction { $0.animation = nil }
    }

    /// The band the controls occupy beneath the stage.
    /// The pills plus the breathing room the rest of the layout uses.
    private static let barHeight: CGFloat = Theme.Size.pill + Theme.Spacing.regular * 2

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
        .padding(.horizontal, Theme.Spacing.regular)
        // The same height as everything beside it: a row of pills where one is
        // shorter reads as uneven, whatever its own proportions are.
        .frame(height: Theme.Size.pill)
        .capsuleSurface(.bar)
    }
}
