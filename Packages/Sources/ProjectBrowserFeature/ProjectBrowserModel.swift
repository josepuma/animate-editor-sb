import Foundation
import StoryboardPersistence

/// Choosing which beatmap folder to open.
///
/// Holds no SwiftUI types, so the selection flow can be tested without a window.
@MainActor
@Observable
public final class ProjectBrowserModel {
    public private(set) var recents: [RecentProjectStore.Entry] = []
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
