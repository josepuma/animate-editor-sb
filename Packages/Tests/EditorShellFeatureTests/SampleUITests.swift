import CoreGraphics
import Foundation
@testable import StoryboardCore
import Testing

@testable import EditorShellFeature

/// What the editor shows and allows for a sound clip.
///
/// A sound draws nothing, so the panels that exist to edit what a clip looks
/// like have nothing to offer it; and its length is its file's, so nothing
/// that stretches it may touch it.
@MainActor
@Suite("Sample UI")
struct SampleUITests {
    private func sample(_ shell: EditorShellModel, time: Double = 0) throws -> EffectNode {
        shell.audioDuration = { _ in 2 }
        return try #require(shell.addSample(at: "sb/clap.wav", time: time))
    }

    // ─── Tabs ────────────────────────────────────────────────────────────────

    @Test("a sound has the Effect and Clip tabs only")
    func sampleTabs() {
        #expect(InspectorTab.tabs(isScript: false, drawsSprites: false) == [.effect, .clip])
    }

    @Test("every other clip keeps the tabs it had")
    func otherTabs() {
        #expect(InspectorTab.tabs(isScript: false, drawsSprites: true) == [.effect, .clip, .filters])
        #expect(InspectorTab.tabs(isScript: true, drawsSprites: true) == [.effect, .clip, .filters, .output])
    }

    @Test("a tab chosen elsewhere falls back to Effect on a sound")
    func shownFallsBack() {
        #expect(InspectorTab.filters.shown(isScript: false, drawsSprites: false) == .effect)
        #expect(InspectorTab.clip.shown(isScript: false, drawsSprites: false) == .clip)
    }

    // ─── Keyframe mode ───────────────────────────────────────────────────────

    @Test("keyframe mode is refused for a sound")
    func keyframeModeRefused() throws {
        let shell = EditorShellModel()
        let node = try sample(shell)

        shell.openKeyframes(of: node.id)

        #expect(shell.keyframeNodeID == nil)
    }

    @Test("keyframe mode still opens for a clip that draws")
    func keyframeModeOpensForImage() throws {
        let shell = EditorShellModel()
        let node = try #require(shell.addImage(at: "a.png", time: 0))

        shell.openKeyframes(of: node.id)

        #expect(shell.keyframeNodeID == node.id)
        #expect(shell.selectedNodeID == node.id)
    }

    // ─── Timeline block ──────────────────────────────────────────────────────

    @Test("a sound's block is as wide as its stored length at the shared scale")
    func blockWidth() throws {
        let shell = EditorShellModel()
        let node = try sample(shell, time: 1000)
        let scale = TimelineScale(range: 0...10000, width: 1000)

        let spans = VisibleSpan.spans(of: [node.timeRange], scale: scale)

        let span = try #require(spans.first)
        #expect(abs(span.width - scale.width(of: 2000)) < 0.001)
        #expect(abs(span.start - scale.x(of: 1000)) < 0.001)
    }

    @Test("a zero-length sound still has a selectable minimum block")
    func zeroLengthBlock() {
        let scale = TimelineScale(range: 0...10000, width: 1000)
        let spans = VisibleSpan.spans(of: [500...500], scale: scale)
        #expect(spans.first?.width == VisibleSpan.minimumWidth)
    }

    @Test("a sound has no resize bars; a clip that draws does")
    func resizeBars() {
        #expect(ClipBlockRule.showsResizeBars(SampleEffect.descriptor) == false)
        #expect(ClipBlockRule.showsResizeBars(ImageEffect.descriptor) == true)
        #expect(ClipBlockRule.showsResizeBars(nil) == true)
    }

