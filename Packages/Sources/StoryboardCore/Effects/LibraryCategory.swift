import Foundation

/// How the library is grouped for whoever is looking through it.
///
/// By **what a thing does**, not by whether it is an `Effect` or a
/// `SpriteFilter`. That split is real and load-bearing in the code — one
/// generates, the other transforms — and it is the wrong first question to ask
/// someone hunting for "something that glows". After Effects makes the same
/// choice: its menu is Blur, Distort, Generate, and never "plug-in kind".
///
/// A closed list rather than free strings, which is what it was: nine things
/// had drifted into "Stylise" while "Basic" and "Particles" were declared and
/// never shown anywhere. A category nobody can misspell is a category the panel
/// can rely on.
public enum LibraryCategory: String, CaseIterable, Sendable, Codable {
    /// Makes something out of nothing.
    case generate = "Generate"
    /// Reacts to the music.
    ///
    /// Its own group rather than a corner of Generate: in an editor for a
    /// rhythm game, the things that listen to the song are the point, and
    /// burying them among the ones that do not is filing by implementation.
    case audio = "Audio"
    /// Built effects, several emitters wearing one name.
    case packs = "Packs"
    /// Changes how something looks.
    case stylise = "Stylise"
    /// Changes where or when something happens.
    case motion = "Motion"
    /// Changes what the file costs, or repeats what is there.
    case utility = "Utility"

    /// The order they appear in, which is roughly the order they are reached
    /// for: something has to exist before it can be styled.
    public static let displayOrder: [LibraryCategory] = [
        .generate, .audio, .packs, .stylise, .motion, .utility,
    ]

    public var systemImage: String {
        switch self {
        case .generate: "sparkles"
        case .audio: "waveform"
        case .packs: "shippingbox"
        case .stylise: "paintbrush"
        case .motion: "arrow.triangle.turn.up.right.diamond"
        case .utility: "wrench.and.screwdriver"
        }
    }
}

public extension LibraryCategory {
    /// Where this sits in the panel.
    var order: Int { Self.displayOrder.firstIndex(of: self) ?? Self.displayOrder.count }

    /// Orders anything that declares a category and a name.
    ///
    /// Shared because both libraries sort their own descriptors, and two copies
    /// of the same comparison drift the moment one is edited.
    static func precedes(
        _ first: (category: LibraryCategory, name: String),
        _ second: (category: LibraryCategory, name: String),
    ) -> Bool {
        first.category.order == second.category.order
            ? first.name < second.name
            : first.category.order < second.category.order
    }
}
