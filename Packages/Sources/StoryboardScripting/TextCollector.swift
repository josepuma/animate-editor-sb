import Foundation
import JavaScriptCore
import StoryboardCore

/// Installs `text(string, options?)`, which hands a script one builder per
/// character.
///
/// **One sprite per glyph, not one per line**, and that is the whole reason
/// this exists rather than a single text sprite: letters arriving one after
/// another, rising, spinning, scattering. A sprite carrying a whole word can
/// only move as a word — that is a subtitle, not motion graphics.
///
/// The cost is real and worth naming: a forty-character line is forty sprites,
/// each with its commands in the file. Long paragraphs are not for this.
///
/// What a script gets back is a **list of builders already positioned**, so it
/// can give each letter its own rule — which is exactly what a parameter cannot
/// express and why `ScriptEffect` exists at all. Laying the line out here
/// rather than in the script is not a convenience: the advance widths come from
/// a font, and `StoryboardCore` cannot open one.
final class TextCollector {
    private let sprites: SpriteCollector

    init(sprites: SpriteCollector) {
        self.sprites = sprites
    }

    func install(in context: JSContext) {
        // Captured strongly, for the same reason `sprite()` is: the context
        // holds the block and the collector has to outlive every call a script
        // makes. Held weakly it was released before the script ran, and
        // JavaScriptCore reports that as `undefined is not an object` at the
        // call site — pointing at the script rather than at the bridge.
        let make: @convention(block) (String, JSValue?) -> JSValue? = { string, options in
            guard let context = JSContext.current() else { return nil }
            guard string != "undefined", string != "null" else {
                self.sprites.undefinedArgument = true
                return JSValue(newArrayIn: context)
            }
            return self.line(string, options: options, in: context)
        }
        context.setObject(make, forKeyedSubscript: "text" as NSString)
    }

    private func line(_ string: String, options: JSValue?, in context: JSContext) -> JSValue? {
        let style = self.style(from: options)
        let tracking = number("tracking", from: options) ?? 0
        let centre = (
            x: number("x", from: options) ?? 320,
            y: number("y", from: options) ?? 240
        )

        // Laid out on the **advance**, not on the ink.
        //
        // Packing by ink crowds the narrow glyphs and spaces out the wide ones,
        // because it throws away the room the font builds into each character.
        let glyphs = Array(string)
        let advances = glyphs.map { TextMetrics.glyph($0, style: style).width + tracking }
        let total = advances.reduce(0, +) - (glyphs.isEmpty ? 0 : tracking)

        // Around the centre, because a clip's transform rotates and scales
        // about that point: text laid out from one corner would sweep one end
        // through an arc when turned.
        var cursor = centre.x - total / 2

        guard let array = JSValue(newArrayIn: context) else { return nil }
        var index = 0

        for (glyph, advance) in zip(glyphs, advances) {
            let x = cursor + advance / 2
            cursor += advance

            // A space has an advance and no ink, so a sprite for it is a sprite
            // drawing nothing — and every one of them costs a line in the file.
            guard !glyph.isWhitespace else { continue }

            let builder = sprites.builder(
                path: TextSprite.path(for: glyph, style: style),
                options: options,
                in: context,
                at: (x: x, y: centre.y),
            )
            guard let builder else { continue }

            // The glyph's own size, so a script can space, stack or scale
            // around what it actually drew rather than guessing from the point
            // size — which is never the width of a character.
            let measured = TextMetrics.glyph(glyph, style: style)
            builder.setObject(measured.width, forKeyedSubscript: "width" as NSString)
            builder.setObject(measured.height, forKeyedSubscript: "height" as NSString)
            builder.setObject(x, forKeyedSubscript: "x" as NSString)
            builder.setObject(centre.y, forKeyedSubscript: "y" as NSString)
            builder.setObject(String(glyph), forKeyedSubscript: "character" as NSString)

            array.setObject(builder, atIndexedSubscript: index)
            index += 1
        }

        return array
    }

    private func style(from options: JSValue?) -> TextStyle {
        TextStyle(
            font: string("font", from: options) ?? "Helvetica",
            size: number("size", from: options) ?? 48,
            isBold: bool("bold", from: options) ?? false,
            isItalic: bool("italic", from: options) ?? false,
            strokeWidth: number("strokeWidth", from: options) ?? 0,
        )
    }

    /// Reads one option, treating a key written wrong as an error.
    ///
    /// An option nobody wrote is fine; one written wrong is not. The
    /// distinction is whether the **key** is present — checking only for
    /// `undefined` treats a typo as an absent option and silently hands back a
    /// default, which is how `Ease.outQuad` once animated as linear.
    private func value(_ name: String, from options: JSValue?) -> JSValue? {
        guard let options, options.isObject else { return nil }
        guard let value = options.forProperty(name) else { return nil }
        guard !value.isUndefined, !value.isNull else {
            if options.hasProperty(name) { sprites.undefinedArgument = true }
            return nil
        }
        return value
    }

    private func number(_ name: String, from options: JSValue?) -> Double? {
        guard let value = value(name, from: options) else { return nil }
        let number = value.toDouble()
        // A NaN written on purpose is arithmetic somebody may have meant; a NaN
        // reaching `Int` further down is a **trap** that takes the editor with
        // it. Rejected here rather than clamped, so the default applies.
        return number.isFinite ? number : nil
    }

    private func string(_ name: String, from options: JSValue?) -> String? {
        value(name, from: options)?.toString()
    }

    private func bool(_ name: String, from options: JSValue?) -> Bool? {
        value(name, from: options)?.toBool()
    }
}
