import DesignSystem
import StoryboardPersistence
import SwiftUI
import UniformTypeIdentifiers

/// Landing screen: pick a beatmap folder, or reopen a recent one.
public struct ProjectBrowserView: View {
    @State private var model: ProjectBrowserModel
    @State private var isTargetedForDrop = false

    /// - Parameter onOpen: called with a folder that loaded successfully.
    public init(onOpen: @escaping (URL) -> Void) {
        _model = State(wrappedValue: ProjectBrowserModel(onOpen: onOpen))
    }

    public var body: some View {
        VStack(spacing: Theme.Spacing.section) {
            header
            dropZone
            if !model.recents.isEmpty { recentsList }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.section)
        .frame(minWidth: 620, minHeight: 520)
        .background(Theme.Palette.stage)
        .surfaceGroup()
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
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            Text("Animate Editor")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.primary)

            Text("Open a beatmap folder to play its storyboard")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dropZone: some View {
        VStack(spacing: Theme.Spacing.compact) {
            Image(systemName: "folder.badge.plus")
                .font(Theme.Typography.emptyStateIcon)
                .foregroundStyle(Theme.Palette.secondary)

            Text("Drop a beatmap folder here")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.secondary)

            Button("Choose Folder…", action: chooseFolder)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.page)
        .surface(.panel, radius: Theme.Radius.stage)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.stage, style: .continuous)
                .strokeBorder(
                    isTargetedForDrop ? Theme.Palette.accent : .clear,
                    style: StrokeStyle(lineWidth: 2, dash: [6, 4]),
                )
        }
        .animation(Theme.Motion.quick, value: isTargetedForDrop)
        .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop, perform: handleDrop)
    }

    private var recentsList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
            Text("Recent")
                .font(Theme.Typography.heading)
                .foregroundStyle(Theme.Palette.secondary)

            ScrollView {
                LazyVStack(spacing: Theme.Spacing.snug) {
                    ForEach(model.recents) { entry in
                        RecentRow(
                            entry: entry,
                            open: { model.open(url: entry.url) },
                            forget: { model.forget(entry) },
                        )
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

// ─── Rows ────────────────────────────────────────────────────────────────────

private struct RecentRow: View {
    let entry: RecentProjectStore.Entry
    let open: () -> Void
    let forget: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: Theme.Spacing.compact) {
                Image(systemName: "music.note.list")
                    .foregroundStyle(Theme.Palette.secondary)

                VStack(alignment: .leading, spacing: Theme.Spacing.hair) {
                    Text(entry.name)
                        .font(Theme.Typography.cardTitle)
                        .foregroundStyle(Theme.Palette.primary)
                        .lineLimit(1)

                    Text(entry.url.deletingLastPathComponent().path)
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Palette.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }

                Spacer(minLength: Theme.Spacing.snug)

                if isHovered {
                    IconButton(
                        systemImage: "xmark.circle.fill",
                        size: Theme.Size.controlSmall,
                        help: "Remove from recents",
                        action: forget,
                    )
                }
            }
            .padding(.horizontal, Theme.Spacing.compact)
            .padding(.vertical, Theme.Spacing.snug)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .surface(isHovered ? .raised : .panel, radius: Theme.Radius.control)
        .animation(Theme.Motion.quick, value: isHovered)
        .onHover { isHovered = $0 }
    }
}
