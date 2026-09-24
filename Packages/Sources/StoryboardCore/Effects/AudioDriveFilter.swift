import Foundation

/// Any clip following the song's level: a logo that breathes with the bass, a
/// title that swells on the chorus, a background that dims in the breakdown.
///
/// The continuous half of listening, beside Beat Pulse's discrete one. A pulse
/// fires on a hit and settles; this tracks how loud it is from moment to
/// moment — so it costs a command per frame per property, where a pulse costs
/// one per hit. That trade is why both exist: this for a drop or a chorus,
/// the pulse for a whole song.
///
/// **It multiplies, never replaces.** The size and opacity a clip already has
/// are read at every step and scaled — a bar keeps its proportions, an
/// entrance keeps its fade. Two commands on one property at one moment fight,
/// and osu! picks a winner, so the ones this rewrites are taken over whole.
public struct AudioDriveFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let listenTo = "listenTo"
        public static let scale = "scale"
        public static let dim = "dim"
        public static let smoothing = "smoothing"
        public static let frameRate = "frameRate"
    }

    /// How many steps one sprite may write per property. Past it the steps
    /// widen instead of multiplying: a long clip at a high rate would write
    /// thousands of lines for a flicker faster than anyone sees.
    static let maximumSteps = 400

    public static let descriptor = FilterDescriptor(
        type: "audio-drive",
        name: "Audio Drive",
        category: .audio,
        systemImage: "waveform",
        parameters: [
            EffectParameter(
                id: Param.listenTo,
                name: "Listen To",
                group: "Audio",
                defaultValue: .choice(EmitterEffect.AudioBand.all.rawValue),
                options: EmitterEffect.AudioBand.allCases.map(\.rawValue),
            ),
            // How much bigger at full volume, as a multiplier on the clip's
            // own size. Zero by default: it lands on clips already placed.
            EffectParameter(
                id: Param.scale,
                name: "Scale",
                group: "Audio",
                defaultValue: .number(0),
                range: 0...2,
                step: 0.05,
            ),
            // How far the quiet parts dim. At 1, silence is invisible and the
            // loudest moment is the clip's own opacity — the song lights it.
            EffectParameter(
                id: Param.dim,
                name: "Dim",
                group: "Audio",
                defaultValue: .number(0),
                range: 0...1,
                step: 0.05,
            ),
            // A slow release: after a hit the level falls off by this much per
            // analysed frame instead of cutting out. Without it a driven clip
            // flickers with every transient.
            EffectParameter(
                id: Param.smoothing,
                name: "Smoothing",
                group: "Audio",
                defaultValue: .number(0.6),
                range: 0...0.95,
                step: 0.05,
            ),
            // Steps per second, which is what the file pays: every step is a
            // command per property per sprite.
            EffectParameter(
                id: Param.frameRate,
                name: "Frame Rate",
                group: "Audio",
                defaultValue: .number(20),
                range: 5...30,
                step: 1,
                unit: "fps",
            ),
        ],
    )

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        let scale = context.number(Param.scale)
        let dim = min(max(context.number(Param.dim), 0), 1)
        // Inert at its defaults, and cheaply so: nothing is read or rewritten.
        guard scale > 0 || dim > 0, !sprites.isEmpty else { return sprites }

        let birth = sprites.flatMap { $0.commands.map(\.startTime) }.min() ?? 0
        let death = sprites.flatMap { $0.commands.map(\.endTime) }.max() ?? birth
        guard death > birth else { return sprites }

        let envelope = Self.envelope(
            in: context,
            from: birth,
            to: death,
            band: EmitterEffect.AudioBand(rawValue: context.choice(Param.listenTo)) ?? .all,
            smoothing: min(max(context.number(Param.smoothing), 0), 0.95),
        )
        let step = 1000 / min(max(context.number(Param.frameRate), 5), 30)

        return sprites.map { sprite in
            driven(sprite, by: envelope, from: birth, step: step, scale: scale, dim: dim)
        }
    }

    /// The level to follow, frame by frame from `birth`, 0…1.
    ///
    /// Asked in SONG time — filters run before the clip is shifted into place —
    /// then stretched to the clip's own range, so what it follows is the
    /// music's dynamics here and not how loud the song is overall. The
    /// release runs after, so a hit rises at once and falls off slowly.
    private static func envelope(
        in context: FilterContext,
        from birth: Double,
        to death: Double,
        band: EmitterEffect.AudioBand,
        smoothing: Double,
    ) -> [Double] {
        let frames = AudioSpectrum.levels(
            in: (birth + context.clipStart) ... (death + context.clipStart),
            bands: EmitterAudio.bands,
            interval: EmitterAudio.interval,
            using: context.audio,
        )
        let energy = AudioOnsets.energy(of: frames, bands: band.bands)
        guard let low = energy.min(), let high = energy.max() else { return [] }
        let span = high - low
        let level = span > 1e-6 ? energy.map { ($0 - low) / span } : energy.map { _ in 0.0 }

        var held: [Double] = []
        held.reserveCapacity(level.count)
        for value in level {
            held.append(max(value, (held.last ?? 0) * smoothing))
        }
        return held
    }

    /// One sprite, following the envelope across its own life.
    private func driven(
        _ sprite: StoryboardSprite,
        by envelope: [Double],
        from birth: Double,
        step: Double,
        scale: Double,
        dim: Double,
    ) -> StoryboardSprite {
        guard !envelope.isEmpty,
              let start = sprite.commands.map(\.startTime).min(),
              let end = sprite.commands.map(\.endTime).max(),
              end > start
        else { return sprite }

        let steps = min(Self.maximumSteps, max(1, Int(((end - start) / step).rounded(.up))))
        let times = (0 ... steps).map { start + (end - start) * Double($0) / Double(steps) }

        func level(at time: Double) -> Double {
            let frame = Int((time - birth) / EmitterAudio.interval)
            return envelope[min(max(0, frame), envelope.count - 1)]
        }

        var result = sprite
        if scale > 0 {
            let sizes = times.map { time -> (x: Double, y: Double) in
                let resting = sprite.restingScale(at: time)
                let factor = 1 + scale * level(at: time)
                return (resting.x * factor, resting.y * factor)
            }
            // Uniform when the subject is: `_V` on a sprite that was never
            // stretched spends two numbers where one was enough.
            let uniform = sizes.allSatisfy { abs($0.x - $0.y) < 1e-9 }
            result.commands.removeAll { $0.kind == .scale || $0.kind == .vectorScale }
            for index in 0 ..< steps {
                let a = sizes[index], b = sizes[index + 1]
                result.commands.append(Command(
                    easing: .linear,
                    startTime: times[index],
                    endTime: times[index + 1],
                    payload: uniform
                        ? .scale(start: a.x, end: b.x)
                        : .vectorScale(startX: a.x, startY: a.y, endX: b.x, endY: b.y),
                ))
            }
        }

        if dim > 0 {
            let opacities = times.map { time in
                sprite.restingOpacity(at: time) * (1 - dim + dim * level(at: time))
            }
            result.commands.removeAll { $0.kind == .fade }
            for index in 0 ..< steps {
                result.commands.append(Command(
                    easing: .linear,
                    startTime: times[index],
                    endTime: times[index + 1],
                    payload: .fade(start: opacities[index], end: opacities[index + 1]),
                ))
            }
        }
        return result
    }
}
