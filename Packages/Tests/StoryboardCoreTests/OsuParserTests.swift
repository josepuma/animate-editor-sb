import Testing

@testable import StoryboardCore

@Suite("OsuParser")
struct OsuParserTests {
    // ─── General ─────────────────────────────────────────────────────────────

    @Test("reads the audio filename")
    func readsAudioFilename() {
        let timing = OsuParser.parse("""
        [General]
        AudioFilename: audio.mp3
        AudioLeadIn: 0
        """)

        #expect(timing.audioFilename == "audio.mp3")
    }

    @Test("keeps colons inside a filename")
    func keepsColonsInFilename() {
        let timing = OsuParser.parse("""
        [General]
        AudioFilename: weird: name.mp3
        """)

        #expect(timing.audioFilename == "weird: name.mp3")
    }

    // ─── Metadata ────────────────────────────────────────────────────────────

    @Test("reads metadata fields")
    func readsMetadata() {
        let timing = OsuParser.parse("""
        [Metadata]
        Title:EOS
        TitleUnicode:EOS
        Artist:ginkiha
        ArtistUnicode:ginkiha
        Creator:Mapper
        Version:Extra
        """)

        #expect(timing.metadata.title == "EOS")
        #expect(timing.metadata.artist == "ginkiha")
        #expect(timing.metadata.creator == "Mapper")
        #expect(timing.metadata.version == "Extra")
        #expect(timing.metadata.displayName == "ginkiha - EOS")
    }

    @Test("unicode fields fall back to their ASCII counterparts")
    func unicodeFallsBackToAscii() {
        let timing = OsuParser.parse("""
        [Metadata]
        Title:Song
        Artist:Band
        """)

        #expect(timing.metadata.titleUnicode == "Song")
        #expect(timing.metadata.artistUnicode == "Band")
    }

    @Test("displayName copes with missing halves")
    func displayNameHandlesMissingFields() {
        #expect(BeatmapMetadata(title: "Song").displayName == "Song")
        #expect(BeatmapMetadata(artist: "Band").displayName == "Band")
        #expect(BeatmapMetadata().displayName.isEmpty)
    }

    // ─── Timing points ───────────────────────────────────────────────────────

    @Test("parses uninherited timing points")
    func parsesUninheritedPoints() throws {
        let timing = OsuParser.parse("""
        [TimingPoints]
        1000,500,4,2,0,100,1,0
        """)

        let point = try #require(timing.uninheritedPoints.first)
        #expect(point.time == 1000)
        #expect(point.beatLength == 500)
        #expect(point.bpm == 120)
        #expect(point.meter == 4)
        #expect(point.kiai == false)
    }

    @Test("ignores inherited timing points")
    func ignoresInheritedPoints() {
        let timing = OsuParser.parse("""
        [TimingPoints]
        1000,500,4,2,0,100,1,0
        2000,-50,4,2,0,100,0,0
        """)

        // A green point carries a slider multiplier, not a tempo.
        #expect(timing.uninheritedPoints.count == 1)
    }

    @Test("ignores points with a non-positive beat length")
    func ignoresNonPositiveBeatLength() {
        let timing = OsuParser.parse("""
        [TimingPoints]
        1000,0,4,2,0,100,1,0
        2000,-100,4,2,0,100,1,0
        """)

        #expect(timing.uninheritedPoints.isEmpty)
    }

    @Test("timing points are sorted by time")
    func sortsTimingPoints() {
        let timing = OsuParser.parse("""
        [TimingPoints]
        3000,500,4,2,0,100,1,0
        1000,400,4,2,0,100,1,0
        2000,600,4,2,0,100,1,0
        """)

        #expect(timing.uninheritedPoints.map(\.time) == [1000, 2000, 3000])
    }

    @Test("finds the timing point governing a moment")
    func findsTimingPointAtTime() throws {
        let timing = OsuParser.parse("""
        [TimingPoints]
        1000,500,4,2,0,100,1,0
        5000,250,4,2,0,100,1,0
        """)

        #expect(timing.timingPoint(at: 3000)?.beatLength == 500)
        #expect(timing.timingPoint(at: 5000)?.beatLength == 250)
        #expect(timing.timingPoint(at: 9000)?.beatLength == 250)
        // Before the first point, the first one still applies.
        #expect(timing.timingPoint(at: 0)?.beatLength == 500)
    }

