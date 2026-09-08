import Foundation

/// What a script may produce before its output is cut short.
///
/// Every effect written by hand is self-limiting by construction: the emitter
/// cannot exceed ``EmitterEffect/maximumCount`` because its own parameter range
/// says so, and nothing else can emit at all. A script has no such shape — a
/// loop with the wrong bound produces fifty thousand sprites, each of which is
/// a line in a text file the game has to parse and hold.
///
/// It truncates rather than failing. Two thousand sprites someone can look at
/// and turn down is a result; a blank canvas and an error is a dead end, and
/// the number they need to change is a number they cannot see.
public enum ScriptLimits {
    /// The same number the emitter uses, deliberately.
    ///
    /// Two answers to "how many sprites can one clip hold" would be two numbers
    /// to keep in step, and nothing about a script makes it able to afford more
    /// than an emitter can.
    public static let maximumSprites = EmitterEffect.maximumCount

    /// A generous per-sprite command budget.
    ///
    /// Twenty covers a particle with a full life — move, fade in, fade out,
    /// scale, rotate, a colour ramp and a few segments of curved path — with
    /// room over. It exists to derive the total below rather than to be
    /// enforced per sprite: one sprite carrying two hundred commands is fine as
    /// long as the file as a whole stays sane.
    public static let commandsPerSprite = 20

    /// The ceiling on commands across the whole clip.
    ///
    /// Derived from the two numbers above rather than picked. There was no
    /// command ceiling anywhere in this codebase before, and inventing a round
    /// number would have been a constant nobody could account for.
    public static let maximumCommands = maximumSprites * commandsPerSprite

    /// A script's output, cut to what a storyboard can carry.
    ///
    /// Applied at the bridge, before the clip's transform and before any
    /// filter: a Grid multiplies whatever it is given, so clamping afterwards
    /// would be clamping a number that had already been multiplied by nine.
    public static func clamped(
        _ produced: [StoryboardSprite],
    ) -> (sprites: [StoryboardSprite], diagnostics: [ScriptRuntime.Diagnostic]) {
        var diagnostics: [ScriptRuntime.Diagnostic] = []

        var kept = produced
        if kept.count > maximumSprites {
            diagnostics.append(.spritesTruncated(produced: kept.count, kept: maximumSprites))
            kept = Array(kept.prefix(maximumSprites))
        }

        let commands = kept.reduce(0) { $0 + $1.commands.count }
        guard commands > maximumCommands else {
            return (kept, diagnostics)
        }

        // Cut sprite by sprite, in creation order, keeping whole sprites until
        // the budget runs out. Trimming commands from within a sprite instead
        // would leave it drawing half an animation, which reads as a bug in the
        // script rather than as a limit being hit.
        var budget = maximumCommands
        var trimmed: [StoryboardSprite] = []
        for sprite in kept {
            guard sprite.commands.count <= budget else { break }
            budget -= sprite.commands.count
            trimmed.append(sprite)
        }

        diagnostics.append(.commandsTruncated(
            produced: commands,
            kept: trimmed.reduce(0) { $0 + $1.commands.count },
        ))
        return (trimmed, diagnostics)
    }
}
