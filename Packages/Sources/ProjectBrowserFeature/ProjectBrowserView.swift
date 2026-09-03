import DesignSystem
import StoryboardPersistence
import SwiftUI
import UniformTypeIdentifiers

/// Landing screen: a wall of recently opened beatmaps, or a way to add one.
public struct ProjectBrowserView: View {
    @State private var model: ProjectBrowserModel
    @State private var isTargetedForDrop = false
    /// Width the grid has to divide, measured rather than assumed.
    @State private var availableWidth: CGFloat = 0

    /// Card width. The grid fits as many as the window allows.
    private static let cardWidth: CGFloat = 260

    /// - Parameter onOpen: called with a folder that loaded successfully.
    public init(onOpen: @escaping (URL) -> Void) {
        _model = State(wrappedValue: ProjectBrowserModel(onOpen: onOpen))
    }

    public var body: some View {
        // The reader wraps the scroll view rather than sitting inside it: a
        // scroll view offers its child whatever height the content asks for, so
        // an empty state inside one can never learn how tall the window is —
        // and it ends up a band across the top instead of a page.
        GeometryReader { window in
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
                header

                if model.recents.isEmpty {
                    // Given the window's height less what the header took, so
                    // it fills the page rather than floating in a strip.
                    emptyState
                        .frame(
                            minHeight: max(
                                240,
                                window.size.height
                                    - Theme.Spacing.section * 2
                                    - Self.headerHeight,
                            ),
                        )
                } else {
                    recentsGrid
                }
            }
            // Measured inside the padding, so the width is what the grid
            // actually divides. `onGeometryChange` rather than a
            // `GeometryReader`: a reader reports its parent's size and
            // publishes none of its own, leaving the stack unable to size
            // itself.
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                availableWidth = width
            }
            .padding(Theme.Spacing.section)
        }
        .frame(minWidth: 760, minHeight: 560)
        .background(Theme.Palette.stage)
        .surfaceGroup()
        .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop, perform: handleDrop)
        .overlay {
            if isTargetedForDrop { dropHighlight }
        }
        }
        .animation(Theme.Motion.quick, value: isTargetedForDrop)
        .alert(
            "Could not open that folder",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.dismissError() } },
            ),
        ) {
            Button("OK", role: .cancel) { model.dismissError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // ─── Sections ────────────────────────────────────────────────────────────

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.regular) {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text("Animate Editor")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.primary)

                Text("Storyboards for osu!")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.secondary)
            }

            Spacer(minLength: Theme.Spacing.regular)

            // Creating in the header as well as in the empty state.
            //
            // The empty state is where somebody starts their *first* project,
            // and it is gone the moment there is a second — so putting the only
            // way to create one there means the command disappears exactly when
            // a project already exists. The header is where it has to live.
            Button("New Project", systemImage: "plus", action: createProject)
                .buttonStyle(.themed(.primary, size: .small, capsule: true))
                .disabled(model.openingURL != nil)

            // A folder chosen from the panel has no card to spin, so the button
            // carries the wait: the spinner takes the icon's place rather than
            // appearing beside it, which would shift the label mid-click.
            Button(action: chooseFolder) {
                Label {
                    Text("Open Folder")
                } icon: {
                    ZStack {
                        // A folder, not a plus: it sits beside New Project now,
                        // and two pluses side by side say the same thing about
                        // two commands that do not.
                        //
                        // Both drawn into one slot so the label does not shift
                        // when they swap: a spinner is wider than the icon.
                        Image(systemName: "folder")
                            .opacity(model.openingURL != nil ? 0 : 1)

                        if model.openingURL != nil {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
                }
            }
            .buttonStyle(.themed(.secondary, size: .small, capsule: true))
            .disabled(model.openingURL != nil)
        }
    }

    /// Equal columns rather than `.adaptive`.
    ///
    /// An adaptive grid with an open maximum hands the leftover width out
    /// unevenly, so one card ends up wider than its neighbour — and since the
    /// height follows the aspect ratio, taller too, which is what leaves the
    /// footers on different lines.
    private var columns: [GridItem] {
        // The gaps come out of the width before it is divided: ignoring them
        // fits one column too many at certain widths, and every card then
        // lands under the minimum it was sized for.
        let gap = Theme.Spacing.regular
        let count = max(1, Int((availableWidth + gap) / (Self.cardWidth + gap)))

        return Array(
            repeating: GridItem(.flexible(), spacing: gap),
            count: count,
        )
    }

    private var recentsGrid: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
            SectionHeader("Recent")

            LazyVGrid(
                columns: columns,
                spacing: Theme.Spacing.loose,
            ) {
                ForEach(model.recents) { entry in
                    BeatmapCard(
                        entry: entry,
                        preview: model.previews[entry.id],
                        isOpening: model.isOpening(entry.url),
                        open: { model.open(url: entry.url) },
                        forget: { model.forget(entry) },
                    )
                }
            }
        }
    }

    /// Roughly what the header occupies, so the empty state can claim the rest.
    ///
    /// A constant rather than a measurement: the two would have to be measured
    /// and published back, and being a few points out changes nothing — the
    /// empty state is centred in whatever it gets.
    private static let headerHeight: CGFloat = 96

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.compact) {
            Text("No projects yet")
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(Theme.Palette.primary)

            Text("Start from an audio file, or open a beatmap folder")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.tertiary)

            // The action inside the empty state, not only in the header.
            //
            // An empty screen is the one moment somebody has nothing to look at
            // and no idea what to do — so the thing to do goes where they are
            // already looking, rather than in a corner they have to find.
            Button("New Project", systemImage: "plus", action: createProject)
                .buttonStyle(.themed(.primary, size: .regular, capsule: true))
                .padding(.top, Theme.Spacing.tight)
        }
        // Centred in whatever height it is given, both ways: a message pinned
        // to the top of a tall panel reads as content that failed to fill it.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, Theme.Spacing.page)
        // Placeholder cards behind the message, the way a real grid would look.
        //
        // An empty panel says "nothing here"; a ghost of the layout says "your
        // projects will look like this", which is the difference between a dead
        // end and a starting point.
        .background {
            PlaceholderGrid()
                .padding(Theme.Spacing.compact)
        }
        .surface(.panel, radius: Theme.Radius.stage)
    }

    /// Ghosted cards behind the empty message.
    ///
    /// Hatched rather than solid: a filled card reads as content that failed to
    /// load, and the point is to show the *shape* of what goes here.
    private struct PlaceholderGrid: View {
        var body: some View {
            VStack(spacing: Theme.Spacing.compact) {
                ForEach(0 ..< 3, id: \.self) { _ in
                    HStack(spacing: Theme.Spacing.compact) {
                        ForEach(0 ..< 3, id: \.self) { _ in
                            RoundedRectangle(
                                cornerRadius: Theme.Radius.control,
                                style: .continuous,
                            )
                            .strokeBorder(Theme.Border.card, lineWidth: 1)
                        }
                    }
                    // Shared out rather than fixed, so the ghosts fill the
                    // panel however tall it is — a short band of cards behind a
                    // tall page looks like the grid failed to load.
                    .frame(maxHeight: .infinity)
                }
            }
            .opacity(0.5)
            // Never in the way of the message or the button above it.
            .allowsHitTesting(false)
        }
    }

    /// Shown while a folder is held over the window.
    ///
    /// The whole window is the drop target rather than a marked-out zone, which
    /// is one fewer thing to aim at.
    private var dropHighlight: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.stage, style: .continuous)
            .strokeBorder(
                Theme.Palette.accent,
                style: StrokeStyle(lineWidth: 2, dash: [8, 5]),
            )
            .padding(Theme.Spacing.compact)
            .allowsHitTesting(false)
    }

    // ─── Actions ─────────────────────────────────────────────────────────────

    /// Picks a track, then where the project should live.
    ///
    /// Two panels rather than one: the audio is what a storyboard cannot do
    /// without, and where the folder goes is a separate decision — asking both
    /// at once would need a form, and this is two clicks.
    private func createProject() {
        let audioPanel = NSOpenPanel()
        audioPanel.canChooseFiles = true
        audioPanel.canChooseDirectories = false
        audioPanel.allowsMultipleSelection = false
        audioPanel.allowedContentTypes = [.mp3, .wav, .audio]
        audioPanel.prompt = "Choose"
        audioPanel.message = "Choose the song this storyboard runs over"

        guard audioPanel.runModal() == .OK, let audio = audioPanel.url else { return }

        let folderPanel = NSOpenPanel()
        folderPanel.canChooseFiles = false
        folderPanel.canChooseDirectories = true
        folderPanel.canCreateDirectories = true
        folderPanel.allowsMultipleSelection = false
        folderPanel.prompt = "Create"
        folderPanel.message = "Where should the project folder go?"

        guard folderPanel.runModal() == .OK, let parent = folderPanel.url else { return }

        model.createProject(withAudio: audio, in: parent)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose a beatmap folder"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.open(url: url)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in model.open(url: url) }
        }
        return true
    }
}

