import Foundation
import StoryboardCore

/// The images the app provides, by name.
///
/// A script names an image the same way a native effect does: either one of
/// these, or a path relative to the beatmap folder. Mirroring `BuiltInSprite`
/// rather than restating its paths as literals, because a third copy of the
/// same fact is a third place for it to drift — Core and the renderer already
/// have a test holding their two copies in step.
enum ImageConstants {
    static let table: [String: String] = [
        "soft": BuiltInSprite.soft,
        "glow": BuiltInSprite.glow,
        "smoke": BuiltInSprite.smoke,
        "star": BuiltInSprite.star,
        "square": BuiltInSprite.square,
        "streak": BuiltInSprite.streak,
        "ring": BuiltInSprite.ring,
    ]
}

/// The easing curves, by the names osu! gives them.
///
/// The whole set rather than a chosen few: a script is code, so a long list
/// costs nothing to read past — unlike the inspector, where a menu of
/// thirty-five is a menu nobody reads.
enum EaseConstants {
    static let table: [String: Int] = Dictionary(
        uniqueKeysWithValues: Easing.allCases.map { ($0.scriptName, $0.rawValue) },
    )
}

/// Layers and origins, by the names the format uses.
enum LayerConstants {
    static let table: [String: String] = Dictionary(
        uniqueKeysWithValues: Layer.allCases.map { ($0.rawValue, $0.rawValue) },
    )

    static let originTable: [String: String] = Dictionary(
        uniqueKeysWithValues: Origin.allCases.map { ($0.rawValue, $0.rawValue) },
    )
}

private extension Easing {
    /// The name a script uses, which is the enum case as written in Swift.
    ///
    /// Derived from the case rather than spelled out in a second list: a table
    /// of thirty-five hand-written strings is thirty-five chances to typo one,
    /// and the one that is wrong would be a curve nobody could reach.
    var scriptName: String {
        "\(self)"
    }
}
