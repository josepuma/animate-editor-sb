import CoreGraphics
import StoryboardCore
import Testing

@testable import EditorShellFeature

/// The queue that fills the library's cards — presets and filters — with
/// previews.
///
/// A preview sets up the renderer on the main thread, so the queue exists to
/// spend that cost once per preset, only for cards that appeared, and one at a
/// time — never as a burst that freezes the panel.
@MainActor
@Suite("Library preview queue")
struct PresetPreviewQueueTests {
    /// Counts what the renderer was asked for, in order.
    @MainActor
    final class Renderer {
        var asked: [String] = []

        func install(on shell: EditorShellModel) {
            shell.previewImage = { [self] subject in
                asked.append(subject.key)
                return []
            }
        }
    }

    private func settle(_ shell: EditorShellModel) async {
        // The queue yields between previews; a handful of turns drains it.
        for _ in 0 ..< 50 { await Task.yield() }
    }

    @Test("each preset renders once, however often its card appears")
    func rendersOnce() async throws {
        let shell = EditorShellModel()
        let renderer = Renderer()
        renderer.install(on: shell)
        let preset = try #require(shell.presets.first)

        shell.requestPreview(for: .preset(preset))
        shell.requestPreview(for: .preset(preset))
        await settle(shell)
        // Scrolled away and back: the card appears again.
        shell.requestPreview(for: .preset(preset))
        await settle(shell)

        #expect(renderer.asked == [PreviewSubject.preset(preset).key])
        #expect(shell.previews[PreviewSubject.preset(preset).key] != nil)
    }

    @Test("previews render in the order their cards appeared")
    func rendersInOrder() async throws {
        let shell = EditorShellModel()
        let renderer = Renderer()
        renderer.install(on: shell)
        let presets = Array(shell.presets.prefix(3))
        try #require(presets.count == 3)

        for preset in presets { shell.requestPreview(for: .preset(preset)) }
        await settle(shell)

        #expect(renderer.asked == presets.map { PreviewSubject.preset($0).key })
    }

    @Test("without a renderer nothing is queued")
    func noRendererNoWork() async throws {
        let shell = EditorShellModel()
        let preset = try #require(shell.presets.first)

        shell.requestPreview(for: .preset(preset))
        await settle(shell)

        #expect(shell.previews.isEmpty)
    }

    @Test("filters share the queue with presets, in arrival order")
    func filtersShareTheQueue() async throws {
        let shell = EditorShellModel()
        let renderer = Renderer()
        renderer.install(on: shell)
        let preset = try #require(shell.presets.first)
        let filter = try #require(shell.filterDescriptors.first)

        shell.requestPreview(for: .filter(filter))
        shell.requestPreview(for: .preset(preset))
        shell.requestPreview(for: .filter(filter))
        await settle(shell)

        #expect(renderer.asked == [PreviewSubject.filter(filter).key, PreviewSubject.preset(preset).key])
    }

    @Test("a filter and an effect of the same type name keep separate previews")
    func keysDoNotCollide() throws {
        let shell = EditorShellModel()
        let effect = try #require(shell.library.descriptors.first)
        let filter = try #require(shell.filterDescriptors.first)
        // The keys are prefixed by kind, so a shared type name cannot make a
        // filter's card show an effect's picture.
        #expect(PreviewSubject.effect(effect).key.hasPrefix("effect:"))
        #expect(PreviewSubject.filter(filter).key.hasPrefix("filter:"))
        #expect(PreviewSubject.effect(effect).key != PreviewSubject.filter(filter).key)
    }
}
