import Testing
import StoryboardCore
import StoryboardRendering
@testable import PlaybackFeature

/// When a dragged clip's preview stops being drawn.
///
/// Released on mouse-up, the picture jumped back to where the clip had been
/// and then forward again once the committed sprites arrived — the evaluation
/// runs off the main thread, so there is always a gap. Held until the sprites
/// carrying the commit reach the GPU, the preview is swapped for them on the
/// same frame.
@MainActor
@Suite("Clip preview hold")
struct ClipPreviewHoldTests {
    private let preview = ClipPreview(clipID: "clip", dx: 40, dy: 0)

    @Test("a released preview is kept until newer sprites are uploaded")
    func heldUntilTheCommitArrives() {
        let model = PlaybackModel()
        model.previewDrag(preview)
        model.releasePreview()
        #expect(model.clipPreview == preview, "released before the commit landed")

        model.effectsChanged(to: [])
        #expect(model.clipPreview == preview, "dropped before the new sprites reached the GPU")

        model.spritesUploaded(revision: model.spritesRevision)
        #expect(model.clipPreview == nil)
    }

    /// Sprites already waiting when the hand came up do not carry the commit.
    @Test("an upload from before the release keeps the preview")
    func olderUploadKeepsIt() {
        let model = PlaybackModel()
        model.previewDrag(preview)
        model.effectsChanged(to: [])
        let pending = model.spritesRevision
        model.releasePreview()

        model.spritesUploaded(revision: pending)
        #expect(model.clipPreview == preview)
    }

    @Test("an upload in the middle of a drag keeps the preview")
    func dragSurvivesAnUpload() {
        let model = PlaybackModel()
        model.previewDrag(preview)
        model.effectsChanged(to: [])
        model.spritesUploaded(revision: model.spritesRevision)
        #expect(model.clipPreview == preview)
    }

    @Test("a cancelled preview goes at once")
    func cancelClears() {
        let model = PlaybackModel()
        model.previewDrag(preview)
        model.cancelPreview()
        #expect(model.clipPreview == nil)
    }
}
