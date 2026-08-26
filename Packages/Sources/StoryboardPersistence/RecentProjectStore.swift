import Foundation

/// Remembers recently opened beatmap folders across launches.
///
/// Folders are stored as security-scoped bookmarks rather than paths: a sandboxed
/// app is granted access to a folder when the user picks it, and only a bookmark
/// carries that grant into the next launch.
public final class RecentProjectStore: @unchecked Sendable {
    public struct Entry: Identifiable, Sendable {
        public let id: UUID
        public let name: String
        public let url: URL
        public let lastOpened: Date

        public init(id: UUID = UUID(), name: String, url: URL, lastOpened: Date) {
            self.id = id
            self.name = name
            self.url = url
            self.lastOpened = lastOpened
        }
    }

    private struct StoredEntry: Codable {
        let name: String
        let bookmark: Data
        let lastOpened: Date
    }

    private let defaults: UserDefaults
    private let key: String
    private let limit: Int

    /// URLs whose security scope this process has started, so access can be
    /// released when the store goes away.
    private var accessedURLs: Set<URL> = []
    private let lock = NSLock()

    public init(
        defaults: UserDefaults = .standard,
        key: String = "recentProjects",
        limit: Int = 10,
    ) {
        self.defaults = defaults
        self.key = key
        self.limit = limit
    }

    deinit {
        for url in accessedURLs {
            url.stopAccessingSecurityScopedResource()
        }
    }

    // ─── Reading ─────────────────────────────────────────────────────────────

    /// Recently opened folders, newest first.
    ///
    /// Entries whose bookmark no longer resolves — the folder was moved,
    /// renamed or deleted — are dropped.
    public func entries() -> [Entry] {
        stored()
            .compactMap { entry in
                guard let url = resolve(entry.bookmark) else { return nil }
                return Entry(name: entry.name, url: url, lastOpened: entry.lastOpened)
            }
            .sorted { $0.lastOpened > $1.lastOpened }
    }

    /// Resolves a bookmark and begins security-scoped access to it.
    private func resolve(_ bookmark: Data) -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale,
        ) else { return nil }

        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        // Outside a sandbox this returns false and is unnecessary, so a failure
        // is not treated as fatal.
        if url.startAccessingSecurityScopedResource() {
            lock.lock()
            accessedURLs.insert(url)
            lock.unlock()
        }
        return url
    }

    // ─── Writing ─────────────────────────────────────────────────────────────

    /// Records `url` as the most recently opened folder.
    ///
    /// - Returns: `false` when no bookmark could be created, in which case the
    ///   folder still opens but will not be remembered.
    @discardableResult
    public func remember(url: URL) -> Bool {
        guard let bookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil,
        ) else { return false }

        let entry = StoredEntry(
            name: url.lastPathComponent,
            bookmark: bookmark,
            lastOpened: Date(),
        )

        var all = stored().filter { existing in
            // Replace any entry pointing at the same folder.
            resolve(existing.bookmark)?.standardizedFileURL != url.standardizedFileURL
        }
        all.insert(entry, at: 0)
        save(Array(all.prefix(limit)))
        return true
    }

    public func forget(url: URL) {
        let remaining = stored().filter {
            resolve($0.bookmark)?.standardizedFileURL != url.standardizedFileURL
        }
        save(remaining)
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }

    // ─── Storage ─────────────────────────────────────────────────────────────

    private func stored() -> [StoredEntry] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([StoredEntry].self, from: data)
        else { return [] }
        return decoded
    }

    private func save(_ entries: [StoredEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
    }
}
