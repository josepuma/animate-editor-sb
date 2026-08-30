import DesignSystem
import StoryboardPersistence
import SwiftUI
import UniformTypeIdentifiers

/// Landing screen: a wall of recently opened beatmaps, or a way to add one.
public struct ProjectBrowserView: View {
    @State private var model: ProjectBrowserModel
    @State private var isTargetedForDrop = false

    /// Card width. The grid fits as many as the window allows.
    private static let cardWidth: CGFloat = 260

    /// - Parameter onOpen: called with a folder that loaded successfully.
    public init(onOpen: @escaping (URL) -> Void) {
        _model = State(wrappedValue: ProjectBrowserModel(onOpen: onOpen))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
                header

                if model.recents.isEmpty {
                    emptyState
                } else {
                    recentsGrid
                }
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

            // A folder chosen from the panel has no card to spin, so the button
            // carries the wait: the spinner takes the icon's place rather than
            // appearing beside it, which would shift the label mid-click.
            Button(action: chooseFolder) {
                Label {
                    Text("Open Folder")
                } icon: {
                    ZStack {
                        // Both drawn into one slot so the label does not shift
                        // when they swap: a spinner is wider than a `plus`.
                        Image(systemName: "plus")
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

    private var recentsGrid: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
            SectionHeader("Recent")

            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: Self.cardWidth, maximum: .infinity),
                        spacing: Theme.Spacing.regular,
                    ),
                ],
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

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.compact) {
            Image(systemName: "folder.badge.plus")
                .font(Theme.Typography.emptyStateIcon)
                .foregroundStyle(Theme.Palette.tertiary)

            Text("No beatmaps yet")
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(Theme.Palette.secondary)

            Text("Drop a folder anywhere, or use Open Folder")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.page)
        .surface(.panel, radius: Theme.Radius.stage)
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
