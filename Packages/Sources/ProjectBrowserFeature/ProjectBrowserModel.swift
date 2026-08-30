import Foundation
import StoryboardPersistence

/// Choosing which beatmap folder to open.
///
/// Holds no SwiftUI types, so the selection flow can be tested without a window.
@MainActor
@Observable
public final class ProjectBrowserModel {
    public private(set) var recents: [RecentProjectStore.Entry] = []

    /// Artwork and metadata per folder, keyed by entry id.
    ///
    /// Filled in after the list appears: reading ten folders' headers is fast
    /// but not instant, and the cards should not wait on it.
    public private(set) var previews: [RecentProjectStore.Entry.ID: BeatmapPreview] = [:]
    public private(set) var errorMessage: String?

    private let store: RecentProjectStore
    private let onOpen: (URL) -> Void

    /// - Parameters:
    ///   - store: where recent folders are remembered.
    ///   - onOpen: called with a folder that loaded successfully.
    public init(
        store: RecentProjectStore = RecentProjectStore(),
        onOpen: @escaping (URL) -> Void,
    ) {
        self.store = store
        self.onOpen = onOpen
        refreshRecents()
    }

    public func refreshRecents() {
        recents = store.entries()
        loadPreviews(for: recents)
    }

    /// Reads each folder's cover art off the main thread.
    private func loadPreviews(for entries: [RecentProjectStore.Entry]) {
        for entry in entries where previews[entry.id] == nil {
            let url = entry.url
            Task.detached(priority: .utility) {
                guard let preview = BeatmapPreviewLoader.load(from: url) else { return }
                await MainActor.run { self.previews[entry.id] = preview }
            }
        }
    }

    /// Validates `url` holds a storyboard, remembers it, and reports it open.
    ///
    /// Validating here means a bad folder surfaces an error in the browser
    /// rather than a blank canvas in the player.
    public func open(url: URL) {
        do {
            let folder = try BeatmapFolder(url: url)
            _ = try BeatmapStoryboardLoader.load(from: folder)

            store.remember(url: url)
            refreshRecents()
            errorMessage = nil
            onOpen(url)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    public func forget(_ entry: RecentProjectStore.Entry) {
        store.forget(url: entry.url)
        refreshRecents()
    }

    public func dismissError() {
        errorMessage = nil
    }
}
