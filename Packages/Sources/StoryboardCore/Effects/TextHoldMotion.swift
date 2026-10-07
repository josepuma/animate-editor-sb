import Foundation

/// How a glyph moves while it holds, between landing and leaving.
///
/// Pure like `TextExit`: values in, commands out. Every mode is written as a
/// short run of commands over the hold, because osu! has no oscillator — a
/// wave is a string of eased moves from one crest to the next.
///
/// Three rules every mode keeps:
/// - **An envelope** brings the motion in from nothing and back to nothing, so
///   the hold neither jumps off the entrance nor into the exit.
/// - **At most `maximumSteps` commands.** A long hold lengthens its steps
///   rather than writing more of them or stopping short: each step is a line
///   per glyph in the file.
/// - **Its own stream**, derived per unit. Explode, Drift and the scatter draw
///   from the glyph's stream, and a hold drawing ahead of them would hand
///   every saved burst different headings.
enum TextHoldMotion {
    static let tag = 0x7E1D_4001
    static let maximumSteps = 48

    enum Mode: String, CaseIterable {
        case none = "None", wave = "Wave", float = "Float", jitter = "Jitter", breathe = "Breathe", shake = "Shake"
    }

    struct Settings {
        var mode: Mode
        /// Pixels, for the modes that move.
        var amount: Double
        /// A share, 0…1, for Breathe.
        var breathe: Double
        /// Hertz.
        var speed: Double
        /// Degrees between neighbouring units.
        var phase: Double

        init(context: EffectContext) {
            typealias P = TextEffect.Param
            mode = Mode(rawValue: context.choice(P.holdMotion)) ?? .none
            amount = context.number(P.holdAmount)
            breathe = context.number(P.holdBreathe) / 100
            speed = context.number(P.holdSpeed)
            phase = context.number(P.holdPhase)
        }

        var movesPosition: Bool { [.wave, .float, .jitter, .shake].contains(mode) && amount != 0 }
        var scales: Bool { mode == .breathe && breathe != 0 }
    }

    /// The parameters, in the order the inspector shows them.
    static let parameters: [EffectParameter] = {
        typealias P = TextEffect.Param
        let moving = ["Wave", "Float", "Jitter", "Shake"]
        return [
            // Movement across the whole clip, not just its ends.
            //
            // A line that arrives, sits perfectly still, and leaves is three
            // separate moments. Letting it travel while it is up is what turns
            // those into one shot — the drift a title has as it holds.
            EffectParameter(
                id: P.driftX, name: "Travel X", group: "Hold",
                defaultValue: .number(0), range: -800...800, step: 5, unit: "px",
            ),
            EffectParameter(
                id: P.driftY, name: "Travel Y", group: "Hold",
                defaultValue: .number(0), range: -600...600, step: 5, unit: "px",
            ),
            // Still is the default: a placement gives text, not a performance.
            EffectParameter(
                id: P.holdMotion, name: "Motion", group: "Hold",
                defaultValue: .choice(Mode.none.rawValue), options: Mode.allCases.map(\.rawValue),
            ),
            EffectParameter(
                id: P.holdAmount, name: "Amount", group: "Hold",
                defaultValue: .number(10), range: 0...200, step: 1, unit: "px",
                shownWhen: .init(parameter: P.holdMotion, isAnyOf: moving),
            ),
            EffectParameter(
                id: P.holdBreathe, name: "Breathe", group: "Hold",
                defaultValue: .number(10), range: 0...100, step: 1, unit: "%",
                shownWhen: .init(parameter: P.holdMotion, isAnyOf: ["Breathe"]),
            ),
            EffectParameter(
                id: P.holdSpeed, name: "Speed", group: "Hold",
                defaultValue: .number(1), range: 0.1...8, step: 0.05, unit: "Hz",
                shownWhen: .init(parameter: P.holdMotion, isAnyOf: moving + ["Breathe"]),
            ),
            // Only the smooth modes have a phase: a jitter has no cycle to
            // offset.
            EffectParameter(
                id: P.holdPhase, name: "Phase Spread", group: "Hold",
                defaultValue: .number(40), range: 0...360, step: 5, unit: "°",
                shownWhen: .init(parameter: P.holdMotion, isAnyOf: ["Wave", "Float", "Breathe"]),
            ),
        ]
    }()

    /// 0 at both edges of the hold, 1 inside, with smoothstep ramps of a fifth
    /// of the hold (at most 250ms) between.
    static func envelope(_ t: Double, start: Double, end: Double) -> Double {
        let ramp = min(250, 0.2 * (end - start))
        guard ramp > 0 else { return 0 }
        let edge = min(t - start, end - t) / ramp
        let clamped = min(1, max(0, edge))
        return clamped * clamped * (3 - 2 * clamped)
    }

