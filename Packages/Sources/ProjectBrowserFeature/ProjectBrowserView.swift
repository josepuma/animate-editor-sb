import DesignSystem
import StoryboardPersistence
import SwiftUI
import UniformTypeIdentifiers

/// Landing screen: one project playing as a poster, the rest beneath it — or,
/// with nothing opened yet, a way to start.
///
/// The poster's moving picture is handed in: playing a storyboard takes the
/// renderer and the editor's evaluation, and this feature imports neither.
public struct ProjectBrowserView<Trailer: View>: View {
    /// Made once, when the view appears — never in `init`.
    ///
    /// `State(wrappedValue:)` evaluates its argument on every init and throws
    /// all but the first away, so a model built there ran in full each time
    /// the parent rebuilt. Worse, its init *read* observed properties while
    /// the parent's body was evaluating, which subscribed the parent to a model
    /// nobody kept: that model's previews landing rebuilt the parent, which
    /// built another model, which loaded every preview again — a loop. Measured
    /// in release, half the main thread, and every new model picked a new
    /// featured project, so the trailer restarted without end.
    @State private var model: ProjectBrowserModel?
    private let onOpen: (URL) -> Void
    private let trailer: (URL, Double?, Bool) -> Trailer

    /// - Parameters:
    ///   - onOpen: called with a folder that loaded successfully.
    ///   - trailer: the featured project playing — given its folder, the
    ///     mapper's preview time and whether to stay silent.
    public init(
        onOpen: @escaping (URL) -> Void,
        @ViewBuilder trailer: @escaping (URL, Double?, Bool) -> Trailer,
    ) {
        self.onOpen = onOpen
        self.trailer = trailer
    }

    public var body: some View {
        if let model {
            ProjectBrowserPage(model: model, trailer: trailer)
        } else {
            Theme.Tone.base
                .frame(minWidth: 760, minHeight: 560)
                .onAppear { model = ProjectBrowserModel(onOpen: onOpen) }
        }
    }
}

/// The browser itself, over a model that already exists.
struct ProjectBrowserPage<Trailer: View>: View {
    let model: ProjectBrowserModel
    let trailer: (URL, Double?, Bool) -> Trailer
    @State private var isTargetedForDrop = false
    /// Width the grid has to divide, measured rather than assumed.
    @State private var availableWidth: CGFloat = 0

    /// Card width. The grid fits as many as the window allows.
    /// Computed: Swift allows no stored statics on a generic type.
    private static var cardWidth: CGFloat { 260 }

