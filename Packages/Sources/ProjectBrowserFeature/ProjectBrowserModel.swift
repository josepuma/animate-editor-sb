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

    /// The folder currently being validated, if any.
    ///
    /// Drives the spinner on its card: checking a beatmap means parsing its
    /// storyboard, which takes long enough on a real map that a card with no
    /// feedback reads as a click that did nothing.
    public private(set) var openingURL: URL?

    /// The project the hero plays, chosen once when the browser appears.
    ///
    /// Chosen here rather than per render: a hero that reshuffles whenever the
    /// list refreshes would swap trailers under somebody reading the first.
    public private(set) var featuredURL: URL?

    /// Whether the hero's trailer plays without sound.
    ///
    /// On by default — music starting by itself is startling — and remembered
    /// once changed, because asking again on every launch is a chore.
    public var isTrailerMuted: Bool {
        didSet { defaults.set(!isTrailerMuted, forKey: Self.soundKey) }
    }

    private let store: RecentProjectStore
    private let defaults: UserDefaults
    private let onOpen: (URL) -> Void

    private static let lastFeaturedKey = "projectBrowser.lastFeatured"
    /// Stored as "sound on", so an absent key reads as muted.
    private static let soundKey = "projectBrowser.trailerSound"

    /// - Parameters:
    ///   - store: where recent folders are remembered.
    ///   - onOpen: called with a folder that loaded successfully.
    public init(
        store: RecentProjectStore = RecentProjectStore(),
        defaults: UserDefaults = .standard,
        onOpen: @escaping (URL) -> Void,
    ) {
        self.store = store
        self.defaults = defaults
        self.onOpen = onOpen
        isTrailerMuted = !defaults.bool(forKey: Self.soundKey)
        refreshRecents()
        chooseFeatured()
    }

    /// The preview of the featured project, once it has loaded.
    public var featuredPreview: BeatmapPreview? {
        guard let featuredURL,
              let entry = recents.first(where: { $0.url == featuredURL })
        else { return nil }
        return previews[entry.id]
    }

    /// Picks the hero at random, never the one featured last time.
    ///
    /// Compared by path: an entry's id is minted afresh on every read, and a
    /// URL resolved from a bookmark can differ in its trailing slash.
    private func chooseFeatured() {
        let last = defaults.string(forKey: Self.lastFeaturedKey)
        var generator = SystemRandomNumberGenerator()
        let paths = recents.map(\.url.standardizedFileURL.path)
        guard let path = FeaturedPicker.pick(from: paths, avoiding: last, using: &generator) else {
            featuredURL = nil
            return
        }
        featuredURL = recents.first { $0.url.standardizedFileURL.path == path }?.url
        defaults.set(path, forKey: Self.lastFeaturedKey)
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
    /// Builds a project folder around an audio file and opens it.
    ///
    /// A storyboard needs a folder because that is what osu! reads, and the
    /// audio is the one thing it cannot do without: everything else — the
    /// difficulty, the `.osb`, the art — is either written here or added later.
    /// Requiring a beatmap up front meant a storyboard could only be started
    /// from someone else's map, and this editor exports video too.
    ///
    /// - Parameters:
    ///   - audio: the track to copy in. Copied rather than referenced, for the
    ///     same reason imported art is: osu! reads the folder, not your disk.
    ///   - parent: where the folder is created.
    public func createProject(withAudio audio: URL, in parent: URL) {
        guard openingURL == nil else { return }

        // Named after the track, which is what anyone would call it.
        let name = audio.deletingPathExtension().lastPathComponent
        var folder = parent.appendingPathComponent(name, isDirectory: true)

        // A second project from the same song gets its own folder rather than
        // landing in the first: opening what you thought was new and finding
        // last week's work is worse than an ugly name.
        var attempt = 2
        while FileManager.default.fileExists(atPath: folder.path) {
            folder = parent.appendingPathComponent("\(name) \(attempt)", isDirectory: true)
            attempt += 1
        }

        do {
            try FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true,
            )
            try FileManager.default.copyItem(
                at: audio,
                to: folder.appendingPathComponent(audio.lastPathComponent),
            )
        } catch {
            errorMessage = "Could not create the project: \(error.localizedDescription)"
            return
        }

        open(url: folder)
    }

    public func open(url: URL) {
        guard openingURL == nil else { return }
        openingURL = url

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    let folder = try BeatmapFolder(url: url)
                    _ = try BeatmapStoryboardLoader.load(from: folder)
                }
            }.value

            openingURL = nil

            switch result {
            case .success:
                store.remember(url: url)
                refreshRecents()
                errorMessage = nil
                onOpen(url)
            case let .failure(error):
                errorMessage = String(describing: error)
            }
        }
    }

    /// Whether `entry` is the folder being opened right now.
    public func isOpening(_ url: URL) -> Bool {
        openingURL == url
    }

    public func forget(_ entry: RecentProjectStore.Entry) {
        let wasFeatured = entry.url == featuredURL
        store.forget(url: entry.url)
        refreshRecents()
        // A trailer of a project no longer in the list would be a hero for
        // nothing; the rest of the time the hero stays put.
        if wasFeatured { chooseFeatured() }
    }

    public func dismissError() {
        errorMessage = nil
    }
}
