import Foundation

/// Rewrites sprites so the file osu! reads means what the editor's canvas showed.
///
/// The editor's resolver and osu! disagree on two points, and the resolver is
/// pinned by golden tests against the TypeScript engine, so the disagreement is
/// closed on the way OUT instead of by changing it:
///
/// 1. **`S` and `V` are two properties in osu!, one channel here.** The
///    resolver lets the last of them win; osu! keeps both and combines them, so
///    a held `S … 0,0` before a pop-in zeroes a sprite that also carries `V`
///    for its whole life. Measured on a real export: every `V` sprite with a
///    stray `S` was invisible in the game, while a disc using only `S` drew
///    fine. Any sprite with a `V` therefore has all its `S` written as `V`.
/// 2. **A zero-length `P` is permanent here, momentary in osu!.** The wiki says
///    parameter commands apply only while they are active, so a `P,0,t,,V`
///    flips for an instant. The resolver holds it to the sprite's death (or the
///    end of a loop iteration); the file now says so explicitly.
///
/// Kept apart from `OsbWriter` so that stays a faithful formatter — anything it
/// is given, it writes — and the export decides what the file should MEAN.
public enum OsbExportNormalization {
    public static func normalize(_ sprites: [StoryboardSprite]) -> [StoryboardSprite] {
        sprites.map(normalize)
    }

    static func normalize(_ sprite: StoryboardSprite) -> StoryboardSprite {
        let needsVector = usesVectorScale(sprite)
        let needsHold = hasZeroLengthParameter(sprite.commands)
            || sprite.loops.contains { hasZeroLengthParameter($0.commands) }

        // The overwhelming majority of sprites need neither, and copying an
        // emitter's thousands of them for nothing is real time at export.
        guard needsVector || needsHold else { return sprite }

        var result = sprite

        if needsHold {
            // The resolver's own answer to "when does this sprite die": it
            // ignores parameter commands (so a hold cannot lengthen the life it
            // is measured against) and counts loops as start + count × period.
            // Reused rather than re-derived, so the file cannot drift from it.
            let death = StoryboardResolver.prepare([sprite]).first?.activeEnd
            result.commands = held(result.commands, until: death)

            for index in result.loops.indices {
                // A loop body is relative to each iteration, so a hold there
                // runs to the end of THAT iteration — the highest relative end
                // in the body, which is how the resolver sizes one pass.
                let period = result.loops[index].commands.reduce(0.0) { max($0, $1.endTime) }
                result.loops[index].commands = held(result.loops[index].commands, until: period)
            }
        }

        if needsVector {
            result.commands = result.commands.map(vectorised)
            for index in result.loops.indices {
                result.loops[index].commands = result.loops[index].commands.map(vectorised)
            }
        }

        return result
    }

    // ─── S → V ───────────────────────────────────────────────────────────────

    private static func usesVectorScale(_ sprite: StoryboardSprite) -> Bool {
        // A `V` anywhere counts, loop bodies included: osu! combines the two
        // properties across the whole sprite, not per block.
        sprite.commands.contains { $0.kind == .vectorScale }
            || sprite.loops.contains { $0.commands.contains { $0.kind == .vectorScale } }
    }

    private static func vectorised(_ command: Command) -> Command {
        guard case let .scale(start, end) = command.payload else { return command }
        return Command(
            timing: command.timing,
            payload: .vectorScale(startX: start, startY: start, endX: end, endY: end),
        )
    }

    // ─── Zero-length P ───────────────────────────────────────────────────────

    private static func hasZeroLengthParameter(_ commands: [Command]) -> Bool {
        commands.contains { $0.kind == .parameter && $0.startTime == $0.endTime }
    }

    private static func held(_ commands: [Command], until end: Double?) -> [Command] {
        guard let end else { return commands }
        return commands.map { command in
            guard command.kind == .parameter, command.startTime == command.endTime,
                  // A hold that would end at or before its own start has no
                  // room to grow, and the writer would spell it blank again —
                  // the same instant, which is all it can honestly be.
                  end > command.startTime
            else { return command }

            var extended = command
            extended.timing.endTime = end
            return extended
        }
    }
}
