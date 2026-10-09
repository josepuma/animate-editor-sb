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
    private let onPick: ((String?, Bool) -> Void)?

    /// Whether the framed clip refuses edits.
    /// Whether the selected clip refuses to be moved, asked for at draw time.
    ///
    /// A callback rather than a value, like every other seam into the shell in
    /// this file: reading it in a `body` up the tree rebuilds the window on
    /// every playhead tick. It used to be passed as a literal `false`, so the
    /// locked frame this drives was implemented and never once shown.
    private let isClipLocked: () -> Bool
    /// Where the selected clip sits, asked for at draw time.
    ///
    /// A callback rather than a value, like every other seam into the shell in
    /// this file: reading it in a `body` up the tree rebuilds the window on
    /// every playhead tick.
    private let clipOrigin: (() -> (x: Double, y: Double)?)?

    /// The motion path being edited, asked for rather than passed: read as a
    /// property in the window's body it would rebuild the window on every edit.
    private let editablePath: (() -> MotionPath?)?
    private let isDrawingPath: (() -> Bool)?
    private let onPathChange: ((MotionPath) -> Void)?

    /// The storyboard camera while it is being edited, `nil` otherwise — asked
    /// for on demand for the reason every seam here is.
    private let editableCamera: (() -> StoryboardCamera?)?
    private let onCameraFrame: ((Double, Double, Double, Double) -> Void)?
    private let onCameraPathPoint: ((Double, Double, Double) -> Void)?
    private let cameraView: CameraViewSwitch?

    public init(
        model: PlaybackModel,
        timeline: TimelineModel,
        source: any StoryboardSource,
        isClipLocked: @escaping () -> Bool = { false },
        clipOrigin: (() -> (x: Double, y: Double)?)? = nil,
        onClipDrag: ((ClipDrag) -> Void)? = nil,
        onPick: ((String?, Bool) -> Void)? = nil,
        editablePath: (() -> MotionPath?)? = nil,
        isDrawingPath: (() -> Bool)? = nil,
        onPathChange: ((MotionPath) -> Void)? = nil,
        editableCamera: (() -> StoryboardCamera?)? = nil,
        onCameraFrame: ((Double, Double, Double, Double) -> Void)? = nil,
        onCameraPathPoint: ((Double, Double, Double) -> Void)? = nil,
        cameraView: CameraViewSwitch? = nil,
    ) {
        _model = Bindable(model)
        _timeline = Bindable(timeline)
        self.source = source
        self.isClipLocked = isClipLocked
        self.clipOrigin = clipOrigin
        self.onClipDrag = onClipDrag
        self.onPick = onPick
        self.editablePath = editablePath
        self.isDrawingPath = isDrawingPath
        self.onPathChange = onPathChange
        self.editableCamera = editableCamera
        self.onCameraFrame = onCameraFrame
        self.onCameraPathPoint = onCameraPathPoint
        self.cameraView = cameraView
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
            clipOrigin: clipOrigin,
            onClipDrag: onClipDrag,
            onPick: onPick,
            editablePath: editablePath,
            isDrawingPath: isDrawingPath,
            onPathChange: onPathChange,
            editableCamera: editableCamera,
            onCameraFrame: onCameraFrame,
            onCameraPathPoint: onCameraPathPoint,
            cameraView: cameraView,
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
    var isClipLocked: () -> Bool = { false }
    /// Where the selected clip sits, asked for at draw time rather than read
    /// here — the same seam every other shell callback in this file uses.
    var clipOrigin: (() -> (x: Double, y: Double)?)?
    var onClipDrag: ((ClipDrag) -> Void)?
    /// A click on the canvas: the clip it landed on (or `nil` for none) and
    /// whether ⌘ or ⇧ was held to add it to the selection.
    var onPick: ((String?, Bool) -> Void)?
    /// The path being edited, or nil when there is nothing to edit.
    var editablePath: (() -> MotionPath?)?
    var isDrawingPath: (() -> Bool)?
    var onPathChange: ((MotionPath) -> Void)?
    var editableCamera: (() -> StoryboardCamera?)?
    var onCameraFrame: ((Double, Double, Double, Double) -> Void)?
    var onCameraPathPoint: ((Double, Double, Double) -> Void)?
    var cameraView: CameraViewSwitch?

    /// Turns a point on the canvas into stage units — the inverse of how the
    /// selection frame places a box.
    ///
    /// The offset is the renderer's (`offset(widescreen:)`), not the constant:
    /// the hit test asks the renderer, and on a 4:3 map the renderer puts no
    /// margin before the stage.
    private func stageCoordinates(viewSize: CGSize) -> (CGPoint) -> (x: Double, y: Double) {
        let stage = OsuCanvas.size(widescreen: model.isWidescreen)
        let scale = Double(viewSize.width) / Double(stage.width)
        let offset = Double(OsuCanvas.offset(widescreen: model.isWidescreen))
        return { point in
            (x: Double(point.x) / scale - offset, y: Double(point.y) / scale)
        }
    }

    /// The same, for a point measured in the whole canvas view rather than on
    /// the stage — where the picking layer sits, so a sprite off the stage can
    /// be picked as well.
    private func containerCoordinates(stageRect: CGRect) -> (CGPoint) -> (x: Double, y: Double) {
        let onStage = stageCoordinates(viewSize: stageRect.size)
        return { point in
            onStage(CGPoint(x: point.x - stageRect.minX, y: point.y - stageRect.minY))
        }
    }

    /// Outlines whichever clip is under the pointer, or none once it leaves.
    private func hover(at point: CGPoint?, toStage: (CGPoint) -> (x: Double, y: Double)) {
        model.hoveredClipID = point.flatMap { model.clip(at: toStage($0)) }
    }

    /// A click: the clip under it, with ⌘ or ⇧ adding it to the selection.
    private func pick(at point: CGPoint, toStage: (CGPoint) -> (x: Double, y: Double)) {
        guard let onPick else { return }
        let flags = NSEvent.modifierFlags
        onPick(
            model.clip(at: toStage(point)),
            flags.contains(.command) || flags.contains(.shift),
        )
    }

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
            // The stage sits wherever the zoom and pan put it inside the
            // space the canvas has; at the fitted view that is the old fitted
            // rectangle, centred. Every overlay is laid over the stage rect
            // with its own geometry unchanged — the frame, guides, pen and
            // camera tools all measure against the stage, not the window.
            let layout = model.canvasViewport.layout(container: available, stage: model.canvasStageSize)
            let stageRect = layout.stageRect
            let size = stageRect.size

            VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                // The whole space, not just the stage: zoomed out, what sits off
                // the stage is drawn around it.
                MetalCanvasView(model: model, source: source)
                    .frame(width: available.width, height: available.height)

                // Off the stage is shown but dimmed, and the stage keeps its
                // edge: the frame osu! draws is still unmistakable, and what is
                // past it reads as outside — there to be found and fixed, not
                // part of the picture.
                StageMat(stageRect: stageRect, container: available)
                    .allowsHitTesting(false)

                // Clicking the picture away from a selection clears it, the
                // way clicking empty space does in any editor.
                //
                // Above the Metal view, which would otherwise swallow the
                // click, and below the selection box, so the frame's own
                // gestures win where they overlap — there the box is what the
                // pointer was aiming at.
                //
                // It also picks: the clip under the pointer is outlined, and a
                // click selects it — ⌘ or ⇧ to add it to the selection — so
                // what is plainly on screen can be chosen without hunting for
                // it on the timeline. Over the whole space, so a sprite off the
                // stage can be picked too.
                if let onPick {
                    let stage = OsuCanvas.size(widescreen: model.isWidescreen)
                    let toStage = containerCoordinates(stageRect: stageRect)
                    Color.clear
                        .frame(width: available.width, height: available.height)
                        .contentShape(.rect)
                        .onContinuousHover(coordinateSpace: .local) { phase in
                            switch phase {
                            case let .active(location): hover(at: location, toStage: toStage)
                            case .ended: hover(at: nil, toStage: toStage)
                            }
                        }
                        .gesture(
                            SpatialTapGesture().onEnded { value in
                                pick(at: value.location, toStage: toStage)
                            },
                        )

                    // Under the selection frame, and only for a clip that is
                    // not already selected: the frame already says where that
                    // one is.
                    if let hovered = model.hoverBounds,
                       let id = model.hoveredClipID,
                       !model.selectedClipIDs.contains(id)
                    {
                        HoverOutline(
                            bounds: hovered,
                            stageSize: (Double(stage.width), Double(stage.height)),
                            viewSize: size,
                        )
                        .onStage(stageRect)
                        .allowsHitTesting(false)
                    }
                }

                if let onClipDrag {
                    let stage = OsuCanvas.size(widescreen: model.isWidescreen)
                    SelectionBox(
                        bounds: model.selectionBounds,
                        origin: clipOrigin?(),
                        stageSize: (Double(stage.width), Double(stage.height)),
                        viewSize: size,
                        // Held to what the view shows, not to the stage: a
                        // frame larger than the stage is why one zooms out.
                        visibleArea: CGRect(
                            x: -stageRect.minX,
                            y: -stageRect.minY,
                            width: available.width,
                            height: available.height,
                        ),
                        isLocked: isClipLocked(),
                        onTap: { point in pick(at: point, toStage: stageCoordinates(viewSize: size)) },
                        onPointer: { point in hover(at: point, toStage: stageCoordinates(viewSize: size)) },
                        onDrag: onClipDrag,
                        onSnap: { snapX, snapY in
                            snappedX = snapX
                            snappedY = snapY
                        },
                    )
                    .onStage(stageRect)
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
                    .onStage(stageRect)
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
                    .onStage(stageRect)
                    .id("path-editor")
                }

                // The camera tool, above everything: while the camera is being
                // edited, the frame is what every drag on the canvas is aimed
                // at. It draws nothing when the camera is not being edited.
                if let editableCamera, let onCameraFrame, let onCameraPathPoint {
                    CameraFrameEditor(
                        model: model,
                        camera: editableCamera,
                        viewSize: size,
                        onFrame: onCameraFrame,
                        onPathPoint: onCameraPathPoint,
                    )
                    .onStage(stageRect)
                    .id("camera-frame")
                }
            }
            .frame(width: available.width, height: available.height, alignment: .topLeading)
            // Behind everything, catching the wheel and the pinch: ⌘ and the
            // wheel, or a pinch, zoom about the pointer; the wheel alone pans.
            .background {
                CanvasScrollMonitor(
                    onPan: { model.panCanvas(by: $0) },
                    onZoom: { factor, point in model.zoomCanvas(by: factor, at: point) },
                )
            }
            // The view's own edge: an overlay reaching past it — a frame
            // larger than the stage, zoomed in — stops here rather than
            // spilling over the panels around the canvas.
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.stage, style: .continuous))
            .onChange(of: available, initial: true) { _, size in
                model.canvasContainerSize = size
            }

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
            CanvasOverlayControls(model: model, cameraView: cameraView)

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

