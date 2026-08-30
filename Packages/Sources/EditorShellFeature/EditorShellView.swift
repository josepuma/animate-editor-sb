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

    @State private var shell = EditorShellModel()

    private let title: String
    private let sprites: [PreparedSprite]
    private let missingImagePaths: Set<String>
    private let currentTime: Double
    private let duration: Double
    private let drawnCount: Int
    private let grid: BeatGrid?
    private let breaks: [BreakPeriod]
    private let kiaiSections: [KiaiSection]
    private let waveformPeaks: [Float]
    private let seek: (Double) -> Void
    private let canvas: Canvas

    public init(
        title: String,
        sprites: [PreparedSprite],
        missingImagePaths: Set<String>,
        currentTime: Double,
        duration: Double,
        drawnCount: Int,
        grid: BeatGrid?,
        breaks: [BreakPeriod],
        kiaiSections: [KiaiSection],
        waveformPeaks: [Float] = [],
        seek: @escaping (Double) -> Void,
        @ViewBuilder canvas: () -> Canvas,
    ) {
        self.title = title
        self.sprites = sprites
        self.missingImagePaths = missingImagePaths
        self.currentTime = currentTime
        self.duration = duration
        self.drawnCount = drawnCount
        self.grid = grid
        self.breaks = breaks
        self.kiaiSections = kiaiSections
        self.waveformPeaks = waveformPeaks
        self.seek = seek
        self.canvas = canvas()
    }

    public var body: some View {
        // The timeline is its own region rather than another row in the stack,
        // so it gets more air above it than the toolbar and workspace get
        // between them. At an even gap it reads as crowding the canvas.
        VStack(spacing: Theme.Spacing.compact) {
            VStack(spacing: Theme.Spacing.snug) {
                toolbar
                workspace
            }

            TrackTimelineView(
                shell: shell,
                currentTime: currentTime,
                duration: duration,
                breaks: breaks,
                kiaiSections: kiaiSections,
                waveformPeaks: waveformPeaks,
                seek: seek,
            )
        }
        .padding(Theme.Spacing.snug)
        .frame(
            minWidth: ShellLayout.minimumWidth,
            minHeight: ShellLayout.minimumHeight,
        )
        .background(Theme.Palette.stage)
        .surfaceGroup()
        .animation(Theme.Motion.standard, value: shell.isSidePanelVisible)
        .animation(Theme.Motion.standard, value: shell.isInspectorVisible)
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
            SidebarRail(
                items: SidePanel.allCases,
                selection: $shell.sidePanel,
                icon: \.systemImage,
                label: \.title,
            )
            .frame(maxHeight: .infinity, alignment: .top)
            .surface(.bar, radius: Theme.Radius.control)

            if shell.isSidePanelVisible {
                SidePanelView(shell: shell)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            canvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if shell.isInspectorVisible {
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

    // ─── Toolbar ─────────────────────────────────────────────────────────────

    private var toolbar: some View {
        HStack(spacing: Theme.Spacing.compact) {
            Text(title)
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(Theme.Palette.primary)
                .lineLimit(1)

            Spacer()

            IconButton(
                systemImage: "sidebar.left",
                size: Theme.Size.controlSmall,
                help: shell.isSidePanelVisible ? "Hide side panel" : "Show side panel",
            ) {
                shell.isSidePanelVisible.toggle()
            }

            IconButton(
                systemImage: "sidebar.right",
                size: Theme.Size.controlSmall,
                help: shell.isInspectorVisible ? "Hide inspector" : "Show inspector",
            ) {
                shell.isInspectorVisible.toggle()
            }
        }
        .padding(.horizontal, Theme.Spacing.compact)
        .padding(.vertical, Theme.Spacing.tight)
        .surface(.bar, radius: Theme.Radius.control)
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
    /// Height of the title bar: its text plus padding.
    static let toolbarHeight: CGFloat = Theme.Size.controlSmall + Theme.Spacing.tight * 2

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
        toolbarHeight
            + minimumCanvasWidth / canvasAspect
            // Room for a ruler and two tracks.
            + TrackTimelineView.height(trackCount: 2)
            + Theme.Spacing.snug * 4
    }
}
