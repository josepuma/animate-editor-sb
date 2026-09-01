import Foundation

/// How a character is drawn.
///
/// Kept in Core, where no font can actually be rendered, because the style is
/// what a text effect stores and what its sprite paths are keyed by. Drawing
/// happens at the edge, the same way built-in shapes and derived blurs do.
public struct TextStyle: Sendable, Equatable, Codable {
    public var font: String
    public var size: Double
    public var isBold: Bool
    public var isItalic: Bool
    /// Outline thickness in points. Zero draws no outline.
    public var strokeWidth: Double

    public init(
        font: String = "Helvetica",
        size: Double = 48,
        isBold: Bool = false,
        isItalic: Bool = false,
        strokeWidth: Double = 0,
    ) {
        self.font = font
        self.size = size
        self.isBold = isBold
        self.isItalic = isItalic
        self.strokeWidth = strokeWidth
    }
}

/// The synthetic paths a text effect points its sprites at.
///
/// A character is not a file anyone has: it is drawn on demand, exactly like
/// `__builtin__` shapes and `__derived__` blurs, and reaches the atlas through
/// the same door. The path carries everything needed to draw it, so the same
/// character in the same style resolves to one image however many sprites name
/// it — a paragraph of repeated letters costs one texture each, not one per
/// occurrence.
///
/// Colour is deliberately **not** part of the path: it is applied per sprite
/// with a `_C` command, so one white glyph serves every colour it is drawn in.
/// Baking colour into the texture would make an atlas entry per shade.
public enum TextSprite {
    public static let prefix = "__text__/"

    /// Told whenever a character is used, so whoever draws glyphs can resolve
    /// a path back to what made it.
    ///
    /// A path is a hash and a hash cannot be reversed. Core cannot call the
    /// renderer, so the renderer leaves a hook here instead.
    nonisolated(unsafe) public static var onUse: (@Sendable (Character, TextStyle) -> Void)?

    /// The path for one character in one style.
    public static func path(for character: Character, style: TextStyle) -> String {
        onUse?(character, style)
        return rawPath(for: character, style: style)
    }

    public static func rawPath(for character: Character, style: TextStyle) -> String {
        // Hashed rather than spelled out: a path holding the character itself
        // would need escaping for slashes, quotes and spaces, and a storyboard
        // path is written into a text file where those are all significant.
        let descriptor = "\(character)|\(style.font)|\(style.size)"
            + "|\(style.isBold)|\(style.isItalic)|\(style.strokeWidth)"
        return "\(prefix)\(hash(descriptor)).png"
    }

    public static func isText(_ path: String) -> Bool {
        path.hasPrefix(prefix)
    }

    /// djb2, which is what the TypeScript side already uses for the same job.
    ///
    /// The two never compare hashes, but a storyboard written by one and opened
    /// by the other should name its glyphs the same way.
    private static func hash(_ string: String) -> String {
        var hash: UInt32 = 5381
        for byte in Array(string.utf8) {
            hash = ((hash << 5) &+ hash) ^ UInt32(byte)
        }
        return String(format: "%08x", hash)
    }
}

/// Measures glyphs for whoever lays text out.
///
/// Core cannot open a font, so the one thing it needs from the outside is how
/// wide each character is. Injected rather than reached for, which keeps the
/// effect testable with a stub and keeps the platform out of the domain.
///
/// The fallback is deliberate: a layout with rough widths still places its
/// characters in order and still animates, which is a great deal better than a
/// text effect that draws nothing because no measurer was installed.
public enum TextMetrics {
    public struct Glyph: Sendable, Equatable {
        public var width: Double
        public var height: Double

        public init(width: Double, height: Double) {
            self.width = width
            self.height = height
        }
    }

    /// Installed once by whoever can draw text.
    nonisolated(unsafe) public static var measure: (@Sendable (Character, TextStyle) -> Glyph)?

    public static func glyph(_ character: Character, style: TextStyle) -> Glyph {
        if let measure { return measure(character, style) }
        // Rough, but ordered and animatable.
        return Glyph(width: style.size * 0.55, height: style.size)
    }
}
