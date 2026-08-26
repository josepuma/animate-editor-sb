import DesignSystem
import StoryboardCore
import SwiftUI

/// The editor layout: a rail and panel on the left, the canvas in the middle,
/// an inspector on the right, and the timeline across the bottom.
///
/// The canvas is supplied by the caller so this target stays independent of
/// playback and rendering — it owns arrangement, not behaviour.
public struct EditorShellView<Canvas: View>: View {
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
        self.seek = seek
        self.canvas = canvas()
    }

    public var body: some View {
        VStack(spacing: Theme.Spacing.snug) {
            toolbar
            workspace

            // The workspace is only as tall as the canvas, so leftover height
            // collects here rather than stretching the panels.
            Spacer(minLength: 0)

            TrackTimelineView(
                shell: shell,
                currentTime: currentTime,
                duration: duration,
                breaks: breaks,
                kiaiSections: kiaiSections,
                seek: seek,
            )
        }
        .padding(Theme.Spacing.snug)
        .background(Theme.Palette.stage)
        // Measured on the whole window rather than inside the row: a
        // `GeometryReader` around the row would report its parent's size
        // without publishing its own, which is what left the columns
        // mismatched.
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            availableWidth = size.width - Theme.Spacing.snug * 2
            // What the workspace may use, once the toolbar, the timeline and
            // the gaps between them have taken theirs.
            availableHeight = max(
                0,
                size.height
                    - ShellLayout.toolbarHeight
                    - timelineHeight
                    - Theme.Spacing.snug * 4,
            )
        }
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

    /// The rail, panels and canvas, every column exactly as tall as the canvas.
    ///
    /// Letting each column size itself never worked: a panel that wants height
    /// stretches the row past the picture, and chasing those one by one only
    /// moves the problem. Instead the canvas's height is computed from the
    /// width left over, and every column is given that height outright.
    private var workspace: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.snug) {
            let height = canvasHeight(in: availableWidth)

            SidebarRail(
                items: SidePanel.allCases,
                selection: $shell.sidePanel,
                icon: \.systemImage,
                label: \.title,
            )
            .frame(height: height, alignment: .top)
            .surface(.bar, radius: Theme.Radius.control)

            if shell.isSidePanelVisible {
                SidePanelView(shell: shell)
                    .frame(height: height, alignment: .top)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            canvas
                .frame(height: height)

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
                .frame(height: height, alignment: .top)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    /// Height the track timeline needs for its ruler and rows.
    private var timelineHeight: CGFloat {
        TrackTimelineView.height(trackCount: shell.tracks.count)
    }

    /// Width the workspace has to lay out in, tracked from the window.
    @State private var availableWidth: CGFloat = 0
    @State private var availableHeight: CGFloat = 0

    /// How tall the canvas will be once the fixed-width columns take theirs.
    private func canvasHeight(in totalWidth: CGFloat) -> CGFloat {
        let columns = ShellLayout.railWidth
            + (shell.isSidePanelVisible ? SidePanelView.width : 0)
            + (shell.isInspectorVisible ? InspectorView.width : 0)
        let gaps = Theme.Spacing.snug
            * CGFloat(1 + (shell.isSidePanelVisible ? 1 : 0) + (shell.isInspectorVisible ? 1 : 0))

        let canvasWidth = max(0, totalWidth - columns - gaps)
        // Whichever runs out first decides: a wide, short window is limited by
        // its height rather than by the picture's proportions.
        return min(canvasWidth / ShellLayout.canvasAspect, availableHeight)
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
private enum ShellLayout {
    /// Aspect ratio of the storyboard canvas.
    static let canvasAspect: CGFloat = 854.0 / 480.0
    /// Width of the icon rail: one control plus its surrounding padding.
    static let railWidth: CGFloat = Theme.Size.control + Theme.Spacing.tight * 2
    /// Height of the title bar: its text plus padding.
    static let toolbarHeight: CGFloat = Theme.Size.controlSmall + Theme.Spacing.tight * 2
}
