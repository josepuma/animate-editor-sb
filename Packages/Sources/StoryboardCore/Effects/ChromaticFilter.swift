import Foundation

/// Splits a clip into red, green and blue copies, offset from each other.
///
/// The look of a lens that cannot focus every wavelength at one point, and the
/// staple of glitch and shockwave work. Three copies drawn additively land back
/// on white where they overlap, so the subject keeps its colour and only the
/// **edges** fringe — which is exactly what the real artefact does.
///
/// Worth knowing before reaching for it: the fringe lives on hard edges, and a
/// soft particle has none. On text, geometry and the drawn shapes it is
/// striking; over a cloud of glows it costs three times the sprites to produce
/// something almost invisible. Use it where there is a line to fringe.
public struct ChromaticFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let offset = "offset"
        public static let angle = "angle"
        public static let intensity = "intensity"
        public static let keepsOriginal = "keepsOriginal"
        public static let jitter = "jitter"
        public static let rate = "rate"
    }

    public static let descriptor = FilterDescriptor(
        type: "chromatic",
        name: "Chromatic",
        category: "Stylise",
        systemImage: "circle.lefthalf.filled.righthalf.striped.horizontal",
        parameters: [
            EffectParameter(
                id: Param.offset,
                name: "Split",
                group: "Chromatic",
                defaultValue: .number(4),
                range: 0...40,
                step: 1,
                unit: "px",
            ),
            EffectParameter(
                id: Param.angle,
                name: "Direction",
                group: "Chromatic",
                defaultValue: .number(0),
                range: 0...360,
                step: 5,
                unit: "°",
            ),
            EffectParameter(
                id: Param.intensity,
                name: "Strength",
                group: "Chromatic",
                defaultValue: .number(0.7),
                range: 0...1,
                step: 0.05,
                presentation: .slider,
            ),
            // How much the split jumps about during the clip.
            //
            // A fixed split is a lens out of focus; a split that leaps and
            // settles is something breaking. That difference is most of what
            // people mean by "glitch", and it needs no keyframes — the jumps
            // are written straight into the commands, the way `Wiggle` writes
            // its shake.
            EffectParameter(
                id: Param.jitter,
                name: "Jitter",
                group: "Glitch",
                defaultValue: .number(0),
                range: 0...1,
                step: 0.05,
                presentation: .slider,
            ),
            EffectParameter(
                id: Param.rate,
                name: "Rate",
                group: "Glitch",
                defaultValue: .number(12),
                range: 1...30,
                step: 1,
                unit: "Hz",
            ),
            // Keeping the subject underneath holds its colour steady while the
            // fringes sit around it. Dropped, the three channels are all there
            // is — a harder, more broken look, and one sprite cheaper.
            EffectParameter(
                id: Param.keepsOriginal,
                name: "Keep Original",
                group: "Chromatic",
                defaultValue: .toggle(false),
            ),
        ],
    )

    public func estimatedMultiplier(in context: FilterContext) -> Double {
        context.toggle(Param.keepsOriginal) ? 4 : 3
    }

    /// The split leaping about, written as a run of move commands.
    ///
    /// Each step **holds** its offset rather than gliding to the next, which is
    /// what separates a glitch from a wobble: a signal that breaks up jumps
    /// between states, it does not travel between them. Two commands per step —
    /// one to arrive, one to hold — and the arrival is instant.
    ///
    /// Written on top of the channel's own offset, so turning Jitter down
    /// returns to the steady split rather than to no split at all.
    private func jumps(
        of sprite: StoryboardSprite,
        from first: Double,
        to last: Double,
        dx: Double,
        dy: Double,
        reach: Double,
        rate: Double,
        rng: inout EffectRandom,
    ) -> [Command] {
        let step = 1000 / rate
        // Capped, because every step is a command in the file: a long clip at a
        // high rate would write thousands per sprite, and past the cap the
        // flicker is faster than anyone can see anyway.
        let count = min(Int((last - first) / step), 120)
        guard count > 1 else { return [] }

        let baseX = sprite.defaultX + dx
        let baseY = sprite.defaultY + dy

        var written: [Command] = []
        written.reserveCapacity(count)

        for index in 0 ..< count {
            let at = first + step * Double(index)

            // Most steps sit still: a glitch that fires on every frame is
            // static, and what reads as breaking up is that the calm between
            // bursts makes each one an event.
            guard rng.unit() < 0.45 else { continue }

            let toX = baseX + rng.symmetric(reach)
            let toY = baseY + rng.symmetric(reach)

            written.append(Command(
                easing: .linear,
                startTime: at,
                endTime: min(last, at + step),
                payload: .move(startX: toX, startY: toY, endX: toX, endY: toY),
            ))
        }

        return written
    }

    private static func seed(from string: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in Array(string.utf8) {
            hash = (hash ^ UInt64(byte)) &* 0x1000_0000_01B3
        }
        return hash
    }

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        let offset = context.number(Param.offset)
        let angle = context.number(Param.angle) * .pi / 180
        let intensity = context.number(Param.intensity)
        let keepsOriginal = context.toggle(Param.keepsOriginal)
        let jitter = context.number(Param.jitter)
        let rate = max(1, context.number(Param.rate))

        guard offset > 0, intensity > 0 else { return sprites }

        // Red one way, blue the other, green in the middle: that ordering is
        // what a lens does, and reversing it looks wrong to anyone who has seen
        // the real thing even without knowing why.
        let channels: [(name: String, colour: EffectColor, shift: Double)] = [
            ("r", EffectColor(r: 255, g: 0, b: 0), 1),
            ("g", EffectColor(r: 0, g: 255, b: 0), 0),
            ("b", EffectColor(r: 0, g: 0, b: 255), -1),
        ]

        var result: [StoryboardSprite] = keepsOriginal ? sprites : []
        result.reserveCapacity(sprites.count * (keepsOriginal ? 4 : 3))

        for channel in channels {
            let dx = cos(angle) * offset * channel.shift
            let dy = sin(angle) * offset * channel.shift

            for (index, sprite) in sprites.enumerated() {
                // A stream per channel per sprite, so every copy jumps on its
                // own — three channels leaping together would slide as a block
                // and read as a shake rather than as a signal coming apart.
                var rng = EffectRandom(seed: Self.seed(from: context.idPrefix + channel.name))
                    .stream(index)
                var copy = sprite
                copy.id = "\(context.idPrefix)/c\(channel.name)-\(index)"
                copy.defaultX += dx
                copy.defaultY += dy

                copy.commands = sprite.commands.compactMap { command in
                    switch command.payload {
                    case let .move(startX, startY, endX, endY):
                        Command(
                            timing: command.timing,
                            payload: .move(
                                startX: startX + dx, startY: startY + dy,
                                endX: endX + dx, endY: endY + dy,
                            ),
                        )

                    case let .moveX(start, end):
                        Command(timing: command.timing, payload: .moveX(start: start + dx, end: end + dx))

                    case let .moveY(start, end):
                        Command(timing: command.timing, payload: .moveY(start: start + dy, end: end + dy))

                    case let .fade(start, end):
                        Command(
                            timing: command.timing,
                            payload: .fade(start: start * intensity, end: end * intensity),
                        )

                    case .color:
                        // Replaced, not multiplied: this copy *is* the channel,
                        // and a red copy of a blue sprite has to come out red
                        // rather than black.
                        Command(
                            timing: command.timing,
                            payload: .color(
                                startR: channel.colour.r,
                                startG: channel.colour.g,
                                startB: channel.colour.b,
                                endR: channel.colour.r,
                                endG: channel.colour.g,
                                endB: channel.colour.b,
                            ),
                        )

                    case .parameter(.additive):
                        // Already additive, and the copies must be — the whole
                        // trick is that three channels sum back to white where
                        // they overlap. Dropped here and re-added below so a
                        // sprite that was not additive becomes one.
                        nil

                    default:
                        command
                    }
                }

                // The colour and the blend, for a sprite that carried neither.
                let first = sprite.commands.map(\.startTime).min() ?? 0
                let last = sprite.commands.map(\.endTime).max() ?? first

                if !sprite.commands.contains(where: { $0.kind == .color }) {
                    copy.commands.append(Command(
                        easing: .linear,
                        startTime: first,
                        endTime: first,
                        payload: .color(
                            startR: channel.colour.r,
                            startG: channel.colour.g,
                            startB: channel.colour.b,
                            endR: channel.colour.r,
                            endG: channel.colour.g,
                            endB: channel.colour.b,
                        ),
                    ))
                }

                copy.commands.append(Command(
                    easing: .linear,
                    startTime: first,
                    endTime: last,
                    payload: .parameter(.additive),
                ))

                if jitter > 0, last > first {
                    copy.commands += jumps(
                        of: sprite,
                        from: first, to: last,
                        dx: dx, dy: dy,
                        reach: offset * jitter * 3,
                        rate: rate,
                        rng: &rng,
                    )
                }

                result.append(copy)
            }
        }

        return result
    }
}
