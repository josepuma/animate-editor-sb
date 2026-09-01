import AppKit
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
    /// Whether the clock is running: a keyframe cannot be placed against a
    /// moving playhead.
    private let isPlaying: Bool
    private let duration: Double
    private let timelineRange: ClosedRange<Double>
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
        isPlaying: Bool = false,
        duration: Double,
        /// The span the timeline covers, which can start before the track and
        /// end after it. Defaults to the track's own length.
        timelineRange: ClosedRange<Double>? = nil,
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
        self.isPlaying = isPlaying
        self.duration = duration
        self.timelineRange = timelineRange ?? 0...max(duration, 1)
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
        // Scoped to the panels that slide, not applied to the whole editor.
        //
        // On the root stack these animate *every* change inside it, selecting a
        // clip included — so the inspector's new contents were faded in over a
        // fifth of a second rather than appearing. Measured at 45 to 55ms to
        // reach the screen whether the panel held four rows or thirty, which is
        // the signature of a fixed cost rather than of work per row.
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
                    SidePanelView(shell: shell, playheadTime: shell.playheadTime)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        .animation(Theme.Motion.standard, value: shell.isSidePanelVisible)
                }
            }

            canvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if shell.isInspectorVisible, !isCanvasFullScreen {
                // Nothing passed but the model: every property handed to a
                // view is a reason for SwiftUI to rebuild it, and the clock
                // would have rebuilt this panel sixty times a second.
                InspectorView(shell: shell)
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .animation(Theme.Motion.standard, value: shell.isInspectorVisible)
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// Whether a text field currently holds the keyboard.
    ///
    /// Asked of AppKit at the moment the shortcut fires rather than tracked as
    /// state: the window's first responder is the authority on where the
    /// keyboard is going, and mirroring it through every field in the tree
    /// would be a second copy to keep in step.
    ///
    /// A focused `NSTextField` hands the keyboard to a shared field editor, so
    /// the responder is an `NSText` whose delegate is the field — which is why
    /// this checks for the editor rather than for the field itself.
    private static var isEditingText: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if let text = responder as? NSText { return text.isEditable }
        return responder is NSTextView
    }

    /// Keyboard equivalents for the editing commands.
    @ViewBuilder
    private var editingShortcuts: some View {
        Group {
            Button("Save") { shell.saveProject() }
                .keyboardShortcut("s", modifiers: .command)

            Button("Export") { shell.exportStoryboard() }
                .keyboardShortcut("e", modifiers: .command)

            // Handed back to the field when one is being edited.
            //
            // A `keyboardShortcut` is claimed window-wide, so these swallowed
            // ⌘C and ⌘V before any text field could see them — copying and
            // pasting inside a field did nothing, or worse, duplicated the
            // selected clip instead. The same collision the space bar had with
            // play/pause.
            Button("Copy") {
                if Self.isEditingText {
                    // Passed on to the field editor, which is what the user was
                    // aiming at.
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                } else {
                    shell.copySelectedEffect()
                }
            }
            .keyboardShortcut("c", modifiers: .command)

            Button("Paste") {
                if Self.isEditingText {
                    NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                } else {
                    shell.pasteEffect(at: shell.playheadTime)
                }
            }
            .keyboardShortcut("v", modifiers: .command)

            // Cut and Select All have no editor-wide meaning yet, so their only
            // job is to reach the field. Without them macOS offers nothing at
            // all inside a text field in a window with no Edit menu.
            Button("Cut") {
                NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("x", modifiers: .command)

            Button("Select All") {
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("a", modifiers: .command)

            Button("Duplicate") {
                guard !Self.isEditingText, let nodeID = shell.selectedNodeID else { return }
                shell.duplicateEffect(nodeID)
            }
            .keyboardShortcut("d", modifiers: .command)

            // Both keys: Delete is the one people reach for, and Forward Delete
            // is the one a full keyboard sends.
            // Delete belongs to the field too, or backspacing a character
            // destroys the clip being edited.
            Button("Delete") {
                guard !Self.isEditingText else { return }
                shell.deleteSelection()
            }
            .keyboardShortcut(.delete, modifiers: [])

            Button("Delete Forward") {
                guard !Self.isEditingText else { return }
                shell.deleteSelection()
            }
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

            if shell.canExport {
                // Visible rather than only a shortcut: exporting is the point
                // of the editor, and a command no one can see is one no one
                // finds.
                Button("Export", systemImage: "square.and.arrow.up") {
                    shell.exportStoryboard()
                }
                .buttonStyle(.themed(.secondary, size: .small, capsule: true))
                .help(exportHelp)
            }
        }
    }

    /// What the export button says it will do, or what went wrong.
    private var exportHelp: String {
        if let error = shell.exportError { return "Export failed: \(error)" }
        if let last = shell.lastExport { return "Last exported to \(last.path)" }
        return "Write the storyboard and its images to an export folder — ⌘E"
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
