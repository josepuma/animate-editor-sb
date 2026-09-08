import Foundation

/// What a script can call, as a list.
///
/// The whole reason autocompletion is cheap here: this API is closed and known.
/// There are ten globals, seven built-in images and thirty-five easing curves —
/// no types to infer, no modules to resolve, nothing a language server would
/// have to work out. A table answers every question the editor can ask.
///
/// And it earns its place beyond convenience: a completion list is how somebody
/// finds out `Image.soft` exists. Without one, an author has to already know
/// the name to type it, which makes the documentation the only way in.
public enum ScriptAPI {
    /// One thing a script can write.
    public struct Entry: Equatable, Sendable {
        /// What appears in the list, and what filtering matches against.
        public let name: String
        /// What gets inserted. Differs from `name` for anything callable, which
        /// arrives with its parentheses.
        public let insert: String
        /// One line, shown beside the name.
        public let summary: String
        public let kind: Kind

        public init(name: String, insert: String? = nil, summary: String, kind: Kind) {
            self.name = name
            self.insert = insert ?? name
            self.summary = summary
            self.kind = kind
        }
    }

    public enum Kind: Equatable, Sendable {
        case function
        case value
        case namespace
        case method
        case keyword
    }

    /// What is in scope with nothing typed before it.
    public static let globals: [Entry] = [
        Entry(
            name: "sprite",
            insert: "sprite(",
            summary: "Creates a sprite from an image path",
            kind: .function,
        ),
        Entry(
            name: "duration",
            summary: "The clip's length in milliseconds",
            kind: .value,
        ),
        Entry(
            name: "rng",
            summary: "Reproducible randomness, seeded from the clip",
            kind: .namespace,
        ),
        Entry(
            name: "param",
            insert: "param(",
            summary: "Reads one of the controls this script declared",
            kind: .function,
        ),
        Entry(
            name: "params",
            insert: "params(",
            summary: "Declares the controls this script shows in the inspector",
            kind: .function,
        ),
        Entry(name: "Image", summary: "The images the app provides", kind: .namespace),
        Entry(name: "Ease", summary: "The easing curves osu! supports", kind: .namespace),
        Entry(name: "Layer", summary: "Which layer a sprite draws on", kind: .namespace),
        Entry(name: "Origin", summary: "Which point of a sprite its position means", kind: .namespace),
        Entry(name: "console", summary: "Logging, for working out what a script did", kind: .namespace),
        Entry(name: "Math", summary: "The language's own maths", kind: .namespace),
    ]

    /// `Image.` — the built-in shapes.
    ///
    /// Mirrors `BuiltInSprite` in Core, and the summaries say what each one is
    /// *for* rather than what it looks like: "soft" and "glow" are both round
    /// blurs, and the difference that matters is which one reads as a particle
    /// and which as light.
    public static let images: [Entry] = [
        Entry(name: "soft", summary: "A soft round dot — the default particle", kind: .value),
        Entry(name: "glow", summary: "A tighter, brighter dot — reads as light", kind: .value),
        Entry(name: "smoke", summary: "A soft cloud with body", kind: .value),
        Entry(name: "star", summary: "A four-pointed star", kind: .value),
        Entry(name: "square", summary: "A hard-edged square", kind: .value),
        Entry(name: "streak", summary: "A tapered streak, for anything with direction", kind: .value),
        Entry(name: "ring", summary: "A hollow ring", kind: .value),
    ]