// ─── Card ────────────────────────────────────────────────────────────────────

/// One beatmap: its cover art, title, and who mapped it.
private struct BeatmapCard: View {
    let entry: RecentProjectStore.Entry
    let preview: BeatmapPreview?
    let isOpening: Bool
    let open: () -> Void
    let forget: () -> Void

    var body: some View {
        PosterCard(
            title: preview?.title ?? entry.name,
            subtitle: subtitle,
            badge: badge,
            isBusy: isOpening,
            action: open,
        ) {
            PosterArtwork(url: preview?.backgroundURL)
        } footer: {
            footer
        }
        .contextMenu {
            Button("Open", action: open)
            Button("Remove from Recents", role: .destructive, action: forget)
        }
    }

    /// Artist, falling back to the folder's own name while the preview loads.
    private var subtitle: String? {
        guard let preview, !preview.artist.isEmpty else { return nil }
        return preview.artist
    }

    private var badge: String? {
        guard let bpm = preview?.bpm, bpm > 0 else { return nil }
        return String(format: "%.0f BPM", bpm)
    }

    @ViewBuilder
    private var footer: some View {
        if let creator = preview?.creator, !creator.isEmpty {
            Text("Mapped by \(creator)")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.tertiary)
                .lineLimit(1)
        } else {
            Text(entry.url.deletingLastPathComponent().lastPathComponent)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.tertiary)
                .lineLimit(1)
                .truncationMode(.head)
        }
    }
}
