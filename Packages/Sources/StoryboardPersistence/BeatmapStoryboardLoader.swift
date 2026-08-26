import Foundation
import StoryboardCore

/// Loads a beatmap folder's storyboard.
///
/// A storyboard lives either in a standalone `.osb` or in the `[Events]`
/// section of a `.osu` difficulty. Both are read and merged, matching osu!,
/// where a difficulty's own events draw on top of the shared `.osb`.
public enum BeatmapStoryboardLoader {
    public struct Result: Sendable {
        /// Sprites ready for resolution, in draw order.
        public let sprites: [StoryboardSprite]
        /// Relative path of the `.osb`, when one was found.
        public let osbPath: String?
        /// Relative paths of every `.osu` that contributed events.
        public let osuPaths: [String]
        /// Sprites whose image could not be found on disk.
        public let missingImagePaths: [String]
        /// Timing and metadata from the first `.osu` that parsed, when present.
        public let timing: BeatmapTimingData?
        /// The beatmap's audio file, resolved against the folder.
        public let audioURL: URL?

        public var spriteCount: Int { sprites.count }
    }

    /// Reads and merges the folder's storyboard sources.
    ///
    /// - Throws: ``BeatmapFolderError/noStoryboardFound(_:)`` when neither
    ///   source yields any sprite.
    public static func load(from folder: BeatmapFolder) throws -> Result {
        var sprites: [StoryboardSprite] = []

        // The shared .osb draws first, beneath any difficulty-specific events.
        let osbPath = folder.files(withExtensions: ["osb"]).first
        if let osbPath, let source = readText(at: osbPath, in: folder) {
            sprites.append(contentsOf: OsbParser.parse(source).sprites)
        }

        var contributingOsuPaths: [String] = []
        var timing: BeatmapTimingData?

        for osuPath in folder.files(withExtensions: ["osu"]) {
            guard let source = readText(at: osuPath, in: folder) else { continue }

            // Difficulties of one beatmap share their audio and tempo, so the
            // first readable file settles both.
            if timing == nil {
                let parsed = OsuParser.parse(source)
                if !parsed.audioFilename.isEmpty || !parsed.uninheritedPoints.isEmpty {
                    timing = parsed
                }
            }

            let parsedSprites = OsbParser.parse(source).sprites
            guard !parsedSprites.isEmpty else { continue }
            contributingOsuPaths.append(osuPath)
            sprites.append(contentsOf: parsedSprites)
        }

        guard !sprites.isEmpty else {
            throw BeatmapFolderError.noStoryboardFound(folder.name)
        }

        // Parsers number sprites per file, so ids collide once files are merged.
        sprites = sprites.enumerated().map { index, sprite in
            var renumbered = sprite
            renumbered.id = "sprite_\(index)"
            return renumbered
        }

        let missing = Set(sprites.map(\.filePath))
            .filter { folder.fileURL(forRelativePath: $0) == nil }
            .sorted()

        // Fall back to scanning for an audio file: some folders name one the
        // `.osu` does not, or have no readable `.osu` at all.
        let audioURL = timing
            .map(\.audioFilename)
            .flatMap { folder.fileURL(forRelativePath: $0) }
            ?? folder.files(withExtensions: ["mp3", "ogg", "wav", "m4a"])
                .first
                .flatMap { folder.fileURL(forRelativePath: $0) }

        return Result(
            sprites: sprites,
            osbPath: osbPath,
            osuPaths: contributingOsuPaths,
            missingImagePaths: missing,
            timing: timing,
            audioURL: audioURL,
        )
    }

    /// Reads a text file, falling back to Latin-1 for the older beatmaps that
    /// are not valid UTF-8.
    private static func readText(at relativePath: String, in folder: BeatmapFolder) -> String? {
        guard let data = folder.data(forRelativePath: relativePath) else { return nil }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
    }
}
