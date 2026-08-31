import DesignSystem
import StoryboardCore
import SwiftUI

/// The editor layout: a rail and panel on the left, the canvas in the middle,
/// an inspector on the right, and the timeline across the bottom.
///
/// The canvas is supplied by the caller so this target stays independent of
/// playback and rendering — it owns arrangement, not behaviour.
public struct EditorShellView<Canvas: View>: View {
    /// Smallest window size this layout supports.
    public static var minimumWindowSize: CGSize {
        CGSize(width: ShellLayout.minimumWidth, height: ShellLayout.minimumHeight)
    }

    @State private var ownShell = EditorShellModel()
    /// Supplied by the app when the effects have to be visible outside the
    /// shell — the canvas renders them, and the canvas belongs to another
    /// feature. Without one, the shell keeps its own.
    private let providedShell: EditorShellModel?

    private var shell: EditorShellModel { providedShell ?? ownShell }

    private let title: String
    private let sprites: [PreparedSprite]
    private let missingImagePaths: Set<String>
    private let currentTime: Double
    /// Whether the clock is running: a keyframe cannot be placed against a
    /// moving playhead.
    private let isPlaying: Bool
    private let duration: Double
    private let timelineRange: ClosedRange<Double>
    private let drawnCount: Int
    private let grid: BeatGrid?
    private let breaks: [BreakPeriod]
    private let kiaiSections: [KiaiSection]
    private let waveformPeaks: [Float]
    private let isCanvasFullScreen: Bool
    private let seek: (Double) -> Void
    private let canvas: Canvas

    /// - Parameter isCanvasFullScreen: hides everything but the canvas. Owned
    ///   by whoever supplies the canvas, since the control that toggles it
    ///   lives there.
    public init(
        /// The model to drive, when the app needs to read the effects placed in
        /// it. Omitted, the shell owns one of its own.
        shell: EditorShellModel? = nil,
        title: String,
        sprites: [PreparedSprite],
        missingImagePaths: Set<String>,
        currentTime: Double,
        isPlaying: Bool = false,
        duration: Double,
        /// The span the timeline covers, which can start before the track and
        /// end after it. Defaults to the track's own length.
        timelineRange: ClosedRange<Double>? = nil,
        drawnCount: Int,
        grid: BeatGrid?,
        breaks: [BreakPeriod],
        kiaiSections: [KiaiSection],
        waveformPeaks: [Float] = [],
        isCanvasFullScreen: Bool = false,
        seek: @escaping (Double) -> Void,
        @ViewBuilder canvas: () -> Canvas,
    ) {
        providedShell = shell
        self.title = title
        self.sprites = sprites
        self.missingImagePaths = missingImagePaths
        self.currentTime = currentTime
        self.isPlaying = isPlaying
        self.duration = duration
        self.timelineRange = timelineRange ?? 0...max(duration, 1)
        self.drawnCount = drawnCount
        self.grid = grid
        self.breaks = breaks
        self.kiaiSections = kiaiSections
        self.waveformPeaks = waveformPeaks
        self.isCanvasFullScreen = isCanvasFullScreen
        self.seek = seek
        self.canvas = canvas()
    }

    public var body: some View {
        // The timeline is its own region rather than another row in the stack,
        // so it gets more air above it than the toolbar and workspace get
        // between them. At an even gap it reads as crowding the canvas.
        // The canvas is built once and kept in one place in the tree, whatever
        // is around it. Placing it in both branches of an `if` makes them two
        // different views to SwiftUI: switching would tear down the Metal view
        // and build another, restarting the audio from zero.
        //
        // The canvas carries its own floating controls, so transport, scrub and
        // volume travel with it and playback stays reachable in full screen.
        VStack(spacing: Theme.Spacing.compact) {
            workspace

            if !isCanvasFullScreen {
                TrackTimelineView(
                    shell: shell,
                    currentTime: currentTime,
                    isPlaying: isPlaying,
                    timelineRange: timelineRange,
                    audioDuration: duration,
                    breaks: breaks,
                    kiaiSections: kiaiSections,
                    waveformPeaks: waveformPeaks,
                    seek: seek,
                )
            }
        }
        // No inset in full screen: a margin around a picture meant to fill the
        // window reads as the window failing to fill.
        .padding(isCanvasFullScreen ? 0 : Theme.Spacing.snug)
        .frame(
            minWidth: ShellLayout.minimumWidth,
            minHeight: ShellLayout.minimumHeight,
        )
        .background(Theme.Palette.stage)
        .surfaceGroup()
        .toolbar { windowToolbar }
        // Copy, paste and delete, on the whole editor.
        //
        // Zero-size buttons rather than `onKeyPress`: a `keyboardShortcut`
        // reaches the window's key equivalents, which means it loses to a text
        // field that has the keyboard — and a Delete pressed while renaming a
        // track should delete a character, not the track.
        .background {
            editingShortcuts
        }
        .animation(Theme.Motion.standard, value: shell.isSidePanelVisible)
        .animation(Theme.Motion.standard, value: shell.isInspectorVisible)
        .animation(Theme.Motion.deliberate, value: isCanvasFullScreen)
        // Sprites arrive after the renderer finishes loading, so the count is
        // the signal that content is ready. `load` ignores repeat calls for the
        // same storyboard.
        .onChange(of: sprites.count, initial: true) { _, _ in
            shell.load(sprites: sprites, missingImagePaths: missingImagePaths)
        }
    }

    // ─── Workspace ───────────────────────────────────────────────────────────

