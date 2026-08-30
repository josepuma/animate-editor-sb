import Foundation

/// Parses the sections of a `.osu` beatmap the editor needs: `[General]`,
/// `[Metadata]`, `[TimingPoints]` and the breaks in `[Events]`.
///
/// Ported from `app/lib/parser/osu.ts`. Storyboard sprites come from
/// ``OsbParser`` instead, which reads the same `[Events]` section.
public enum OsuParser {
    public static func parse(_ source: String) -> BeatmapTimingData {
        var section = ""
        var audioFilename = ""
        // osu! treats a missing key as off: a beatmap written before widescreen
        // storyboards existed is a 4:3 one.
        var isWidescreen = false
        var metadataFields: [String: String] = [:]
        var uninheritedPoints: [UninheritedTimingPoint] = []
        // Both red and green points, needed to track kiai across the map.
        var allPoints: [(time: Double, kiai: Bool)] = []
        var breaks: [BreakPeriod] = []

        for rawLine in source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = rawLine.trimmed()

            if line.hasPrefix("["), line.hasSuffix("]") {
                section = line
                continue
            }
            if line.isEmpty || line.hasPrefix("//") { continue }

            switch section {
            case "[General]":
                // Values may themselves contain colons, so split only on the first.
                if let colon = line.firstIndex(of: ":") {
                    let key = String(line[line.startIndex..<colon]).trimmed()
                    let value = String(line[line.index(after: colon)...]).trimmed()

                    switch key {
                    case "AudioFilename":
                        audioFilename = value
                    case "WidescreenStoryboard":
                        isWidescreen = value == "1"
                    default:
                        break
                    }
                }

            case "[Metadata]":
                if let colon = line.firstIndex(of: ":") {
                    let key = String(line[line.startIndex..<colon]).trimmed()
                    metadataFields[key] = String(line[line.index(after: colon)...]).trimmed()
                }

            case "[TimingPoints]":
                parseTimingPoint(line, into: &uninheritedPoints, all: &allPoints)

            case "[Events]":
                parseBreak(line, into: &breaks)

            default:
                continue
            }
        }

        uninheritedPoints.sort { $0.time < $1.time }
        allPoints.sort { $0.time < $1.time }
        breaks.sort { $0.startTime < $1.startTime }

        let metadata = BeatmapMetadata(
            title: metadataFields["Title"] ?? "",
            titleUnicode: metadataFields["TitleUnicode"] ?? metadataFields["Title"] ?? "",
            artist: metadataFields["Artist"] ?? "",
            artistUnicode: metadataFields["ArtistUnicode"] ?? metadataFields["Artist"] ?? "",
            creator: metadataFields["Creator"] ?? "",
            version: metadataFields["Version"] ?? "",
        )

        return BeatmapTimingData(
            metadata: metadata,
            audioFilename: audioFilename,
            isWidescreen: isWidescreen,
            uninheritedPoints: uninheritedPoints,
            breaks: breaks,
            kiaiSections: kiaiSections(from: allPoints),
        )
    }

    // ─── Sections ────────────────────────────────────────────────────────────

    /// `time,beatLength,meter,sampleSet,sampleIndex,volume,uninherited,effects`
    private static func parseTimingPoint(
        _ line: String,
        into uninherited: inout [UninheritedTimingPoint],
        all: inout [(time: Double, kiai: Bool)],
    ) {
        let parts = line.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmed() }
        guard parts.count >= 2 else { return }

        let time = (Double(parts[0]) ?? 0).rounded()
        let beatLength = Double(parts[1]) ?? 0
        let meter = parts.count > 2 ? (Int(parts[2]) ?? 4) : 4
        // The uninherited flag defaults to 1 when absent, matching older files.
        let isUninherited = parts.count > 6 ? (Int(parts[6]) ?? 1) == 1 : true
        let effects = parts.count > 7 ? (Int(parts[7]) ?? 0) : 0
        let kiai = effects & 1 == 1

        all.append((time: time, kiai: kiai))

        // A green point carries a negative beatLength: a slider multiplier,
        // not a tempo.
        if isUninherited, beatLength > 0 {
            uninherited.append(UninheritedTimingPoint(
                time: time,
                beatLength: beatLength,
                meter: meter == 0 ? 4 : meter,
                kiai: kiai,
            ))
        }
    }

    /// `2,startTime,endTime` or `Break,startTime,endTime`
    private static func parseBreak(_ line: String, into breaks: inout [BreakPeriod]) {
        let parts = line.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmed() }
        guard let type = parts.first, type == "2" || type == "Break", parts.count >= 3 else { return }

        let startTime = Double(parts[1]) ?? 0
        let endTime = Double(parts[2]) ?? 0
        guard endTime > startTime else { return }

        breaks.append(BreakPeriod(startTime: startTime, endTime: endTime))
    }

    /// Walks the timing points in order, joining runs where kiai stays on.
    ///
    /// Kiai persists from one timing point to the next until a point clears it.
    private static func kiaiSections(
        from allPoints: [(time: Double, kiai: Bool)],
    ) -> [KiaiSection] {
        var sections: [KiaiSection] = []
        var openStart: Double?

        for point in allPoints {
            if point.kiai, openStart == nil {
                openStart = point.time
            } else if !point.kiai, let start = openStart {
                sections.append(KiaiSection(startTime: start, endTime: point.time))
                openStart = nil
            }
        }

        // Still on at the last point: leave it open past the end, for callers
        // to clamp against the audio's real duration.
        if let start = openStart {
            let lastTime = allPoints.last?.time ?? start
            sections.append(KiaiSection(startTime: start, endTime: lastTime + 60_000))
        }

        return sections
    }
}
