import Foundation
import StoryboardCore
import StoryboardPersistence

/// Plays the storyboard of a beatmap folder on disk.
public struct BeatmapStoryboardSource: StoryboardSource {
    public let displayName: String
    private let folder: BeatmapFolder
    private let sprites: [StoryboardSprite]

    /// Image paths the storyboard references that are not in the folder. Those
    /// sprites still animate, drawn as flat quads.
    public let missingImagePaths: Set<String>

    public let audioURL: URL?

    /// Timing and metadata from the beatmap's first readable `.osu`.
    public let timing: BeatmapTimingData?

    /// Loads the storyboard eagerly, so a broken folder fails here rather than
    /// mid-render.
    public init(folderURL: URL) throws {
        let folder = try BeatmapFolder(url: folderURL)
        let loaded = try BeatmapStoryboardLoader.load(from: folder)

        self.folder = folder
        sprites = loaded.sprites
        missingImagePaths = Set(loaded.missingImagePaths)
        audioURL = loaded.audioURL
        timing = loaded.timing

        // Prefer the beatmap's own title over the folder name, which usually
        // carries a leading beatmap id.
        let title = loaded.timing?.metadata.displayName ?? ""
        displayName = title.isEmpty ? folder.name : title
    }

    public func loadSprites() throws -> [PreparedSprite] {
        StoryboardResolver.prepare(sprites)
    }

    public func imageData(for filePath: String) -> Data? {
        folder.data(forRelativePath: filePath)
    }
}