/// A thin outline around the clip under the pointer.
///
/// Thinner and fainter than the selection frame, with no handles: it says
/// "this is what a click would pick", not "this is picked". Turned with the
/// clip, like the frame, so the outline sits where the clip is drawn.
private struct HoverOutline: View {
    let bounds: ClipBounds
    let stageSize: (width: Double, height: Double)
    let viewSize: CGSize

    var body: some View {
        let scale = Double(viewSize.width) / stageSize.width
        let rect = CGRect(
            x: (bounds.minX + Double(OsuCanvas.xOffset)) * scale,
            y: bounds.minY * scale,
            width: bounds.width * scale,
            height: bounds.height * scale,
        )
        Rectangle()
            .strokeBorder(Theme.Palette.selection.opacity(0.6), lineWidth: 1)
            .frame(width: rect.width, height: rect.height)
            .rotationEffect(.radians(bounds.rotation))
            .position(x: rect.midX, y: rect.midY)
    }
}

private extension View {
    /// Lays an overlay over the stage rect, so its own stage geometry holds
    /// wherever the zoom and pan have put the stage.
    func onStage(_ rect: CGRect) -> some View {
        frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }
}

/// Dims what lies off the stage and draws the stage's edge.
///
/// The canvas shows what sits outside the frame osu! draws — that is what
/// zooming out is for — but it must still read as outside: dimmed, with the
/// stage's edge unmistakable.
private struct StageMat: View {
    let stageRect: CGRect
    let container: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The hole and the edge share one radius — the stage's, the same
            // one every other surface in the app is cut to. A square stage
            // inside rounded panels read as a different family of thing.
            Path { path in
                path.addRect(CGRect(origin: .zero, size: container))
                path.addRoundedRect(
                    in: stageRect,
                    cornerSize: CGSize(width: Theme.Radius.stage, height: Theme.Radius.stage),
                    style: .continuous,
                )
            }
            .fill(Theme.Fill.offStage, style: FillStyle(eoFill: true))