    /// `Ease.` — every curve the format has.
    ///
    /// All thirty-five, because a list is free to scroll past in an editor —
    /// unlike the inspector, where a menu of thirty-five is a menu nobody
    /// reads. The names are the enum cases, so what is typed here is what the
    /// bridge accepts.
    public static let easings: [Entry] = [
        Entry(name: "linear", summary: "No easing — the only curve nothing real follows", kind: .value),
        Entry(name: "out", summary: "Decelerates", kind: .value),
        Entry(name: "in", summary: "Accelerates", kind: .value),
        Entry(name: "inQuad", summary: "Accelerates, gently", kind: .value),
        Entry(name: "outQuad", summary: "Decelerates, gently — a safe default", kind: .value),
        Entry(name: "inOutQuad", summary: "Accelerates then decelerates", kind: .value),
        Entry(name: "inCubic", summary: "Accelerates, harder", kind: .value),
        Entry(name: "outCubic", summary: "Decelerates, harder", kind: .value),
        Entry(name: "inOutCubic", summary: "Both, harder", kind: .value),
        Entry(name: "inQuart", summary: "Accelerates, harder still", kind: .value),
        Entry(name: "outQuart", summary: "Decelerates, harder still", kind: .value),
        Entry(name: "inOutQuart", summary: "Both, harder still", kind: .value),
        Entry(name: "inQuint", summary: "Accelerates sharply", kind: .value),
        Entry(name: "outQuint", summary: "Decelerates sharply", kind: .value),
        Entry(name: "inOutQuint", summary: "Both, sharply", kind: .value),
        Entry(name: "inSine", summary: "Accelerates on a sine curve", kind: .value),
        Entry(name: "outSine", summary: "Decelerates on a sine curve", kind: .value),
        Entry(name: "inOutSine", summary: "A smooth S — good for anything that sways", kind: .value),
        Entry(name: "inExpo", summary: "Accelerates exponentially", kind: .value),
        Entry(name: "outExpo", summary: "Decelerates exponentially — a hard stop", kind: .value),
        Entry(name: "inOutExpo", summary: "Both, exponentially", kind: .value),
        Entry(name: "inCirc", summary: "Accelerates on a circular arc", kind: .value),
        Entry(name: "outCirc", summary: "Decelerates on a circular arc", kind: .value),
        Entry(name: "inOutCirc", summary: "Both, circular", kind: .value),
        Entry(name: "inElastic", summary: "Winds up before moving", kind: .value),
        Entry(name: "outElastic", summary: "Overshoots and springs back", kind: .value),
        Entry(name: "outElasticHalf", summary: "Springs back, half as far", kind: .value),
        Entry(name: "outElasticQuarter", summary: "Springs back, a quarter as far", kind: .value),
        Entry(name: "inOutElastic", summary: "Winds up, overshoots, settles", kind: .value),
        Entry(name: "inBack", summary: "Pulls back before going", kind: .value),
        Entry(name: "outBack", summary: "Goes past and returns", kind: .value),
        Entry(name: "inOutBack", summary: "Pulls back, overshoots, settles", kind: .value),
        Entry(name: "inBounce", summary: "Bounces into the start", kind: .value),
        Entry(name: "outBounce", summary: "Bounces on landing", kind: .value),
        Entry(name: "inOutBounce", summary: "Bounces at both ends", kind: .value),
    ]

    /// What a sprite builder answers to.
    ///
    /// The signatures are in the summaries because a completion list is where
    /// anyone finds out the easing argument is optional — and that the times
    /// come before the values, which is the order the format itself uses and
    /// the one most easily got backwards.
    public static let spriteMethods: [Entry] = [
        Entry(
            name: "fade",
            insert: "fade(",
            summary: "(ease?, from, to, startOpacity, endOpacity)",
            kind: .method,
        ),
        Entry(
            name: "move",
            insert: "move(",
            summary: "(ease?, from, to, startX, startY, endX, endY)",
            kind: .method,
        ),
        Entry(
            name: "scale",
            insert: "scale(",
            summary: "(ease?, from, to, startScale, endScale)",
            kind: .method,
        ),
        Entry(
            name: "rotate",
            insert: "rotate(",
            summary: "(ease?, from, to, startRadians, endRadians)",
            kind: .method,
        ),
        Entry(
            name: "at",
            insert: "at(",
            summary: "(x, y) — where the sprite sits before it moves",
            kind: .method,
        ),
    ]

    /// What `rng.` answers to.
    public static let randomMethods: [Entry] = [
        Entry(name: "unit", insert: "unit()", summary: "A number in [0, 1)", kind: .method),
        Entry(name: "between", insert: "between(", summary: "(low, high) — a number in between", kind: .method),
        Entry(name: "integer", insert: "integer(", summary: "(low, high) — a whole number, inclusive", kind: .method),
    ]

    public static let layers: [Entry] = [
        Entry(name: "Background", summary: "Behind everything", kind: .value),
        Entry(name: "Fail", summary: "Only while the player is failing", kind: .value),
        Entry(name: "Pass", summary: "Only while the player is passing", kind: .value),
        Entry(name: "Foreground", summary: "The usual one", kind: .value),
        Entry(name: "Overlay", summary: "In front of everything", kind: .value),
    ]

    public static let origins: [Entry] = [
        Entry(name: "TopLeft", summary: "", kind: .value),
        Entry(name: "TopCentre", summary: "", kind: .value),
        Entry(name: "TopRight", summary: "", kind: .value),
        Entry(name: "CentreLeft", summary: "", kind: .value),
        Entry(name: "Centre", summary: "The usual one", kind: .value),
        Entry(name: "CentreRight", summary: "", kind: .value),
        Entry(name: "BottomLeft", summary: "", kind: .value),
        Entry(name: "BottomCentre", summary: "", kind: .value),
        Entry(name: "BottomRight", summary: "", kind: .value),
    ]

    public static let consoleMethods: [Entry] = [
        Entry(name: "log", insert: "log(", summary: "(value) — for working out what a script did", kind: .method),
        Entry(name: "warn", insert: "warn(", summary: "(value)", kind: .method),
        Entry(name: "error", insert: "error(", summary: "(value)", kind: .method),
    ]

    /// The members of a namespace, by its name.
    public static func members(of namespace: String) -> [Entry] {
        switch namespace {
        case "Image": images
        case "Ease": easings
        case "Layer": layers
        case "Origin": origins
        case "rng": randomMethods
        case "console": consoleMethods
        default: []
        }
    }
}
