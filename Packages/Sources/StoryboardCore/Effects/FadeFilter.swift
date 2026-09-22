import Foundation

/// Fades a whole clip in and out, as one thing.
///
/// One sprite in, one sprite out: the fade multiplies the opacity commands the
/// sprites were carrying anyway, so a clip's entry and exit costs no sprites at
/// all.
///
/// ## Why this is not what an emitter already does
///
/// Every particle an emitter writes is born with its own fade, so *each sprite*
/// softening is already covered. What is not is the **field** arriving and
/// leaving together: making a thousand particles dim at the end of a clip means
/// reaching into a thousand individual fades. So this reads the clip's span and
/// attenuates across it — at 200ms into a 500ms fade-in, everything on screen
/// is at 40%, whenever each sprite happened to be born.
///
/// The alternative reading — each sprite fading over its own life, the way
/// ``TintFilter`` ramps its colour — is deliberately absent. A tint needs it
/// (a ramp spread over the clip would be invisible on a half-second particle);
/// a fade does not, because that case already exists.
public struct FadeFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let fadeIn = "fadeIn"
        public static let fadeOut = "fadeOut"
        public static let curve = "curve"
    }

    /// The same eight curves ``EaseFilter`` names, by what they do rather than
    /// by their polynomial.
    ///
    /// Trimmed to the four that read well on an opacity: a bouncing fade
    /// flickers, and an elastic one flashes past full brightness and back —
    /// which is the reasoning `Ease` already wrote down when it defaulted
    /// `Movement Only` to on.
    public enum Curve: String, CaseIterable, Sendable {
        case linear = "Linear"
        case ease = "Ease In Out"
        case accelerate = "Accelerate"
        case settle = "Settle"

        var easing: Easing {
            switch self {
            case .linear: .linear
            case .ease: .quadInOut
            case .accelerate: .quadIn
            case .settle: .quadOut
            }
        }
    }

    public static let descriptor = FilterDescriptor(
        type: "fade",
        name: "Fade",
        category: .stylise,
        systemImage: "circle.lefthalf.filled",
        parameters: [
            EffectParameter(
                id: Param.fadeIn,
                name: "In",
                group: "Fade",
                // Both ends rest at zero, so dropping the filter on a finished
                // clip changes nothing until someone asks for it. A default
                // that animated would rewrite work already approved.
                defaultValue: .number(0),
                range: 0...5000,
                step: 50,
                unit: "ms",
            ),
            EffectParameter(
                id: Param.fadeOut,
                name: "Out",
                group: "Fade",
                defaultValue: .number(0),
                range: 0...5000,
                step: 50,
                unit: "ms",
            ),
            EffectParameter(
                id: Param.curve,
                name: "Curve",
                group: "Fade",
                defaultValue: .choice(Curve.linear.rawValue),
                options: Curve.allCases.map(\.rawValue),
            ),
        ],
    )

    public func apply(
        to sprites: [StoryboardSprite],
        in context: FilterContext,
    ) -> [StoryboardSprite] {
        let fadeIn = max(0, context.number(Param.fadeIn))
        let fadeOut = max(0, context.number(Param.fadeOut))
        let easing = (Curve(rawValue: context.choice(Param.curve)) ?? .linear).easing

        // Inert at its defaults, and cheaply: a filter resting at zero should
        // cost nothing rather than rewrite every command to multiply by one.
        guard fadeIn > 0 || fadeOut > 0 else { return sprites }

        // The clip's span, read from the sprites — a filter runs in local time
        // and is never told how long its clip is.
        let starts = sprites.flatMap { $0.commands.map(\.startTime) }
        let ends = sprites.flatMap { $0.commands.map(\.endTime) }
        guard let clipStart = starts.min(), let clipEnd = ends.max() else { return sprites }

        // A fade longer than the clip, or two that overlap, would have the
        // ramps fighting over the same instants — and two commands on one
        // property means the last one written wins, not a blend. Scaled down
        // together so their proportion survives.
        let span = clipEnd - clipStart
        guard span > 0 else { return sprites }
        let requested = fadeIn + fadeOut
        let scale = requested > span ? span / requested : 1
        let head = fadeIn * scale
        let tail = fadeOut * scale

        let inEnd = clipStart + head
        let outStart = clipEnd - tail

        // The moments the envelope changes slope. A command spanning one of
        // these is cut there, so the piece either side reads its own ends
        // rather than holding one value across the corner.
        var cuts: [Double] = []
        if head > 0 { cuts.append(inEnd) }
        if tail > 0 { cuts.append(outStart) }

        return sprites.map { sprite in
            var faded = sprite
            let birth = sprite.commands.map(\.startTime).min() ?? clipStart
            let death = sprite.commands.map(\.endTime).max() ?? birth

            faded.commands = AnimatedFactor.apply(
                to: covering(sprite.commands, birth: birth, death: death),
                cutAt: cuts,
            ) { command in
                guard case let .fade(start, end) = command.payload else { return command }
                return Command(
                    easing: command.easing,
                    startTime: command.startTime,
                    endTime: command.endTime,
                    payload: .fade(
                        start: start * envelope(
                            at: command.startTime,
                            inEnd: inEnd, outStart: outStart,
                            clipStart: clipStart, clipEnd: clipEnd,
                            easing: easing,
                        ),
                        end: end * envelope(
                            at: command.endTime,
                            inEnd: inEnd, outStart: outStart,
                            clipStart: clipStart, clipEnd: clipEnd,
                            easing: easing,
                        ),
                    ),
                )
            }
            return faded
        }
    }

    /// How much of its own opacity a sprite keeps at `time`.
    private func envelope(
        at time: Double,
        inEnd: Double, outStart: Double,
        clipStart: Double, clipEnd: Double,
        easing: Easing,
    ) -> Double {
        if time < inEnd, inEnd > clipStart {
            let progress = (time - clipStart) / (inEnd - clipStart)
            return applyEasing(easing, min(1, max(0, progress)))
        }
        if time > outStart, clipEnd > outStart {
            let progress = (clipEnd - time) / (clipEnd - outStart)
            return applyEasing(easing, min(1, max(0, progress)))
        }
        return 1
    }

    /// The sprite's commands, with its opacity guaranteed to span its whole
    /// life.
    ///
    /// The envelope works by *multiplying* the fades a sprite already has, so a
    /// stretch with no fade command over it has nothing to attenuate — and a
    /// sprite that fades in, holds, and fades out has exactly that shape: two
    /// short commands at the ends and a silent middle where its opacity is
    /// simply whatever the last one left.
    ///
    /// This is the bug ``BlurFilter`` already paid for: measured on a text
    /// clip, every glyph carried a fade at `0-40` and another at `6176-6376`,
    /// and the entire middle had none. A fade-out landing in that hole would
    /// have nothing to turn down, and the clip would stay lit.
    private func covering(
        _ commands: [Command], birth: Double, death: Double,
    ) -> [Command] {
        let fades = commands.filter { $0.kind == .fade }.sorted { $0.startTime < $1.startTime }

        // A sprite with no fade at all holds its default opacity for its whole
        // life, so the envelope needs one command to multiply.
        guard let first = fades.first, let last = fades.last else {
            return commands + [Command(
                easing: .linear,
                startTime: birth,
                endTime: death,
                payload: .fade(start: 1, end: 1),
            )]
        }

        var filled = commands

        // Before the sprite's own first fade, for one that starts late.
        if first.startTime > birth + 1, case let .fade(opening, _) = first.payload, opening > 0 {
            filled.append(Command(
                easing: .linear,
                startTime: birth,
                endTime: first.startTime,
                payload: .fade(start: opening, end: opening),
            ))
        }

        // Every gap between consecutive fades, not only the tail: a sprite that
        // fades in, holds and fades out leaves its hole in the *middle*.
        for (earlier, later) in zip(fades, fades.dropFirst()) {
            guard later.startTime > earlier.endTime + 1,
                  case let .fade(_, held) = earlier.payload, held > 0
            else { continue }
            filled.append(Command(
                easing: .linear,
                startTime: earlier.endTime,
                endTime: later.startTime,
                payload: .fade(start: held, end: held),
            ))
        }

        // And the tail, for a sprite whose last fade ends before it does.
        if last.endTime < death - 1, case let .fade(_, held) = last.payload, held > 0 {
            filled.append(Command(
                easing: .linear,
                startTime: last.endTime,
                endTime: death,
                payload: .fade(start: held, end: held),
            ))
        }

        return filled
    }

    public func estimatedMultiplier(in context: FilterContext) -> Double { 1 }
}
