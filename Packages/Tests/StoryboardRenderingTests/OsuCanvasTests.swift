import Testing

@testable import StoryboardRendering

@Suite("OsuCanvas")
struct OsuCanvasTests {
    @Test("the wide stage carries the offset, the narrow one does not")
    func offsetFollowsTheStage() {
        // The wide stage is the 640-point playfield with room either side; the
        // narrow one is the playfield itself, so storyboard and canvas space
        // are the same and nothing is shifted.
        #expect(OsuCanvas.offset(widescreen: true) == 107)
        #expect(OsuCanvas.offset(widescreen: false) == 0)
    }

    @Test("the offset accounts for the width either stage adds")
    func offsetMatchesTheExtraWidth() {
        let extra = OsuCanvas.width - OsuCanvas.narrowWidth
        #expect(OsuCanvas.offset(widescreen: true) == extra / 2)
    }

    @Test("the stages are the ratios they claim")
    func stagesHaveTheirRatios() {
        let wide = OsuCanvas.size(widescreen: true)
        let narrow = OsuCanvas.size(widescreen: false)

        #expect(abs(wide.width / wide.height - 16.0 / 9.0) < 0.01)
        #expect(abs(narrow.width / narrow.height - 4.0 / 3.0) < 0.01)
    }

    @Test("the centre of the playfield is the centre of either stage")
    func playfieldCentresOnBothStages() {
        // osu! positions sprites around (320, 240) whichever stage is in use,
        // so a sprite left there has to land in the middle of both.
        let centre: Float = 320

        let wide = OsuCanvas.size(widescreen: true)
        let narrow = OsuCanvas.size(widescreen: false)

        #expect(centre + OsuCanvas.offset(widescreen: true) == wide.width / 2)
        #expect(centre + OsuCanvas.offset(widescreen: false) == narrow.width / 2)
    }
}
