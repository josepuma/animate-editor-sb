@testable import StoryboardCore
import Foundation

/// The one named exception to "phase two moves nothing phase one produced".
///
/// Phase one wrote the Rise and Fall exits as `_MY` from `defaultY`. The
/// resolver lets an axis command override `_M` outright and holds its start
/// before its first command, so a glyph with an `_M` entrance never showed its
/// vertical arrival, and one with Travel Y jumped back as it left. Phase two
/// writes them as `_M` from wherever the glyph is. The oracles stay frozen;
/// this says exactly which cases they no longer describe, and what those cases
/// must now read — everything else is still compared byte for byte.
enum RiseFallFix {
    /// Whether a node's output carries the changed exit.
    ///
    /// Shared by every suite that compares against an oracle, so the excluded
    /// set is stated once: a looser predicate would hide a real regression
    /// behind the exception, a tighter one would fail on the fix itself.
    static func applies(_ values: [String: EffectValue]) -> Bool {
        let merged = TextEffect.descriptor.defaultValues.merging(values) { _, new in new }
        guard case let .choice(exit)? = merged[TextEffect.Param.exit],
              case let .number(fadeOut)? = merged[TextEffect.Param.fadeOut]
        else { return false }
        return ["Rise", "Fall"].contains(exit) && fadeOut > 0
    }

    /// The oracle's sprites with their exit `_MY` replaced by the `_M` phase
    /// two writes: same span, same curve, same 60px, starting from where the
    /// travel left the glyph. Nothing else is touched.
    static func rewrite(
        _ sprites: [StoryboardSprite],
        travel: (x: Double, y: Double),
    ) -> [StoryboardSprite] {
        sprites.map { sprite in
            var sprite = sprite
            sprite.commands = sprite.commands.map { command in
                // Phase one wrote `_MY` nowhere else, so every one is the exit.
                guard case let .moveY(start, end) = command.payload else { return command }
                let x = sprite.defaultX + travel.x
                return Command(
                    timing: command.timing,
                    payload: .move(startX: x, startY: start + travel.y, endX: x, endY: end + travel.y),
                )
            }
            return sprite
        }
    }

    /// The travel a node asks for, as `rewrite` needs it.
    static func travel(_ values: [String: EffectValue]) -> (x: Double, y: Double) {
        let merged = TextEffect.descriptor.defaultValues.merging(values) { _, new in new }
        func number(_ key: String) -> Double {
            if case let .number(value)? = merged[key] { value } else { 0 }
        }
        return (number(TextEffect.Param.driftX), number(TextEffect.Param.driftY))
    }
}
