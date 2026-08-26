import MetalKit
import StoryboardCore

/// Supplies a storyboard and its images to the playback feature.
///
/// The feature never reaches for a file system or a demo generator itself:
/// whoever composes the app decides where content comes from. That keeps
/// playback testable and lets the development harness feed it a generated
/// storyboard while the shipping app feeds it a beatmap folder.
public protocol StoryboardSource: Sendable {
    /// Name shown in the UI.
    var displayName: String { get }

    /// The track to play alongside the storyboard, when there is one.
    ///
    /// A source without audio plays against a synthetic clock instead.
    var audioURL: URL? { get }

    /// Tempo, kiai and breaks, when the source knows them. Without this the
    /// timeline still scrubs, just with no beat grid.
    var timing: BeatmapTimingData? { get }

    /// Image paths the storyboard references but the source cannot supply.
    var missingImagePaths: Set<String> { get }

    /// Loads the storyboard's sprites, ready for resolution.
    func loadSprites() throws -> [PreparedSprite]

    /// Image data for a sprite's file path, or `nil` when it cannot be found —
    /// such sprites are drawn as flat quads rather than failing the load.
    func imageData(for filePath: String) -> Data?
}

public extension StoryboardSource {
    /// Sources with no audio opt out by inheriting this.
    var audioURL: URL? { nil }
    /// Sources with no beatmap timing opt out by inheriting this.
    var timing: BeatmapTimingData? { nil }
    /// Sources that can supply every image opt out by inheriting this.
    var missingImagePaths: Set<String> { [] }
}

/// A source backed by `.osb` text already in memory.
public struct InMemoryStoryboardSource: StoryboardSource {
    public let displayName: String
    private let osb: String
    private let images: @Sendable (String) -> Data?

    public init(
        displayName: String,
        osb: String,
        images: @escaping @Sendable (String) -> Data?,
    ) {
        self.displayName = displayName
        self.osb = osb
        self.images = images
    }

    public func loadSprites() throws -> [PreparedSprite] {
        StoryboardResolver.prepare(OsbParser.parse(osb).sprites)
    }

    public func imageData(for filePath: String) -> Data? {
        images(filePath)
    }
}
