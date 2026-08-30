import Testing

@testable import StoryboardPersistence

/// A card needs the map's cover art, which the `.osu` names in its events
/// alongside videos and breaks.
@Suite("Beatmap preview")
struct BeatmapPreviewTests {
    @Test("finds the background image")
    func findsBackground() {
        let path = BeatmapPreviewLoader.backgroundImagePath(in: """
        [Events]
        //Background and Video events
        0,0,"bg.jpg",0,0
        """)

        #expect(path == "bg.jpg")
    }

    @Test("ignores videos and breaks")
    func ignoresOtherEvents() {
        // A video is type 1 and a break is type 2; only type 0 is the artwork.
        let path = BeatmapPreviewLoader.backgroundImagePath(in: """
        [Events]
        1,0,"intro.mp4"
        2,1000,3000
        0,0,"cover.png",0,0
        """)

        #expect(path == "cover.png")
    }

    @Test("ignores sprite lines")
    func ignoresSprites() {
        let path = BeatmapPreviewLoader.backgroundImagePath(in: """
        [Events]
        Sprite,Foreground,Centre,"sb/a.png",320,240
        0,0,"bg.jpg",0,0
        """)

        #expect(path == "bg.jpg")
    }

    @Test("only reads the events section")
    func onlyReadsEvents() {
        let path = BeatmapPreviewLoader.backgroundImagePath(in: """
        [General]
        0,0,"not-here.jpg",0,0
        [Events]
        0,0,"bg.jpg",0,0
        [TimingPoints]
        0,500,4,2,0,100,1,0
        """)

        #expect(path == "bg.jpg")
    }

    @Test("a file with no background yields nothing")
    func noBackground() {
        #expect(BeatmapPreviewLoader.backgroundImagePath(in: "[Events]\n2,1000,3000") == nil)
        #expect(BeatmapPreviewLoader.backgroundImagePath(in: "") == nil)
    }

    @Test("handles names with spaces and CRLF endings")
    func handlesAwkwardNames() {
        let path = BeatmapPreviewLoader.backgroundImagePath(
            in: "[Events]\r\n0,0,\"my cover art.jpg\",0,0\r\n",
        )

        #expect(path == "my cover art.jpg")
    }

    @Test("comments are skipped")
    func skipsComments() {
        let path = BeatmapPreviewLoader.backgroundImagePath(in: """
        [Events]
        //0,0,"commented.jpg",0,0
        0,0,"real.jpg",0,0
        """)

        #expect(path == "real.jpg")
    }

    @Test("duration text formats as minutes and seconds")
    func formatsDuration() {
        let preview = BeatmapPreview(
            title: "", artist: "", creator: "",
            backgroundURL: nil, bpm: nil, duration: 154_000,
        )

        #expect(preview.durationText == "2:34")
    }

    @Test("an unknown duration has no text")
    func unknownDuration() {
        let preview = BeatmapPreview(
            title: "", artist: "", creator: "",
            backgroundURL: nil, bpm: nil, duration: nil,
        )

        #expect(preview.durationText == nil)
    }
}
