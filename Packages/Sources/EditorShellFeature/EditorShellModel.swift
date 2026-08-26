import Foundation
import StoryboardCore

/// Which panel the left rail is showing.
public enum SidePanel: String, CaseIterable, Identifiable, Sendable {
    case assets
    case scripts
    case layers
    case timing

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .assets: "photo.stack"
        case .scripts: "curlybraces"
        case .layers: "square.3.layers.3d"
        case .timing: "metronome"
        }
    }

    public var title: String {
        switch self {
        case .assets: "Assets"
        case .scripts: "Scripts"
        case .layers: "Layers"
        case .timing: "Timing"
        }
    }
}

/// A storyboard script and the sprites it produces.
///
/// Scripting is not implemented yet, so instances are currently derived from a
/// loaded storyboard rather than authored. The shape is what the real feature
/// will use: one track per script, which is how the work is organised.
public struct ScriptTrack: Identifiable, Sendable {
    public let id: String
    public var name: String
    public var layer: Layer
    public var spriteCount: Int
    /// When this script's sprites are on screen, for drawing the track.
    public var activeRanges: [ClosedRange<Double>]
    public var isVisible: Bool
    public var isLocked: Bool

    public init(
        id: String,
        name: String,
        layer: Layer,
        spriteCount: Int,
        activeRanges: [ClosedRange<Double>],
        isVisible: Bool = true,
        isLocked: Bool = false,
    ) {
        self.id = id
        self.name = name
        self.layer = layer
        self.spriteCount = spriteCount
        self.activeRanges = activeRanges
        self.isVisible = isVisible
        self.isLocked = isLocked
    }
}

/// An image the storyboard references.
public struct AssetItem: Identifiable, Sendable {
    public enum Kind: String, CaseIterable, Identifiable, Sendable {
        case all
        case image
        case audio

        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .all: "All"
            case .image: "Images"
            case .audio: "Audio"
            }
        }
    }

    public let id: String
    public var name: String
    public var path: String
    public var kind: Kind
    /// How many sprites reference this file.
    public var useCount: Int
    public var isMissing: Bool

    public init(
        id: String,
        name: String,
        path: String,
        kind: Kind,
        useCount: Int,
        isMissing: Bool = false,
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.kind = kind
        self.useCount = useCount
        self.isMissing = isMissing
    }
}

/// State for the editor shell: which panels are open and what they show.
@MainActor
@Observable
public final class EditorShellModel {
    public var sidePanel: SidePanel = .layers
    public var isSidePanelVisible = true
    public var isInspectorVisible = true
    public var assetFilter: AssetItem.Kind = .all

    /// Tracks derived from the loaded storyboard, grouped by layer.
    public private(set) var tracks: [ScriptTrack] = []
    public private(set) var assets: [AssetItem] = []
    public var selectedTrackID: ScriptTrack.ID?

    public init() {}

    public var selectedTrack: ScriptTrack? {
        guard let selectedTrackID else { return nil }
        return tracks.first { $0.id == selectedTrackID }
    }

    public var visibleAssets: [AssetItem] {
        assetFilter == .all ? assets : assets.filter { $0.kind == assetFilter }
    }

    // ─── Deriving content ────────────────────────────────────────────────────

    /// Builds tracks and assets from a loaded storyboard.
    ///
    /// Until scripts exist, sprites are grouped by layer: it is the only
    /// grouping the file itself provides, and it keeps the track list at five
    /// rows rather than thousands.
    /// Sprite count of the storyboard the current tracks were built from.
    ///
    /// SwiftUI calls this from both `onAppear` and `onChange`, and rebuilding
    /// mutates observed state — which would feed straight back into another
    /// update. Rebuilding only when the content actually changed breaks that.
    private var loadedSpriteCount: Int?

    public func load(sprites: [PreparedSprite], missingImagePaths: Set<String>) {
        guard loadedSpriteCount != sprites.count else { return }
        loadedSpriteCount = sprites.count

        tracks = Layer.allCases.compactMap { layer in
            let inLayer = sprites.filter { $0.layer == layer }
            guard !inLayer.isEmpty else { return nil }

            return ScriptTrack(
                id: layer.rawValue,
                name: layer.rawValue,
                layer: layer,
                spriteCount: inLayer.count,
                activeRanges: TrackRanges.merged(of: inLayer),
            )
        }
        // Keep the selection when the same track still exists.
        if selectedTrackID == nil || !tracks.contains(where: { $0.id == selectedTrackID }) {
            selectedTrackID = tracks.first?.id
        }

        var counts: [String: Int] = [:]
        for sprite in sprites {
            counts[sprite.filePath, default: 0] += 1
        }

        assets = counts
            .map { path, count in
                AssetItem(
                    id: path,
                    name: (path as NSString).lastPathComponent,
                    path: path,
                    kind: .image,
                    useCount: count,
                    isMissing: missingImagePaths.contains(path),
                )
            }
            .sorted { $0.useCount > $1.useCount }
    }

    public func toggleVisibility(of trackID: ScriptTrack.ID) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        tracks[index].isVisible.toggle()
    }

    public func toggleLock(of trackID: ScriptTrack.ID) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        tracks[index].isLocked.toggle()
    }

}

// ─── Range merging ───────────────────────────────────────────────────────────

/// Collapses sprite lifetimes into the spans a track draws.
///
/// Kept separate from the model so it stays a pure function: it is the only
/// non-obvious logic here, and it is worth testing without a main actor.
enum TrackRanges {
    /// A track showing thousands of individual bars is unreadable and slow, so
    /// spans closer together than this are merged. Half a second reads as one
    /// continuous run at any zoom a whole-track view uses.
    static let gapThreshold: Double = 500

    static func merged(of sprites: [PreparedSprite]) -> [ClosedRange<Double>] {
        let sorted = sprites
            .map { $0.activeStart...Swift.max($0.activeStart, $0.activeEnd) }
            .sorted { $0.lowerBound < $1.lowerBound }
        guard var current = sorted.first else { return [] }

        var merged: [ClosedRange<Double>] = []

        for range in sorted.dropFirst() {
            if range.lowerBound <= current.upperBound + gapThreshold {
                current = current.lowerBound...Swift.max(current.upperBound, range.upperBound)
            } else {
                merged.append(current)
                current = range
            }
        }
        merged.append(current)
        return merged
    }
}
