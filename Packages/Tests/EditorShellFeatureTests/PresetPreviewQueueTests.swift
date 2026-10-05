import CoreGraphics
import StoryboardCore
import Testing

@testable import EditorShellFeature

/// The queue that fills the library's cards with previews.
///
/// A preview sets up the renderer on the main thread, so the queue exists to
/// spend that cost once per preset, only for cards that appeared, and one at a
/// time — never as a burst that freezes the panel.
@MainActor
@Suite("Preset preview queue")
struct PresetPreviewQueueTests {
    /// Counts what the renderer was asked for, in order.
    @MainActor
    final class Renderer {
        var asked: [String] = []

        func install(on shell: EditorShellModel) {
            shell.previewImage = { [self] subject in
                if case let .preset(preset) = subject { asked.append(preset.id) }
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

        shell.requestPreview(for: preset)
        shell.requestPreview(for: preset)
        await settle(shell)
        // Scrolled away and back: the card appears again.
        shell.requestPreview(for: preset)
        await settle(shell)

        #expect(renderer.asked == [preset.id])
        #expect(shell.presetPreviews[preset.id] != nil)
    }

    @Test("previews render in the order their cards appeared")
    func rendersInOrder() async throws {
        let shell = EditorShellModel()
        let renderer = Renderer()
        renderer.install(on: shell)
        let presets = Array(shell.presets.prefix(3))
        try #require(presets.count == 3)

        for preset in presets { shell.requestPreview(for: preset) }
        await settle(shell)

        #expect(renderer.asked == presets.map(\.id))
    }

    @Test("without a renderer nothing is queued")
    func noRendererNoWork() async throws {
        let shell = EditorShellModel()
        let preset = try #require(shell.presets.first)

        shell.requestPreview(for: preset)
        await settle(shell)

        #expect(shell.presetPreviews.isEmpty)
    }
}