    /// The position steps over `[start, end]`, or `nil` when this mode does not
    /// move the glyph — the travel is then written as it always was.
    ///
    /// The travel is folded in: every step writes `base(t) + offset(t)` with
    /// `base` running from `rest` to `rest + travel`. Two `_M` over one span
    /// are not added by osu!, the later one simply wins.
    static func position(
        _ settings: Settings,
        unit: Int,
        rest: (x: Double, y: Double),
        travel: (x: Double, y: Double),
        start: Double,
        end: Double,
        rng: EffectRandom,
    ) -> [Command]? {
        guard settings.movesPosition, end > start else { return nil }
        let span = end - start
        func base(_ t: Double) -> (x: Double, y: Double) {
            let share = (t - start) / span
            return (rest.x + travel.x * share, rest.y + travel.y * share)
        }
        func move(_ from: Double, _ to: Double, _ a: (x: Double, y: Double), _ b: (x: Double, y: Double), _ easing: Easing) -> Command {
            let p = base(from), q = base(to)
            return Command(
                easing: easing, startTime: from, endTime: to,
                payload: .move(startX: p.x + a.x, startY: p.y + a.y, endX: q.x + b.x, endY: q.y + b.y),
            )
        }

        switch settings.mode {
        case .wave, .float:
            let phase = Double(unit) * settings.phase * .pi / 180
            let omega = angularSpeed(settings.speed, span: span)
            let isWave = settings.mode == .wave
            let amount = settings.amount
            // Float's horizontal swing runs at half the speed of its vertical
            // one, so its crests are a subset of the vertical ones: breaking at
            // the vertical extremes catches both.
            let crests = extremes(omega: omega, phase: isWave ? phase : 2 * phase - .pi / 2, offset: .pi / 2, start: start, end: end)
            func offset(_ t: Double) -> (x: Double, y: Double) {
                let e = envelope(t, start: start, end: end)
                return isWave
                    ? (0, e * amount * sin(omega * t + phase))
                    : (e * amount * sin(omega / 2 * t + phase), e * 0.5 * amount * sin(omega * t + 2 * phase - .pi / 2))
            }
            let times = [start] + crests + [end]
            return zip(times, times.dropFirst()).map { a, b in move(a, b, offset(a), offset(b), .sineInOut) }

        case .jitter, .shake:
            let rate = 12 * settings.speed
            let count = steps(span: span, step: 1000 / rate)
            let times = (0...count).map { start + span * Double($0) / Double(count) }
            var stream = rng
            if settings.mode == .jitter {
                // A held offset per step, so the glyph jumps at each joint
                // rather than sliding between places — what reads as a glitch.
                // Three draws per step whether or not it fires, so its numbers
                // never depend on the step before.
                let offsets: [(x: Double, y: Double)] = times.dropLast().enumerated().map { index, t in
                    let fires = stream.unit() < 0.45
                    let jump = (x: stream.symmetric(settings.amount), y: stream.symmetric(settings.amount))
                    let e = index == count - 1 ? 0 : envelope(t, start: start, end: end)
                    return fires ? (jump.x * e, jump.y * e) : (0, 0)
                }
                return offsets.indices.map { index in
                    move(times[index], times[index + 1], offsets[index], offsets[index], .linear)
                }
            }
            // Shake: a walk pulled halfway home at each step, so it trembles
            // around the rest rather than wandering off.
            var walk = (x: 0.0, y: 0.0)
            var points: [(x: Double, y: Double)] = [(0, 0)]
            for t in times.dropFirst().dropLast() {
                walk.x = min(settings.amount, max(-settings.amount, 0.5 * walk.x + stream.symmetric(settings.amount)))
                walk.y = min(settings.amount, max(-settings.amount, 0.5 * walk.y + stream.symmetric(settings.amount)))
                let e = envelope(t, start: start, end: end)
                points.append((walk.x * e, walk.y * e))
            }
            points.append((0, 0))
            return (0..<count).map { move(times[$0], times[$0 + 1], points[$0], points[$0 + 1], .linear) }

        case .none, .breathe:
            return nil
        }
    }

    /// Breathe: the glyph swelling and settling over `[start, end]`, on `_V`
    /// when the sprite already speaks it — one scale vocabulary per sprite.
    static func scale(_ settings: Settings, unit: Int, start: Double, end: Double, vector: Bool) -> [Command] {
        guard settings.scales, end > start else { return [] }
        let phase = Double(unit) * settings.phase * .pi / 180
        let omega = angularSpeed(settings.speed, span: end - start)
        func size(_ t: Double) -> Double {
            1 + envelope(t, start: start, end: end) * settings.breathe * (1 - cos(omega * t + phase)) / 2
        }
        let times = [start] + extremes(omega: omega, phase: phase, offset: 0, start: start, end: end) + [end]
        return zip(times, times.dropFirst()).map { a, b in
            Command(
                easing: .sineInOut, startTime: a, endTime: b,
                payload: vector
                    ? .vectorScale(startX: size(a), startY: size(a), endX: size(b), endY: size(b))
                    : .scale(start: size(a), end: size(b)),
            )
        }
    }

    /// Radians per millisecond, slowed so a hold never needs more than
    /// `maximumSteps` crest-to-crest steps: a sine has two extremes a cycle.
    private static func angularSpeed(_ hertz: Double, span: Double) -> Double {
        let ceiling = Double(maximumSteps - 2) * 1000 / (2 * span)
        return 2 * .pi * min(max(0, hertz), ceiling) / 1000
    }

    /// The instants strictly inside `(start, end)` where `ωt + phase` lands on
    /// `offset + kπ` — the crests and troughs of the curve the steps follow.
    private static func extremes(omega: Double, phase: Double, offset: Double, start: Double, end: Double) -> [Double] {
        guard omega > 0 else { return [] }
        var k = ((omega * start + phase - offset) / .pi).rounded(.down)
        var found: [Double] = []
        while found.count < maximumSteps - 1 {
            let t = (offset + k * .pi - phase) / omega
            k += 1
            if t <= start { continue }
            if t >= end { break }
            found.append(t)
        }
        return found
    }

    /// How many equal steps cover `span` at `step` each, lengthened to stay
    /// inside the cap rather than cut short of the hold's end.
    private static func steps(span: Double, step: Double) -> Int {
        min(maximumSteps, max(1, Int((span / step).rounded(.up))))
    }
}