            RoundedRectangle(cornerRadius: Theme.Radius.stage, style: .continuous)
                .strokeBorder(Theme.Border.stage, lineWidth: 1)
                .frame(width: stageRect.width, height: stageRect.height)
                .offset(x: stageRect.minX, y: stageRect.minY)
        }
        .frame(width: container.width, height: container.height, alignment: .topLeading)
    }
}

/// Catches the scroll wheel and the trackpad pinch over the canvas.
///
/// SwiftUI on macOS has no scroll-wheel handler, and the Metal view under the
/// canvas keeps its own events — so a local monitor, answering only for
/// events over this view and in its window, and leaving every other scroll in
/// the app alone. It takes no clicks: it only listens.
private struct CanvasScrollMonitor: NSViewRepresentable {
    var onPan: (CGSize) -> Void
    var onZoom: (Double, CGPoint) -> Void

    func makeNSView(context _: Context) -> MonitorView {
        let view = MonitorView()
        view.onPan = onPan
        view.onZoom = onZoom
        return view
    }

    func updateNSView(_ view: MonitorView, context _: Context) {
        view.onPan = onPan
        view.onZoom = onZoom
    }

    final class MonitorView: NSView {
        var onPan: (CGSize) -> Void = { _ in }
        var onZoom: (Double, CGPoint) -> Void = { _, _ in }
        private var monitor: Any?

        /// Top-left origin, the way SwiftUI measures the canvas.
        override var isFlipped: Bool { true }

        /// Listens only; clicks go to whatever is in front.
        override func hitTest(_: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Removed when the view leaves its window, which is also how it
            // leaves for good; a monitor left behind would answer for a
            // canvas that no longer exists.
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
                guard let self, let handled = self.handle(event), handled else { return event }
                return nil
            }
        }

        /// `true` when the event was over the canvas and has been used.
        private func handle(_ event: NSEvent) -> Bool? {
            guard event.window === window else { return false }
            let point = convert(event.locationInWindow, from: nil)
            guard bounds.contains(point) else { return false }

            switch event.type {
            case .magnify:
                onZoom(1 + event.magnification, point)
            case .scrollWheel:
                // A mouse wheel reports lines, a trackpad points; lines are
                // scaled so a notch moves a useful amount.
                let step: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
                let dx = event.scrollingDeltaX * step
                let dy = event.scrollingDeltaY * step
                if event.modifierFlags.contains(.command) {
                    onZoom(pow(1.01, Double(dy)), point)
                } else {
                    onPan(CGSize(width: dx, height: dy))
                }
            default:
                return false
            }
            return true
        }
    }
}