    @Test("a meter of zero falls back to four")
    func zeroMeterFallsBack() throws {
        let timing = OsuParser.parse("""
        [TimingPoints]
        0,500,0,2,0,100,1,0
        """)

        #expect(try #require(timing.uninheritedPoints.first).meter == 4)
    }

    // ─── Kiai ────────────────────────────────────────────────────────────────

    @Test("computes a kiai section between its on and off points")
    func computesKiaiSection() throws {
        let timing = OsuParser.parse("""
        [TimingPoints]
        1000,500,4,2,0,100,1,1
        5000,500,4,2,0,100,1,0
        """)

        let section = try #require(timing.kiaiSections.first)
        #expect(section.startTime == 1000)
        #expect(section.endTime == 5000)
    }

    @Test("kiai persists across points that do not clear it")
    func kiaiPersistsAcrossPoints() {
        let timing = OsuParser.parse("""
        [TimingPoints]
        1000,500,4,2,0,100,1,1
        2000,-50,4,2,0,100,0,1
        3000,500,4,2,0,100,1,0
        """)

        #expect(timing.kiaiSections.count == 1)
        #expect(timing.kiaiSections.first?.startTime == 1000)
        #expect(timing.kiaiSections.first?.endTime == 3000)
    }

    @Test("kiai still on at the last point stays open past it")
    func kiaiOpenAtEnd() throws {
        let timing = OsuParser.parse("""
        [TimingPoints]
        1000,500,4,2,0,100,1,1
        """)

        let section = try #require(timing.kiaiSections.first)
        #expect(section.startTime == 1000)
        #expect(section.endTime > 1000, "callers clamp this to the audio duration")
    }

    // ─── Breaks ──────────────────────────────────────────────────────────────

    @Test("parses breaks in both notations")
    func parsesBreaks() {
        let timing = OsuParser.parse("""
        [Events]
        2,1000,3000
        Break,5000,7000
        """)

        #expect(timing.breaks.count == 2)
        #expect(timing.breaks[0].startTime == 1000)
        #expect(timing.breaks[1].endTime == 7000)
    }

    @Test("ignores breaks that do not move forward")
    func ignoresZeroLengthBreaks() {
        let timing = OsuParser.parse("""
        [Events]
        2,1000,1000
        2,3000,2000
        """)

        #expect(timing.breaks.isEmpty)
    }

    @Test("ignores sprite lines in the events section")
    func ignoresSpriteEvents() {
        let timing = OsuParser.parse("""
        [Events]
        Sprite,Foreground,Centre,"sb/a.png",320,240
        2,1000,3000
        """)

        #expect(timing.breaks.count == 1)
    }

    // ─── Robustness ──────────────────────────────────────────────────────────

    @Test("handles CRLF line endings")
    func handlesCRLF() {
        let timing = OsuParser.parse(
            "[General]\r\nAudioFilename: audio.mp3\r\n[TimingPoints]\r\n0,500,4,2,0,100,1,0\r\n",
        )

        #expect(timing.audioFilename == "audio.mp3")
        #expect(timing.uninheritedPoints.count == 1)
    }

    @Test("skips comments and blank lines")
    func skipsCommentsAndBlanks() {
        let timing = OsuParser.parse("""
        [General]
        //a comment

        AudioFilename: audio.mp3
        """)

        #expect(timing.audioFilename == "audio.mp3")
    }

    @Test("an empty file yields empty data")
    func emptySource() {
        let timing = OsuParser.parse("")

        #expect(timing.audioFilename.isEmpty)
        #expect(timing.uninheritedPoints.isEmpty)
        #expect(timing.breaks.isEmpty)
        #expect(timing.kiaiSections.isEmpty)
    }

    @Test("a malformed timing point does not abort the parse")
    func malformedTimingPointIsSkipped() {
        let timing = OsuParser.parse("""
        [TimingPoints]
        garbage
        1000
        2000,500,4,2,0,100,1,0
        """)

        #expect(timing.uninheritedPoints.count == 1)
    }
}
