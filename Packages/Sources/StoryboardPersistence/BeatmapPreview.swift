import Foundation
import StoryboardCore

/// What a beatmap folder shows on a card: its artwork and who made it.
public struct BeatmapPreview: Sendable {
    public let title: String
    public let artist: String
    public let creator: String
    /// The map's background image, when it has one.
    public let backgroundURL: URL?
    /// Tempo of the first timing point.
    public let bpm: Double?
    /// Length of the track, in milliseconds.
    public let duration: Double?

    public init(
        title: String,
        artist: String,
        creator: String,
        backgroundURL: URL?,
        bpm: Double?,
        duration: Double?,
    ) {
        self.title = title
        self.artist = artist
        self.creator = creator
        self.backgroundURL = backgroundURL
        self.bpm = bpm
        self.duration = duration
    }

    /// `m:ss`, or `nil` when the length is unknown.
    public var durationText: String? {
        guard let duration else { return nil }
        let seconds = Int(duration / 1000)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Reads just enough of a beatmap folder to draw a card for it.
///
/// Deliberately cheap: a browser listing ten folders should not parse ten
/// storyboards. Only the `.osu` header and the background's file name are read.
public enum BeatmapPreviewLoader {
    public static func load(from url: URL) -> BeatmapPreview? {
        guard let folder = try? BeatmapFolder(url: url) else { return nil }

        // Difficulties of one map share their metadata, so the first readable
        // file settles it.
        var timing: BeatmapTimingData?
        var backgroundPath: String?

        for osuPath in folder.files(withExtensions: ["osu"]) {
            guard let data = folder.data(forRelativePath: osuPath),
                  let source = String(data: data, encoding: .utf8)
                      ?? String(data: data, encoding: .isoLatin1)
            else { continue }

            timing = OsuParser.parse(source)
            backgroundPath = backgroundImagePath(in: source)
            break
        }

        let backgroundURL = backgroundPath
            .flatMap { folder.fileURL(forRelativePath: $0) }
            // Some folders name their art nowhere the `.osu` mentions, so fall
            // back to the largest image that is not a storyboard sprite.
            ?? largestImage(in: folder)

        let metadata = timing?.metadata
        return BeatmapPreview(
            title: metadata?.displayTitle ?? url.lastPathComponent,
            artist: metadata?.displayArtist ?? "",
            creator: metadata?.creator ?? "",
            backgroundURL: backgroundURL,
            bpm: timing?.uninheritedPoints.first?.bpm,
            duration: nil,
        )
    }

    // ─── Background ──────────────────────────────────────────────────────────

    /// Finds the background declared in a `.osu` file's `[Events]` section.
    ///
    /// The line is `0,0,"filename.jpg",0,0` — a type of `0` marks the
    /// background, distinguishing it from videos and breaks.
    static func backgroundImagePath(in source: String) -> String? {
        var inEvents = false

        for rawLine in source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("[") {
                inEvents = line == "[Events]"
                continue
            }
            guard inEvents, !line.isEmpty, !line.hasPrefix("//") else { continue }

            let parts = line.split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count >= 3, parts[0].trimmingCharacters(in: .whitespaces) == "0" else {
                continue
            }

            let name = parts[2]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if !name.isEmpty { return name }
        }

        return nil
    }

    /// The biggest image outside the storyboard folder.
    ///
    /// A map's background is usually its largest image; sprites under `sb/` are
    /// excluded because they are pieces of the animation, not cover art.
    private static func largestImage(in folder: BeatmapFolder) -> URL? {
        folder.files(withExtensions: ["jpg", "jpeg", "png"])
            .filter { !$0.hasPrefix("sb/") && !$0.hasPrefix("sb\\") }
            .compactMap { folder.fileURL(forRelativePath: $0) }
            .max { lhs, rhs in
                fileSize(of: lhs) < fileSize(of: rhs)
            }
    }

    private static func fileSize(of url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
}