    @Test("a sound wears its own glyph, not the sparkles fallback")
    func badges() {
        #expect(ClipBlockRule.badges(filterIcons: [], descriptor: SampleEffect.descriptor)
            == [SampleEffect.descriptor.systemImage])
        #expect(ClipBlockRule.badges(filterIcons: [], descriptor: ImageEffect.descriptor) == ["sparkles"])
        #expect(ClipBlockRule.badges(filterIcons: ["a", "b"], descriptor: ImageEffect.descriptor) == ["a", "b"])
    }

    @Test("a sound has no tail and plays exactly once")
    func noTailNoLoop() throws {
        let shell = EditorShellModel()
        let node = try sample(shell)

        #expect(shell.tail(of: node.id) == 0)
        #expect(shell.passCount(of: node.id) == 1)
        #expect(shell.passDuration(of: node.id) == 2000)
    }

    @Test("moving a zero-length sound does not trap")
    func moveZeroLength() throws {
        let shell = EditorShellModel()
        shell.audioDuration = { _ in nil }
        let node = try #require(shell.addSample(at: "a.wav", time: 100))
        shell.moveEffect(node.id, to: 900)
        #expect(shell.effects[node.id]?.startTime == 900)
    }

    // ─── Inspector writes ────────────────────────────────────────────────────

    @Test("a volume drag is one undo step and lands in the collected samples")
    func volumeGesture() throws {
        let shell = EditorShellModel()
        let node = try sample(shell)

        shell.beginGesture()
        for volume in [10, 30, 55, 80] {
            shell.setValue(.integer(volume), for: SampleEffect.Param.volume, on: node.id)
        }
        shell.endGesture()

        #expect(shell.effects.samples.first?.volume == 80)
        shell.undo()
        #expect(shell.effects.samples.first?.volume == 100)
    }

    @Test("changing the layer and the file updates the collected sample")
    func layerAndFile() throws {
        let shell = EditorShellModel()
        let node = try sample(shell)

        shell.setValue(.choice("Foreground"), for: SampleEffect.Param.layer, on: node.id)
        shell.setValue(.text("sb/other.wav"), for: SampleEffect.Param.file, on: node.id)

        #expect(shell.effects.samples.first?.layer == .foreground)
        #expect(shell.effects.samples.first?.path == "sb/other.wav")
    }

    // ─── Creation ────────────────────────────────────────────────────────────

    @Test("the blank-effect menu never offers a sound")
    func hiddenFromMenu() {
        let shell = EditorShellModel()
        let types = shell.creatableDescriptors.map(\.type)

        #expect(!types.contains(SampleEffect.descriptor.type))
        #expect(types.contains(ImageEffect.descriptor.type) || !types.isEmpty)
        #expect(shell.library.descriptors.map(\.type).contains(SampleEffect.descriptor.type))
    }

    // ─── Assets ──────────────────────────────────────────────────────────────

    @Test("the folder listing tells audio from images by extension")
    func kindInference() {
        let shell = EditorShellModel()
        shell.loadFolderAssets(["a.png", "sb/hit.wav", "sb/loop.MP3", "sb/x.ogg", "bg.jpg"])

        let kinds = Dictionary(uniqueKeysWithValues: shell.assets.map { ($0.path, $0.kind) })
        #expect(kinds["a.png"] == .image)
        #expect(kinds["bg.jpg"] == .image)
        #expect(kinds["sb/hit.wav"] == .audio)
        #expect(kinds["sb/loop.MP3"] == .audio)
        #expect(kinds["sb/x.ogg"] == .audio)
    }

    @Test("the Audio chip shows only the sounds")
    func audioFilter() {
        let shell = EditorShellModel()
        shell.loadFolderAssets(["a.png", "sb/hit.wav"])
        shell.assetFilter = .audio
        #expect(shell.visibleAssets.map(\.path) == ["sb/hit.wav"])
    }

    @Test("a sound is never decoded as a picture")
    func noThumbnailForAudio() {
        let shell = EditorShellModel()
        var asked: [String] = []
        shell.assetThumbnail = { path in asked.append(path); return nil }

        _ = shell.thumbnail(for: "sb/hit.wav")
        _ = shell.thumbnail(for: "sb/a.png")

        #expect(asked == ["sb/a.png"])
    }

    @Test("a placed sample counts as a use of its file")
    func sampleUsage() throws {
        let shell = EditorShellModel()
        shell.loadFolderAssets(["sb/clap.wav", "sb/unused.wav"])
        shell.assetFilter = .audio
        _ = try sample(shell)
        _ = try sample(shell, time: 500)

        let uses = Dictionary(uniqueKeysWithValues: shell.visibleAssets.map { ($0.path, $0.useCount) })
        #expect(uses["sb/clap.wav"] == 2)
        #expect(uses["sb/unused.wav"] == 0)
    }

    @Test("importing keeps sounds and images and refuses anything else")
    func importFilters() {
        let shell = EditorShellModel()
        shell.importAssets = { _ in ["sb/hit.wav", "sb/a.png", "sb/notes.txt"] }

        shell.importAssetsFromDisk(into: .storyboard)

        let paths = Set(shell.assets.map(\.path))
        #expect(paths == ["sb/hit.wav", "sb/a.png"])
        #expect(shell.saveError != nil)
    }

    @Test("importing only supported files raises no error")
    func importClean() {
        let shell = EditorShellModel()
        shell.importAssets = { _ in ["sb/hit.ogg"] }
        shell.importAssetsFromDisk(into: .storyboard)
        #expect(shell.saveError == nil)
        #expect(shell.assets.map(\.kind) == [.audio])
    }

    // ─── Placement routing ───────────────────────────────────────────────────

    @Test("an audio asset places a sample; an image places an image")
    func routing() throws {
        let shell = EditorShellModel()
        shell.audioDuration = { _ in 1 }

        let sound = try #require(shell.placeAsset(at: "sb/clap.WAV", time: 0))
        let picture = try #require(shell.placeAsset(at: "sb/a.png", time: 0))

        #expect(sound.type == SampleEffect.descriptor.type)
        #expect(picture.type == ImageEffect.descriptor.type)
    }
}
