import Foundation

/// Repeats everything on the track.
///
/// The one filter that makes a storyboard *smaller*. osu! has a real loop
/// construct — `_L` with a body written once and an iteration count — so a
/// two-second effect repeated ten times is one copy of the commands and a
/// number, not ten copies. Two hundred particles looped ten times is two
/// hundred sprites rather than two thousand.
///
/// That is also its limit, and the limit has two halves.
///
/// A loop body is relative to each iteration, so every pass is identical: a
/// loop cannot drift, grow, or vary. Anything that should change between
/// repetitions is a longer effect, not a looped one.
///
/// And each pass starts from nothing. A continuous emitter reaches a steady
/// density partway through its clip, but the next iteration begins with an
/// empty screen — so a looped fire visibly thins at every seam. Measured on the
/// fire preset: forty-eight particles before the boundary, twenty after it.
/// ``seamSeverity(of:)`` reports how badly a clip suffers from that, so the
/// editor can say so rather than leaving someone to wonder why their fire
/// flickers every few seconds.
public struct LoopFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let count = "count"
        public static let gap = "gap"
    }

    public static let descriptor = FilterDescriptor(
        type: "loop",
        name: "Loop",
        category: .utility,
        systemImage: "repeat",
        parameters: [
            EffectParameter(
                id: Param.count,
                name: "Repeats",
                group: "Loop",
                defaultValue: .integer(4),
                range: 2...200,
                step: 1,
            ),
            // Silence between passes, for a beat that repeats rather than a
            // stream that never stops.
            EffectParameter(
                id: Param.gap,
                name: "Gap",
                group: "Loop",
                defaultValue: .number(0),
                range: 0...10_000,
                step: 50,
                unit: "ms",
            ),
        ],
    )

    /// Looping adds sprites to the *file* only in that each one grows a loop
    /// block; the sprite count itself does not change.
    public func estimatedMultiplier(in context: FilterContext) -> Double { 1 }

    /// A loop is the one filter that changes how long its clip runs.
    ///
    /// Each pass is the clip plus the gap that follows it, so a gap stretches
    /// the whole thing — which a plain multiplier could not express.
    public func duration(of clipDuration: Double, in context: FilterContext) -> Double {
        let count = Double(max(1, context.integer(Param.count)))
        let gap = max(0, context.number(Param.gap))
        return (clipDuration + gap) * count
    }

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        let count = max(1, context.integer(Param.count))
        let gap = max(0, context.number(Param.gap))
        guard count > 1 else { return sprites }

        // One iteration is the whole clip plus whatever silence follows it.
        // Measured from zero rather than from the first command: two sprites
        // that start at different moments have to keep that relationship, and a
        // per-sprite origin would collapse them onto each other.
        let span = (sprites.flatMap { $0.commands.map(\.endTime) }.max() ?? 0) + gap
        guard span > 0 else { return sprites }

        return sprites.map { sprite in
            var looped = sprite
            // The body is relative to each iteration, which is what a `_L`
            // block means, so the commands go in as they stand.
            var body = sprite.commands

            // Every sprite's iteration has to be the same length.
            //
            // A loop's period is read from the longest command in its own body,
            // so left alone each sprite would repeat on its own schedule — a
            // field of particles would drift apart into noise after the first
            // pass. A zero-opacity hold out to the shared span pins them
            // together, and doubles as the gap: the sprite is simply invisible
            // for the rest of the iteration.
            if let last = body.map(\.endTime).max(), last < span {
                body.append(Command(
                    easing: .linear,
                    startTime: last,
                    endTime: span,
                    payload: .fade(start: 0, end: 0),
                ))
            }

            // And the same at the front, for a sprite that starts partway in.
            //
            // A loop body is replayed from zero every pass, and a sprite with
            // no command over the opening stretch is drawn at its default
            // opacity there — visible. Every particle that had not been born
            // yet appeared at once at the top of each iteration, held, and then
            // the sequence began underneath them.
            //
            // Invisible in the editor and plain in the game: this resolver
            // treats an uncommanded sprite as not yet drawn, and osu! draws it.
            // Agreeing with the stricter of the two is the only safe reading.
            if let first = body.map(\.startTime).min(), first > 0 {
                body.insert(Command(
                    easing: .linear,
                    startTime: 0,
                    endTime: first,
                    payload: .fade(start: 0, end: 0),
                ), at: 0)
            }

            looped.commands = []
            looped.loops = sprite.loops + [LoopGroup(
                startTime: 0,
                loopCount: count,
                commands: body,
            )]
            return looped
        }
    }

    /// How much a clip's density drops at a loop boundary, from 0 to 1.
    ///
    /// A pass begins with an empty screen, so anything still alive at the end
    /// of the previous one is simply gone. A clip whose sprites are short-lived
    /// relative to its own length barely notices; one where most of them are
    /// still running at the end loses most of its density.
    public static func seamSeverity(of sprites: [StoryboardSprite]) -> Double {
        guard !sprites.isEmpty else { return 0 }

        let span = sprites.flatMap { $0.commands.map(\.endTime) }.max() ?? 0
        guard span > 0 else { return 0 }

        // Sprites still running when the clip ends are the ones a loop cuts
        // off, and the ones the next pass has to build back up from nothing.
        let alive = sprites.filter { sprite in
            guard let start = sprite.commands.map(\.startTime).min(),
                  let end = sprite.commands.map(\.endTime).max()
            else { return false }
            return start < span && end >= span - 1
        }

        return Double(alive.count) / Double(sprites.count)
    }
}