    /// The rail, panels and canvas, filling the height between the toolbar and
    /// the timeline.
    ///
    /// The columns run full height and the canvas floats centred in what is
    /// left between them. Sizing the panels to the canvas instead — the obvious
    /// reading of "they should line up" — leaves a band of empty window beneath
    /// them whenever the picture is shorter than the space available.
    private var workspace: some View {
        HStack(spacing: Theme.Spacing.snug) {
            if !isCanvasFullScreen {
                SidebarRail(
                    items: SidePanel.allCases,
                    selection: Bindable(shell).sidePanel,
                    icon: \.systemImage,
                    label: \.title,
                )
                .frame(maxHeight: .infinity, alignment: .top)
                .surface(.bar, radius: Theme.Radius.control)

                if shell.isSidePanelVisible {
                    SidePanelView(shell: shell, playheadTime: currentTime)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }

            canvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if shell.isInspectorVisible, !isCanvasFullScreen {
                InspectorView(
                    shell: shell,
                    playback: InspectorView.PlaybackSnapshot(
                        currentTime: currentTime,
                        duration: duration,
                        drawnCount: drawnCount,
                        spriteCount: sprites.count,
                        bpm: grid?.primaryBPM,
                    ),
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// Keyboard equivalents for the editing commands.
    @ViewBuilder
    private var editingShortcuts: some View {
        Group {
            Button("Save") { shell.saveProject() }
                .keyboardShortcut("s", modifiers: .command)

            Button("Copy") { shell.copySelectedEffect() }
                .keyboardShortcut("c", modifiers: .command)

            Button("Paste") { shell.pasteEffect(at: currentTime) }
                .keyboardShortcut("v", modifiers: .command)

            Button("Duplicate") {
                guard let nodeID = shell.selectedNodeID else { return }
                shell.duplicateEffect(nodeID)
            }
            .keyboardShortcut("d", modifiers: .command)

            // Both keys: Delete is the one people reach for, and Forward Delete
            // is the one a full keyboard sends.
            Button("Delete", action: shell.deleteSelection)
                .keyboardShortcut(.delete, modifiers: [])
            Button("Delete Forward", action: shell.deleteSelection)
                .keyboardShortcut(.deleteForward, modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    // ─── Toolbar ─────────────────────────────────────────────────────────────

    private var titleLabel: some View {
        HStack(spacing: Theme.Spacing.tight) {
            Text(title)
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(Theme.Palette.primary)
                .lineLimit(1)

            // A project that failed to open says so, rather than looking like
            // an empty one — and saving is refused while it does.
            if shell.loadFailed {
                Label("Project could not be opened", systemImage: "exclamationmark.triangle")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.warning)
                    .help(shell.saveError ?? "")
            } else if shell.hasUnsavedChanges {
                Circle()
                    .fill(Theme.Palette.tertiary)
                    .frame(width: Theme.Size.ring * 4, height: Theme.Size.ring * 4)
                    .help("Unsaved changes — ⌘S to save")
            }
        }
    }

    /// What the window's own title bar shows for this editor.
    ///
    /// In the title bar rather than in a strip of its own: the bar is already
    /// there for the traffic lights and the back button, and a second row
    /// underneath it spends a band of window repeating what that space could
    /// have carried.
    @ToolbarContentBuilder
    private var windowToolbar: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .principal) {
                titleLabel
            }
            // A toolbar item is a control by default and arrives wearing its
            // own capsule. The title is a label, not something to press.
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .principal) {
                titleLabel
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                shell.isSidePanelVisible.toggle()
            } label: {
                Label(
                    shell.isSidePanelVisible ? "Hide side panel" : "Show side panel",
                    systemImage: "sidebar.left",
                )
            }
            .help(shell.isSidePanelVisible ? "Hide side panel" : "Show side panel")

            Button {
                shell.isInspectorVisible.toggle()
            } label: {
                Label(
                    shell.isInspectorVisible ? "Hide inspector" : "Show inspector",
                    systemImage: "sidebar.right",
                )
            }
            .help(shell.isInspectorVisible ? "Hide inspector" : "Show inspector")
        }
    }
}

// ─── Layout constants ────────────────────────────────────────────────────────

/// Fixed measurements the workspace needs to size itself.
@MainActor
private enum ShellLayout {
    /// Aspect ratio of the storyboard canvas.
    static let canvasAspect: CGFloat = 854.0 / 480.0
    /// Width of the icon rail: one control plus its surrounding padding.
    static let railWidth: CGFloat = Theme.Size.control + Theme.Spacing.tight * 2
    /// Height the window's own title bar takes off the content.
    ///
    /// The bar belongs to the window rather than to this layout, but the space
    /// it occupies still has to come out of the minimum.
    static let titleBarHeight: CGFloat = 28

    /// Smallest window the layout works in.
    ///
    /// Below this the canvas shrinks past the point where its controls fit and
    /// the panels have nothing left to show, so the window refuses to go there
    /// rather than degrading into something broken.
    static let minimumCanvasWidth: CGFloat = 480

    static var minimumWidth: CGFloat {
        railWidth
            + SidePanelView.width
            + InspectorView.width
            + minimumCanvasWidth
            + Theme.Spacing.snug * 5
    }

    static var minimumHeight: CGFloat {
        titleBarHeight
            + minimumCanvasWidth / canvasAspect
            // Room for a ruler and two tracks.
            + TrackTimelineView.height(trackCount: 2)
            + Theme.Spacing.snug * 4
    }
}
