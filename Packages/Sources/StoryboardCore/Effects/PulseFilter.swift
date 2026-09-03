import Foundation

/// Makes whatever is on the track beat with the song.
///
/// The filter that connects the editor to the music, which is what a storyboard
/// for a rhythm game is *for*. The map already states its tempo — the timing
/// points are parsed the moment a folder is opened — so a pulse asks for none
/// of it: no BPM to copy, no offset to line up by ear, no drift over five
/// minutes because a number was typed to two decimal places.
///
/// **A filter and not an effect**, though it was written as one first. "Beats
/// with the music" is a *behaviour*, not a thing: as an effect it could only
/// pulse a disc of its own, while as a filter it pulses the logo, the title,
/// the particle field — whatever is already there. The disc is still available,
/// because a Shape with this on it is exactly that.
public struct PulseFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let every = "every"
        public static let bpm = "bpm"
        public static let punch = "punch"
        public static let decay = "decay"
        public static let bounce = "bounce"
        public static let release = "release"
        public static let expand = "expand"
    }

    /// The shape of the fall back to rest.
    ///
    /// The single number that separates a heartbeat from a bouncing ball. A
    /// pulse is a hit and a settle, and *how* it settles is the whole
    /// character: `Out` lands and eases down, `Elastic` overshoots and rings,
    /// `Bounce` lands twice. Written as a choice rather than left to taste
    /// because these are the four curves the format actually has for it.
    public enum Fall: String, CaseIterable, Sendable {
        case smooth = "Smooth"
        case snap = "Snap"
        case elastic = "Elastic"
        case bounce = "Bounce"

        var easing: Easing {
            switch self {
            case .smooth: .out
            case .snap: .expoOut
            case .elastic: .elasticOut
            case .bounce: .bounceOut
            }
        }
    }

    /// How often it fires, in beats.
    ///
    /// Named in beats rather than milliseconds because that is the unit the
    /// song is written in: "every two beats" survives a tempo change and
    /// "every 923ms" does not.
    public enum Interval: String, CaseIterable, Sendable {
        case half = "Half Beat"
        case everyBeat = "Every Beat"
        case everyTwo = "Every 2 Beats"
        case everyFour = "Every 4 Beats"
        case everyBar = "Every Bar"

        var beats: Double {
            switch self {
            case .half: 0.5
            case .everyBeat: 1
            case .everyTwo: 2
            case .everyFour, .everyBar: 4
            }
        }
    }

    public static let descriptor = FilterDescriptor(
        type: "pulse",
        name: "Beat Pulse",
        category: .audio,
        systemImage: "waveform.path.ecg",
        parameters: [
            EffectParameter(
                id: Param.every,
                name: "Interval",
                group: "Beat",
                defaultValue: .choice(Interval.everyBeat.rawValue),
                options: Interval.allCases.map(\.rawValue),
            ),
            // Zero means "follow the song", which is what it does whenever
            // there is one.
            //
            // Visible rather than hidden: a map may have no timing points at
            // all, and a pulse deliberately off the beat is a real thing to
            // want. Left as an invisible fallback, neither was reachable — and
            // a value the app is using is a value the author should be able to
            // see and override.
            EffectParameter(
                id: Param.bpm,
                name: "BPM",
                group: "Beat",
                defaultValue: .number(0),
                range: 0...400,
                step: 1,
            ),
            // How much larger it gets on the hit.
            //
            // A multiplier on whatever size the subject already is, rather than
            // an absolute: what anyone adjusts is *how hard it kicks*, and that
            // should not change the moment the sprite is resized.
            EffectParameter(
                id: Param.punch,
                name: "Punch",
                group: "Beat",
                defaultValue: .number(0.35),
                range: 0...2,
                step: 0.05,
                presentation: .slider,
            ),
            // How much of the interval the pulse takes to settle.
            //
            // A fraction rather than a duration, so it keeps its shape when the
            // tempo changes: a decay written in milliseconds is a different
            // feel at 120 BPM than at 180.
            EffectParameter(
                id: Param.decay,
                name: "Decay",
                group: "Beat",
                defaultValue: .number(0.6),
                range: 0.05...1,
                step: 0.05,
                presentation: .slider,
            ),
            // Which way the beat goes.
            //
            // A pulse and a shockwave are the same command read backwards. A
            // beat hits large and settles back — a heart, a logo, something
            // alive. A wave starts at rest and opens outward, and is gone by
            // the time it stops: it is not the subject beating, it is
            // something leaving it.
            //
            // One flag rather than two filters, because everything else about
            // them — the tempo, the interval, the curve, the release — is
            // identical, and two entries almost the same force a choice with
            // nothing to base it on.
            EffectParameter(
                id: Param.expand,
                name: "Expand",
                group: "Beat",
                defaultValue: .toggle(false),
            ),
            EffectParameter(
                id: Param.bounce,
                name: "Fall",
                group: "Beat",
                defaultValue: .choice(Fall.smooth.rawValue),
                options: Fall.allCases.map(\.rawValue),
            ),
            // How far the opacity drops between hits.
            //
            // The other half of a beat: something that only grows and shrinks
            // reads as breathing, while something that also dims reads as
            // being *struck*. Zero by default because a subject that fades on
            // its own schedule is a surprise nobody asked for — this is opt-in,
            // the way the punch is not.
            EffectParameter(
                id: Param.release,
                name: "Release",
                group: "Beat",
                defaultValue: .number(0),
                range: 0...1,
                step: 0.05,
                presentation: .slider,
            ),
        ],
    )

    /// A scale command between two multiples of the sprite's own size.
    ///
    /// Multiples rather than absolutes, because what the subject already is
    /// stays the subject's business: a bar drawn at 854×100 has to beat as a
    /// bar. `_S` when both axes agree and `_V` only when they differ — a
    /// uniform scale said as a vector is two numbers where one would do, and a
    /// storyboard pays for every number it carries.
    private static func scale(
        of resting: (x: Double, y: Double),
        from start: Double,
        to end: Double,
    ) -> Command.Payload {
        if abs(resting.x - resting.y) < 0.0001 {
            return .scale(start: resting.x * start, end: resting.x * end)
        }
        return .vectorScale(
            startX: resting.x * start,
            startY: resting.y * start,
            endX: resting.x * end,
            endY: resting.y * end,
        )
    }

    /// Tempo used when there is no song to follow and none was given.
    private static let fallbackBPM: Double = 120

    /// One sprite in, one sprite out: the beat is written into the commands
    /// each sprite already has.
    public func estimatedMultiplier(in context: FilterContext) -> Double { 1 }

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        let interval = Interval(rawValue: context.choice(Param.every)) ?? .everyBeat
        let punch = context.number(Param.punch)
        let decay = min(max(context.number(Param.decay), 0.05), 1)
        let fall = Fall(rawValue: context.choice(Param.bounce)) ?? .smooth
        let release = min(max(context.number(Param.release), 0), 1)
        let expand = context.toggle(Param.expand)

        // Either axis alone is a pulse; neither is nothing to do.
        guard punch > 0 || release > 0, !sprites.isEmpty else { return sprites }

        let birth = sprites.flatMap { $0.commands.map(\.startTime) }.min() ?? 0
        let death = sprites.flatMap { $0.commands.map(\.endTime) }.max() ?? birth
        guard death > birth else { return sprites }

        let hits = beats(in: context, from: birth, to: death, every: interval)
        guard !hits.isEmpty else { return sprites }

        return sprites.map { sprite in
            pulsed(
                sprite,
                at: hits,
                until: death,
                punch: punch,
                decay: decay,
                fall: fall,
                release: release,
                expand: expand,
            )
        }
    }

    /// One sprite, beating.
    ///
    /// The scale it already had is the size it settles back to — read rather
    /// than assumed, so a pulse on a sprite drawn at half size kicks from half
    /// size rather than snapping to full.
    private func pulsed(
        _ sprite: StoryboardSprite,
        at hits: [Double],
        until death: Double,
        punch: Double,
        decay: Double,
        fall: Fall,
        release: Double,
        expand: Bool,
    ) -> StoryboardSprite {
        var result = sprite
        var beats: [Command] = []
        var fades: [Command] = []

        for (index, hit) in hits.enumerated() {
            let next = index + 1 < hits.count ? hits[index + 1] : death
            let settle = min(hit + (next - hit) * decay, death)
            guard settle > hit else { continue }

            if punch > 0 {
                let resting = restingScale(of: sprite, at: hit)
                beats.append(Command(
                    // The chosen curve, never linear: a linear ramp reads as a
                    // slide rather than as a hit.
                    easing: fall.easing,
                    startTime: hit,
                    endTime: settle,
                    payload: expand
                        // Out from rest: the wave is born the size the subject
                        // is and opens past it.
                        ? Self.scale(of: resting, from: 1, to: 1 + punch)
                        : Self.scale(of: resting, from: 1 + punch, to: 1),
                ))
            }

            if release > 0 {
                // Full at the hit, down to the floor by the time it settles,
                // and held there until the next one.
                //
                // The floor is a fraction of the sprite's own opacity rather
                // than of one: a subject already fading in has to keep fading
                // in, and a pulse that jumped it to full brightness on every
                // beat would undo its own entrance.
                let peak = restingOpacity(of: sprite, at: hit)
                let floor = peak * (1 - release)

                fades.append(Command(
                    easing: fall.easing,
                    startTime: hit,
                    endTime: settle,
                    payload: .fade(start: peak, end: floor),
                ))
                if next > settle {
                    fades.append(Command(
                        easing: .linear,
                        startTime: settle,
                        endTime: min(next, death),
                        payload: .fade(start: floor, end: floor),
                    ))
                }
            }
        }

        guard !beats.isEmpty || !fades.isEmpty else { return sprite }

        // The beats replace the scale rather than joining it.
        //
        // Two scale commands overlapping in time fight over the same property
        // and one wins at each instant — the same collision the wiggle had with
        // movement. Held between hits at the size the sprite was, so the gaps
        // are not left to a default nobody chose.
        var held: [Command] = []
        var previousEnd = sprite.commands.map(\.startTime).min() ?? 0
        for beat in beats {
            if beat.startTime > previousEnd {
                let resting = restingScale(of: sprite, at: previousEnd)
                held.append(Command(
                    easing: .linear,
                    startTime: previousEnd,
                    endTime: beat.startTime,
                    payload: Self.scale(of: resting, from: 1, to: 1),
                ))
            }
            previousEnd = beat.endTime
        }
        if previousEnd < death {
            let resting = restingScale(of: sprite, at: previousEnd)
            held.append(Command(
                easing: .linear,
                startTime: previousEnd,
                endTime: death,
                payload: Self.scale(of: resting, from: 1, to: 1),
            ))
        }

        if !beats.isEmpty {
            result.commands.removeAll { $0.kind == .scale || $0.kind == .vectorScale }
            result.commands += beats + held
        }

        // Same collision, same answer: two fades overlapping in time fight over
        // one property and one wins at each instant, so the beat has to take
        // the opacity over rather than sit beside what was there.
        //
        // Only the stretch it actually covers, though — an entrance before the
        // first hit is left alone, so a clip still fades in the way it was
        // written and only then starts to beat.
        if let opening = fades.first?.startTime, !fades.isEmpty {
            result.commands.removeAll { $0.kind == .fade && $0.endTime > opening }
            if let entry = sprite.commands.filter({ $0.kind == .fade && $0.startTime < opening }).last,
               case let .fade(_, end) = entry.payload,
               entry.endTime < opening {
                // Held from where the entrance left off, so the gap between it
                // and the first beat is not left to a default nobody chose.
                result.commands.append(Command(
                    easing: .linear,
                    startTime: entry.endTime,
                    endTime: opening,
                    payload: .fade(start: end, end: end),
                ))
            }
            result.commands += fades
        }

        return result
    }

    /// What the sprite's own commands say its scale is at a moment, per axis.
    ///
    /// Both axes, because a sprite may be stretched — and a pulse that read one
    /// number and wrote a uniform `_S` would quietly square it: a 854×100 bar
    /// with a beat on it came back as a block. What the subject is stays the
    /// subject's business; the pulse only multiplies it.
    private func restingScale(of sprite: StoryboardSprite, at time: Double) -> (x: Double, y: Double) {
        var scale = (x: 1.0, y: 1.0)

        for command in sprite.commands {
            guard command.startTime <= time else { continue }
            let span = command.endTime - command.startTime
            let progress = span > 0 ? min(1, (time - command.startTime) / span) : 1

            switch command.payload {
            case let .scale(start, end):
                let value = start + (end - start) * progress
                scale = (value, value)
            case let .vectorScale(startX, startY, endX, endY):
                scale = (
                    startX + (endX - startX) * progress,
                    startY + (endY - startY) * progress,
                )
            default:
                continue
            }
        }

        return scale
    }

    /// What the sprite's own commands say its opacity is at a moment.
    private func restingOpacity(of sprite: StoryboardSprite, at time: Double) -> Double {
        var opacity = 1.0

        for command in sprite.commands {
            guard command.startTime <= time, case let .fade(start, end) = command.payload else { continue }
            let span = command.endTime - command.startTime
            let progress = span > 0 ? min(1, (time - command.startTime) / span) : 1
            opacity = start + (end - start) * progress
        }

        return opacity
    }

    /// When the pulse fires, in clip-local time.
    private func beats(
        in context: FilterContext,
        from birth: Double,
        to death: Double,
        every interval: Interval,
    ) -> [Double] {
        // A stated tempo wins over the song's: someone who types a number means
        // it, and a pulse deliberately off the beat is as legitimate as one on.
        let stated = context.number(Param.bpm)
        if stated > 0 {
            let spacing = 60_000 / stated * interval.beats
            return stride(from: birth, to: death, by: spacing).map { $0 }
        }

        if let grid = context.beat, !grid.isEmpty {
            // Kept only where the line lands on the chosen interval, measured
            // against the timing point rather than by counting the array.
            //
            // `lines(in:)` starts at the edge of the range asked for, which is
            // wherever the clip happens to begin — so counting positions makes
            // the first subdivision it returns the downbeat, and the hits come
            // out unevenly spaced. A pulse has to land on the song's beat, not
            // on the clip's start.
            let step = interval.beats * Double(grid.divisor)

            var hits: [Double] = []
            for line in grid.lines(in: birth ... death) {
                if interval == .everyBar {
                    if line.isMajor { hits.append(line.time) }
                    continue
                }
                guard let origin = grid.timing.timingPoint(at: line.time) else { continue }
                let position = (line.time - origin.time) / (origin.beatLength / Double(grid.divisor))
                if abs(position.rounded().truncatingRemainder(dividingBy: step)) < 0.001 {
                    hits.append(line.time)
                }
            }
            if !hits.isEmpty { return hits }
        }

        let spacing = 60_000 / Self.fallbackBPM * interval.beats
        return stride(from: birth, to: death, by: spacing).map { $0 }
    }
}
