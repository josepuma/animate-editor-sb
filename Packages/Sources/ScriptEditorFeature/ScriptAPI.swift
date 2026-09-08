import Foundation
import StoryboardCore

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

        /// A line of real code, for the documentation pane.
        ///
        /// The library reserves that pane a hundred points whether anything is
        /// in it or not — `minHeight: 100`, hardcoded — so showing the
        /// signature there, which is already in the row beside the name,
        /// spends the space saying nothing twice. An example answers what a
        /// signature cannot: what the numbers actually mean in place.
        public let example: String?

        public let kind: Kind

        public init(
            name: String,
            insert: String? = nil,
            summary: String,
            example: String? = nil,
            kind: Kind,
        ) {
            self.name = name
            self.insert = insert ?? name
            self.summary = summary
            self.example = example
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
            example: """
            // A built-in shape, or any file in the beatmap folder.
            sprite(Image.soft)
            sprite('sb/particle.png')

            // With a layer and an origin, both optional.
            sprite('sb/bar.png', { layer: Layer.Overlay, origin: Origin.TopLeft })
            """,
            kind: .function,
        ),
        Entry(
            name: "duration",
            summary: "The clip's length in milliseconds",
            example: """
            // Time is LOCAL: 0 is where the clip starts, whatever the
            // timeline says. Dragging the clip moves what this made.
            sprite(Image.soft).fade(0, duration, 0, 1)
            """,
            kind: .value,
        ),
        Entry(
            name: "rng",
            summary: "Reproducible randomness, seeded from the clip",
            example: """
            rng.unit()            // 0 up to 1
            rng.between(0, 640)   // a position
            rng.integer(1, 6)     // a whole number, both ends included

            // Seeded from the clip, so it gives the same field every time —
            // which is what keeps the preview and the exported .osb agreeing.
            """,
            kind: .namespace,
        ),
        Entry(
            name: "param",
            insert: "param(",
            summary: "Reads one of the controls this script declared",
            example: """
            const count = param('count')
            for (let i = 0; i < count; i++) sprite(Image.soft)
            """,
            kind: .function,
        ),
        Entry(
            name: "params",
            insert: "params(",
            summary: "Declares the controls this script shows in the inspector",
            example: """
            // Declared once, at the top. They appear in the inspector as
            // real controls, and `param(id)` reads them back.
            params({
              count: { type: 'integer', default: 24, range: [1, 200] },
              tint:  { type: 'color',   default: '#ff8844' },
            })
            """,
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
    /// Derived from `Easing.allCases` rather than written out. The hand-written
    /// version had all thirty-five names **backwards** — `outQuad` where the
    /// enum says `quadOut` — so completion offered names the runtime rejects,
    /// and choosing one produced a script that silently fell back to linear.
    /// A duplicated list with nothing tying it to its source is a list that
    /// drifts, and this one shipped already drifted.
    ///
    /// All thirty-five, because a list is free to scroll past in an editor —
    /// unlike the inspector, where a menu of thirty-five is a menu nobody
    /// reads.
    public static let easings: [Entry] = Easing.allCases.map { easing in
        Entry(name: "\(easing)", summary: easing.summary, kind: .value)
    }

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
            example: "sprite(Image.soft).fade(0, 300, 0, 1)",
            kind: .method,
        ),
        Entry(
            name: "move",
            insert: "move(",
            summary: "(ease?, from, to, startX, startY, endX, endY)",
            example: "sprite(Image.soft).move(Ease.quadOut, 0, 900, 320, 240, 500, 100)",
            kind: .method,
        ),
        Entry(
            name: "scale",
            insert: "scale(",
            summary: "(ease?, from, to, startScale, endScale)",
            example: "sprite(Image.soft).scale(0, 600, 0.2, 1)",
            kind: .method,
        ),
        Entry(
            name: "rotate",
            insert: "rotate(",
            summary: "(ease?, from, to, startRadians, endRadians)",
            example: "sprite(Image.soft).rotate(0, 900, 0, Math.PI * 2)",
            kind: .method,
        ),
        Entry(
            name: "moveX",
            insert: "moveX(",
            summary: "(ease?, from, to, startX, endX) — one axis, half the cost",
            example: "sprite(Image.soft).moveX(0, 900, 320, 500)",
            kind: .method,
        ),
        Entry(
            name: "moveY",
            insert: "moveY(",
            summary: "(ease?, from, to, startY, endY) — one axis, half the cost",
            example: "sprite(Image.soft).moveY(0, 900, 240, 100)",
            kind: .method,
        ),
        Entry(
            name: "scaleVec",
            insert: "scaleVec(",
            summary: "(ease?, from, to, startX, startY, endX, endY) — stretch per axis",
            example: "sprite(Image.square).scaleVec(0, 1, 854, 80, 854, 80)",
            kind: .method,
        ),
        Entry(
            name: "color",
            insert: "color(",
            summary: "(ease?, from, to, r, g, b, r, g, b) — channels in 0–255",
            example: "sprite(Image.soft).color(0, 900, 255, 190, 90, 200, 40, 20)",
            kind: .method,
        ),
        Entry(
            name: "at",
            insert: "at(",
            summary: "(x, y) — where the sprite sits before it moves",
            example: "sprite(Image.soft).at(320, 240)",
            kind: .method,
        ),
        Entry(
            name: "additive",
            insert: "additive(",
            summary: "(from, to) — adds light instead of covering",
            example: "sprite(Image.glow).additive(0, duration)",
            kind: .method,
        ),
        Entry(
            name: "flipH",
            insert: "flipH(",
            summary: "(from, to) — mirrors horizontally",
            example: "sprite('sb/arrow.png').flipH(0, duration)",
            kind: .method,
        ),
        Entry(
            name: "flipV",
            insert: "flipV(",
            summary: "(from, to) — mirrors vertically",
            example: "sprite('sb/arrow.png').flipV(0, duration)",
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

private extension Easing {
    /// One line about what the curve does.
    ///
    /// Grouped by family rather than written per case: thirty-five hand-written
    /// summaries are thirty-five chances to describe one wrongly, and what
    /// distinguishes them within a family is only how hard they pull.
    var summary: String {
        switch self {
        case .linear: return "No easing — the only curve nothing real follows"
        case .out: return "Decelerates"
        case .in: return "Accelerates"
        default:
            let name = "\(self)"
            let shape = if name.hasSuffix("InOut") {
                "accelerates then decelerates"
            } else if name.hasSuffix("Out") {
                "decelerates"
            } else {
                "accelerates"
            }
            return "\(family) — \(shape)"
        }
    }

    private var family: String {
        let name = "\(self)"
        if name.hasPrefix("quad") { return "Gently" }
        if name.hasPrefix("cubic") { return "Harder" }
        if name.hasPrefix("quart") { return "Harder still" }
        if name.hasPrefix("quint") { return "Sharply" }
        if name.hasPrefix("sine") { return "On a sine curve" }
        if name.hasPrefix("expo") { return "Exponentially" }
        if name.hasPrefix("circ") { return "On a circular arc" }
        if name.hasPrefix("elastic") { return "Springs past and settles" }
        if name.hasPrefix("back") { return "Overshoots" }
        if name.hasPrefix("bounce") { return "Bounces" }
        return ""
    }
}
