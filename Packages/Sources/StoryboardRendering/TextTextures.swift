import CoreGraphics
import CoreText
import Foundation
import ImageIO
import StoryboardCore
import UniformTypeIdentifiers

/// Draws the glyphs a text effect names.
///
/// The third source of images the app provides itself, alongside built-in
/// shapes and derived blurs, and it reaches the atlas through the same door: a
/// path that names a character and a style, resolved to pixels on demand.
///
/// Glyphs are drawn **white**. Colour is a `_C` command on the sprite, so one
/// texture serves every colour the character is used in — baking the colour in
/// would mean an atlas entry per shade of the same letter.
public enum TextTextures {
    /// Every character a project has asked for, so a path can be resolved back
    /// to what it was made from.
    ///
    /// A path is a hash, and a hash cannot be reversed. Registering what was
    /// hashed is what lets the renderer answer for it later — the alternative
    /// is spelling the character into the path, where a slash or a quote would
    /// have to survive being written into a storyboard file.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var known: [String: (Character, TextStyle)] = [:]
    nonisolated(unsafe) private static var cache: [String: Data] = [:]

    /// Records what a path stands for. Called as sprites are made.
    public static func register(_ character: Character, style: TextStyle) {
        let path = TextSprite.rawPath(for: character, style: style)
        lock.lock()
        known[path] = (character, style)
        lock.unlock()
    }

    /// PNG data for a text path, or `nil` when the path is not one.
    public static func data(for path: String) -> Data? {
        guard TextSprite.isText(path) else { return nil }

        lock.lock()
        let cached = cache[path]
        let entry = known[path]
        lock.unlock()

        if let cached { return cached }
        guard let entry else { return nil }

        guard let made = draw(entry.0, style: entry.1) else { return nil }
        lock.lock()
        cache[path] = made
        lock.unlock()
        return made
    }

    public static func clearCache() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    // ─── Drawing ─────────────────────────────────────────────────────────────

    private static func draw(_ character: Character, style: TextStyle) -> Data? {
        let font = font(for: style)
        let attributed = NSAttributedString(
            string: String(character),
            attributes: [
                .font: font,
                .foregroundColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
            ],
        )

        let line = CTLineCreateWithAttributedString(attributed)

        // Every glyph gets the same box, sized from the font rather than from
        // its own ink.
        //
        // Cropping each character to its ink is what a single glyph wants and
        // exactly wrong for a line of them: a tall character and a short one
        // came out as different-sized textures, and since every sprite is
        // centred on its own texture, they no longer shared a baseline. Text
        // sat unevenly, most visibly in scripts where glyphs vary a lot —
        // Japanese has both full-height and low, wide characters in one line.
        //
        // Sized to the font's own metrics, every texture is the same height and
        // the baseline lands in the same place in all of them, so centring each
        // sprite lines them up.
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let advance = CTLineGetTypographicBounds(line, nil, nil, nil)

        // Padded, because ink can reach past the box — an italic's overhang and
        // a stroke both do — and a texture cropped to it loses those edges.
        let padding = max(4, style.strokeWidth * 2)
        let width = Int((advance + padding * 2).rounded(.up))
        let height = Int((ascent + descent + padding * 2).rounded(.up))
        guard width > 0, height > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else { return nil }

        context.setAllowsAntialiasing(true)
        context.setShouldSmoothFonts(true)
        // The baseline sits `descent` up from the bottom in every texture, which
        // is what makes them line up once each sprite is centred.
        context.textPosition = CGPoint(x: padding, y: padding + descent)
        CTLineDraw(line, context)

        guard let image = context.makeImage() else { return nil }
        return encode(image)
    }

    private static func font(for style: TextStyle) -> CTFont {
        var traits: CTFontSymbolicTraits = []
        if style.isBold { traits.insert(.traitBold) }
        if style.isItalic { traits.insert(.traitItalic) }

        let base = CTFontCreateWithName(style.font as CFString, style.size, nil)
        guard !traits.isEmpty else { return base }
        // Falls back to the plain face when the family has no bold or italic
        // cut: a missing trait is not a reason to draw nothing.
        return CTFontCreateCopyWithSymbolicTraits(base, style.size, nil, traits, traits) ?? base
    }

    private static func encode(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil,
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    // ─── Measurement ─────────────────────────────────────────────────────────

    /// Installs the measurer Core asks for, so text lays out against the real
    /// font rather than the rough fallback.
    public static func install() {
        TextSprite.onUse = { character, style in register(character, style: style) }
        installMetrics()
    }

    public static func installMetrics() {
        TextMetrics.measure = { character, style in
            let font = self.font(for: style)
            let attributed = NSAttributedString(
                string: String(character), attributes: [.font: font],
            )
            let line = CTLineCreateWithAttributedString(attributed)
            // The advance, which is the width the next character starts after —
            // not the ink's width. Laying out by ink crowds narrow glyphs and
            // spreads wide ones, because it ignores the space a font builds
            // into each character.
            let width = CTLineGetTypographicBounds(line, nil, nil, nil)
            return TextMetrics.Glyph(
                width: width,
                height: CTFontGetAscent(font) + CTFontGetDescent(font),
            )
        }
    }
}
