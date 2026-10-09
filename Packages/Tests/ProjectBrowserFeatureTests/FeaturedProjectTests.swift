import Foundation
import StoryboardPersistence
import Testing

@testable import ProjectBrowserFeature

/// The hero is chosen when the browser appears and remembered across launches,
/// so opening the app twice in a row shows two different projects.
@MainActor
@Suite("Featured project")
struct FeaturedProjectTests {
    private func defaults() -> UserDefaults {
        let name = "featured-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func folders(_ count: Int) throws -> [URL] {
        try (0 ..< count).map { index in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("featured-\(UUID().uuidString)-\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
    }

    @Test("two browsers in a row feature different projects")
    func differsFromLastTime() throws {
        let defaults = defaults()
        let store = RecentProjectStore(defaults: defaults)
        for url in try folders(2) { store.remember(url: url) }

        let first = ProjectBrowserModel(store: store, defaults: defaults, onOpen: { _ in })
        let second = ProjectBrowserModel(store: store, defaults: defaults, onOpen: { _ in })

        let a = try #require(first.featuredURL)
        let b = try #require(second.featuredURL)
        #expect(a.standardizedFileURL != b.standardizedFileURL)
    }

    @Test("nothing is featured without projects")
    func noneWithoutProjects() {
        let defaults = defaults()
        let model = ProjectBrowserModel(
            store: RecentProjectStore(defaults: defaults), defaults: defaults, onOpen: { _ in },
        )
        #expect(model.featuredURL == nil)
    }

    @Test("forgetting the featured project features another")
    func forgettingReplaces() throws {
        let defaults = defaults()
        let store = RecentProjectStore(defaults: defaults)
        for url in try folders(2) { store.remember(url: url) }
        let model = ProjectBrowserModel(store: store, defaults: defaults, onOpen: { _ in })

        let featured = try #require(model.featuredURL)
        let entry = try #require(model.recents.first { $0.url == featured })
        model.forget(entry)

        #expect(model.featuredURL != nil)
        #expect(model.featuredURL != featured)
    }

    @Test("the trailer starts muted, and remembers being unmuted")
    func muteIsRemembered() {
        // Music starting on its own is startling; once somebody chose sound,
        // asking again on every launch is a chore.
        let defaults = defaults()
        let store = RecentProjectStore(defaults: defaults)
        let first = ProjectBrowserModel(store: store, defaults: defaults, onOpen: { _ in })
        #expect(first.isTrailerMuted)

        first.isTrailerMuted = false
        let second = ProjectBrowserModel(store: store, defaults: defaults, onOpen: { _ in })
        #expect(!second.isTrailerMuted)
    }
}
