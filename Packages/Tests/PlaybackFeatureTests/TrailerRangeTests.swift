import StoryboardCore
import Testing

@testable import PlaybackFeature

/// Which stretch of the song the home screen's hero loops over.
@Suite("Trailer range")
struct TrailerRangeTests {
    @Test("starts at the map's preview time")
    func previewTime() {
        let range = TrailerRange.range(previewTime: 64_000, kiai: [], duration: 200_000)
        #expect(range == 64_000 ... 94_000)
    }

    @Test("without a preview time, starts at the first kiai")
    func firstKiai() {
        // Kiai is where the mapper marked the chorus: the next best guess at
        // the moment that sells the map.
        let kiai = [KiaiSection(startTime: 50_000, endTime: 70_000), KiaiSection(startTime: 120_000, endTime: 140_000)]
        let range = TrailerRange.range(previewTime: nil, kiai: kiai, duration: 200_000)
        #expect(range.lowerBound == 50_000)
    }

    @Test("with neither, starts two fifths in")
    func fallback() {
        let range = TrailerRange.range(previewTime: nil, kiai: [], duration: 200_000)
        #expect(range.lowerBound == 80_000)
    }

    @Test("a preview near the end backs up so the loop is not a blip")
    func nearEnd() {
        let range = TrailerRange.range(previewTime: 195_000, kiai: [], duration: 200_000)
        #expect(range == 170_000 ... 200_000)
    }

    @Test("a song shorter than a trailer loops whole")
    func shortSong() {
        let range = TrailerRange.range(previewTime: 5000, kiai: [], duration: 12_000)
        #expect(range == 0 ... 12_000)
    }
}