    var body: some View {
        // The reader wraps the scroll view rather than sitting inside it: a
        // scroll view offers its child whatever height the content asks for, so
        // an empty state inside one can never learn how tall the window is —
        // and it ends up a band across the top instead of a page.
        GeometryReader { window in
        ScrollView {
            if let featured = model.featuredURL {
                let heroHeight = max(
                    Theme.Size.heroMinimum,
                    window.size.height * Theme.Size.heroShare,
                )
                // The projects start on the hero's faded foot rather than
                // below it, the way a streaming home runs its first row into
                // the poster: the page reads as one surface, not a banner with
                // a list stapled under it.
                ZStack(alignment: .top) {
                    hero(for: featured, height: heroHeight)

                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: heroHeight - Theme.Size.heroOverlap)
                        shelf
                            .onGeometryChange(for: CGFloat.self) { proxy in
                                proxy.size.width
                            } action: { width in
                                availableWidth = width
                            }
                            .padding(.horizontal, Theme.Spacing.page)
                            .padding(.bottom, Theme.Spacing.page)
                    }
                }
            } else {
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
        }
        .frame(minWidth: 760, minHeight: 560)
        // The window's tone, as in the editor: black belongs to the stage.
        .background(Theme.Tone.base)
        .surfaceGroup()
        .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop, perform: handleDrop)
        .overlay {
            if isTargetedForDrop { dropHighlight }
        }
        }
        // Up under the transparent title bar, so the poster is the window's
        // own top: a strip of window above it would frame the picture instead
        // of letting it be the page.
        .ignoresSafeArea(.container, edges: .top)
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
                Text("Pulse Studio")
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

    /// The featured project, with the app's header laid over its top edge.
    ///
    /// Over the picture rather than above it: a bar above the poster pushes
    /// the poster down, and the poster is the page.
    private func hero(for url: URL, height: CGFloat) -> some View {
        let preview = model.featuredPreview
        let entry = model.recents.first { $0.url == url }
        return FeaturedHero(
            title: preview?.title ?? entry?.name ?? url.lastPathComponent,
            artist: preview?.artist ?? "",
            detail: Self.detail(for: preview),
            artworkURL: preview?.backgroundURL,
            isMuted: model.isTrailerMuted,
            isOpening: model.isOpening(url),
            open: { model.open(url: url) },
            toggleMute: { model.isTrailerMuted.toggle() },
            bottomInset: Theme.Size.heroOverlap,
        ) {
            // Keyed by the folder so a different featured project is a new
            // player, not the old one asked to change its mind mid-load.
            trailer(url, preview?.previewTime, model.isTrailerMuted)
                .id(url)
        }
        .frame(height: height)
        .overlay(alignment: .top) {
            header
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.top, Theme.Spacing.section)
        }
    }

    /// Every project under the hero, in a grid that runs down the page.
    ///
    /// A grid rather than a sideways row: a row is for browsing a few things,
    /// and finding one project among many means paging through it a screen at
    /// a time. A grid shows them all at a glance.
    private var shelf: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.regular) {
            Text("Recent")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.primary)

            LazyVGrid(columns: columns(minimum: Theme.Size.shelfCard), spacing: Theme.Spacing.section) {
                ForEach(model.recents) { entry in
                    let preview = model.previews[entry.id]
                    ShelfCard(
                        title: preview?.title ?? entry.name,
                        subtitle: Self.shelfSubtitle(for: preview),
                        isBusy: model.isOpening(entry.url),
                        isFeatured: entry.url == model.featuredURL,
                        action: { model.open(url: entry.url) },
                    ) {
                        PosterArtwork(url: preview?.backgroundURL)
                    }
                    .contextMenu {
                        Button("Open") { model.open(url: entry.url) }
                        Button("Remove from Recents", role: .destructive) { model.forget(entry) }
                    }
                }
            }
        }
    }

    /// "Artist · 128 BPM" on one quiet line, or nothing while it loads.
    private static func shelfSubtitle(for preview: BeatmapPreview?) -> String? {
        guard let preview else { return nil }
        let artist = preview.artist.isEmpty ? nil : preview.artist
        let tempo = preview.bpm.flatMap { $0 > 0 ? String(format: "%.0f BPM", $0) : nil }
        let parts = [artist, tempo].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Mapped by X · 128 BPM", or nothing while the preview loads.
    private static func detail(for preview: BeatmapPreview?) -> String? {
        guard let preview else { return nil }
        let creator = preview.creator.isEmpty ? nil : "Mapped by \(preview.creator)"
        let tempo = preview.bpm.flatMap { $0 > 0 ? String(format: "%.0f BPM", $0) : nil }
        let parts = [creator, tempo].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Equal columns rather than `.adaptive`.
    ///
    /// An adaptive grid with an open maximum hands the leftover width out
    /// unevenly, so one card ends up wider than its neighbour — and since the
    /// height follows the aspect ratio, taller too, which is what leaves the
    /// footers on different lines.
    private func columns(minimum: CGFloat) -> [GridItem] {
        // The gaps come out of the width before it is divided: ignoring them
        // fits one column too many at certain widths, and every card then
        // lands under the minimum it was sized for.
        let gap = Theme.Spacing.regular
        let count = max(1, Int((availableWidth + gap) / (minimum + gap)))

        return Array(
            repeating: GridItem(.flexible(), spacing: gap),
            count: count,
        )
    }

    private var recentsGrid: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
            SectionHeader("Recent")

            LazyVGrid(
                columns: columns(minimum: Self.cardWidth),
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
    private static var headerHeight: CGFloat { 96 }

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
                            // Tone, not an outline: the empty slots are the
                            // same surfaces the cards will be, only fainter.
                            RoundedRectangle(
                                cornerRadius: Theme.Radius.control,
                                style: .continuous,
                            )
                            .fill(Theme.Tone.raised)
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
    /// The artist and the tempo on one quiet line.
    ///
    /// The tempo was a pill laid over the artwork — a bright badge on every
    /// card shouting over the pictures it sits on, the same look the asset
    /// tiles dropped. As text beside the artist it is still there to read.
    private var subtitle: String? {
        let artist = preview.flatMap { $0.artist.isEmpty ? nil : $0.artist }
        let tempo = preview?.bpm.flatMap { $0 > 0 ? String(format: "%.0f BPM", $0) : nil }
        let parts = [artist, tempo].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
