import Foundation

/// An old television losing its picture: static, tearing, flicker, dropouts,
/// scanlines and the rolling band — and, if asked, the bars of "no signal".
///
/// **When it breaks is the effect.** A constant loss is a screen with no
/// signal at all; bursts break up the picture and let it hold between; hits
/// break it where the song hits, using the same onset detection as Beat Pulse.
/// A glitch that fires everywhere evenly is noise, not an event.
///
/// **Static jumps.** Every square is re-placed instantly each frame and never
/// slides — a square gliding between two places reads as a particle drifting,
/// and what makes static read as static is that it has no motion at all, only
/// positions.
///
/// **It costs only while it breaks.** The static and the tears write commands
/// only on the frames inside a burst; between bursts each holds invisible in
/// one command. The heavy mode is Constant, and its defaults are held to a
/// section's worth.
public struct SignalLossEffect: Effect {
    public init() {}

    public enum Param {
        public static let trigger = "trigger"
        public static let burstRate = "burstRate"
        public static let burstLength = "burstLength"
        public static let listenTo = "listenTo"
        public static let sensitivity = "sensitivity"
        public static let noise = "noise"
        public static let noiseSize = "noiseSize"
        public static let tears = "tears"
        public static let flicker = "flicker"
        public static let dropout = "dropout"
        public static let scanlines = "scanlines"
        public static let scanlineSpacing = "scanlineSpacing"
        public static let scanlineOpacity = "scanlineOpacity"
        public static let rollingBand = "rollingBand"
        public static let testPattern = "testPattern"
        public static let rate = "rate"
        public static let color = "color"
    }

    public enum Trigger: String, CaseIterable, Sendable {
        /// No signal at all, the whole clip.
        case constant = "Constant"
        /// The picture breaks up now and then, and holds between.
        case bursts = "Bursts"
        /// It breaks where the song hits.
        case hits = "Hits"
    }

    /// The seven bars of the colour test card, in their order — the picture a
    /// set shows when there is nothing to show.
    static let pattern: [EffectColor] = [
        EffectColor(r: 192, g: 192, b: 192), EffectColor(r: 192, g: 192, b: 0),
        EffectColor(r: 0, g: 192, b: 192), EffectColor(r: 0, g: 192, b: 0),
        EffectColor(r: 192, g: 0, b: 192), EffectColor(r: 192, g: 0, b: 0),
        EffectColor(r: 0, g: 0, b: 192),
    ]

    public static let descriptor = EffectDescriptor(
        type: "signalLoss",
        name: "Signal Loss",
        category: .stylise,
        systemImage: "tv",
        parameters: [
            EffectParameter(id: Param.trigger, name: "Trigger", group: "Signal",
                            defaultValue: .choice(Trigger.bursts.rawValue),
                            options: Trigger.allCases.map(\.rawValue)),
            // Bursts a second, on average. The gaps are drawn at random, so
            // the breaks come unevenly — an even rhythm reads as a metronome.
            EffectParameter(id: Param.burstRate, name: "Bursts", group: "Signal",
                            defaultValue: .number(0.8), range: 0.1...6, step: 0.1, unit: "/s",
                            shownWhen: .init(parameter: Param.trigger, isAnyOf: [Trigger.bursts.rawValue])),
            EffectParameter(id: Param.burstLength, name: "Burst Length", group: "Signal",
                            defaultValue: .number(350), range: 50...3000, step: 10, unit: "ms",
                            shownWhen: .init(parameter: Param.trigger,
                                             isAnyOf: [Trigger.bursts.rawValue, Trigger.hits.rawValue])),
            EffectParameter(id: Param.listenTo, name: "Listen To", group: "Signal",
                            defaultValue: .choice(EmitterEffect.AudioBand.bass.rawValue),
                            options: EmitterEffect.AudioBand.allCases.map(\.rawValue),
                            shownWhen: .init(parameter: Param.trigger, isAnyOf: [Trigger.hits.rawValue])),
            EffectParameter(id: Param.sensitivity, name: "Sensitivity", group: "Signal",
                            defaultValue: .number(0.5), range: 0...1, step: 0.05,
                            shownWhen: .init(parameter: Param.trigger, isAnyOf: [Trigger.hits.rawValue])),

            // Squares of static. Each writes two commands per frame of a
            // burst, so this is the number that decides the cost.
            EffectParameter(id: Param.noise, name: "Static", group: "Breakup",
                            defaultValue: .integer(60), range: 0...200, step: 1),
            EffectParameter(id: Param.noiseSize, name: "Static Size", group: "Breakup",
                            defaultValue: .number(4), range: 1...20, step: 0.5, unit: "px"),
            EffectParameter(id: Param.tears, name: "Tears", group: "Breakup",
                            defaultValue: .integer(5), range: 0...16, step: 1),
            EffectParameter(id: Param.flicker, name: "Flicker", group: "Breakup",
                            defaultValue: .number(0.25), range: 0...1, step: 0.05),
            // The chance any one frame of a burst drops to black.
            EffectParameter(id: Param.dropout, name: "Dropout", group: "Breakup",
                            defaultValue: .number(0.1), range: 0...1, step: 0.05),

            EffectParameter(id: Param.scanlines, name: "Scanlines", group: "Screen",
                            defaultValue: .toggle(true)),
            EffectParameter(id: Param.scanlineSpacing, name: "Line Spacing", group: "Screen",
                            defaultValue: .number(4), range: 2...20, step: 1, unit: "px",
                            shownWhen: .init(parameter: Param.scanlines, isAnyOf: ["true"])),
            EffectParameter(id: Param.scanlineOpacity, name: "Line Strength", group: "Screen",
                            defaultValue: .number(0.18), range: 0...1, step: 0.02,
                            shownWhen: .init(parameter: Param.scanlines, isAnyOf: ["true"])),
            EffectParameter(id: Param.rollingBand, name: "Rolling Band", group: "Screen",
                            defaultValue: .toggle(true)),
            EffectParameter(id: Param.testPattern, name: "Test Pattern", group: "Screen",
                            defaultValue: .toggle(false)),

            EffectParameter(id: Param.rate, name: "Frame Rate", group: "Screen",
                            defaultValue: .integer(15), range: 8...30, step: 1, unit: "fps"),
            EffectParameter(id: Param.color, name: "Static Colour", group: "Screen",
                            defaultValue: .color(EffectColor(r: 255, g: 255, b: 255))),
        ],
    )

    public func evaluate(in context: EffectContext, rng: inout EffectRandom) -> [StoryboardSprite] {
        let duration = context.node.duration
        guard duration > 0 else { return [] }

        let step = 1000 / Double(max(8, context.integer(Param.rate)))
        let bursts = windows(in: context, rng: &rng)
        // The frames of the clip, each marked broken or not.
        //
        // By index, not by stepping: accumulating the step leaves each frame's
        // end a hair off the next one's start, and the invisible hold written
        // into that sliver won at exactly those instants — measured, every
        // square of a Constant loss at opacity 0 at 1000, 3400 and 3800ms.
        let count = Int((duration / step).rounded(.up))
        let frames = (0 ..< count).map { index -> Frame in
            let time = Double(index) * step
            return (time: time, end: min(duration, Double(index + 1) * step),
                    broken: bursts.contains { $0.contains(time) })
        }

        let layer = context.node.layer
        let prefix = context.node.id
        var sprites: [StoryboardSprite] = []

        if context.toggle(Param.testPattern) {
            sprites += pattern(prefix: prefix, duration: duration, layer: layer)
        }

        let tint = context.color(Param.color)
        let size = context.number(Param.noiseSize) / Self.fillSource
        for index in 0 ..< max(0, context.integer(Param.noise)) {
            var own = rng.stream(1000 + index)
            sprites.append(broken(
                id: "\(prefix)/noise\(index)", frames: frames, layer: layer, colour: tint,
                scale: .scale(start: size, end: size),
            ) { _ in
                guard own.unit() < 0.85 else { return nil }
                return (x: own.between(-107, 747), y: own.between(0, 480),
                        opacity: own.between(0.3, 0.95), size: nil)
            })
        }

        for index in 0 ..< max(0, context.integer(Param.tears)) {
            var own = rng.stream(5000 + index)
            sprites.append(broken(
                id: "\(prefix)/tear\(index)", frames: frames, layer: layer, colour: tint, scale: nil,
            ) { _ in
                guard own.unit() < 0.55 else { return nil }
                return (x: 320 + own.symmetric(60), y: own.between(0, 480),
                        opacity: own.between(0.35, 0.85),
                        size: (x: 900 / Self.fillSource, y: own.between(3, 30) / Self.fillSource))
            })
        }

        if context.toggle(Param.rollingBand) {
            sprites.append(band(prefix: prefix, duration: duration, layer: layer))
        }

        if context.toggle(Param.scanlines) {
            sprites += scanlines(
                prefix: prefix, duration: duration, layer: layer,
                spacing: max(2, context.number(Param.scanlineSpacing)),
                opacity: context.number(Param.scanlineOpacity),
            )
        }

        let flicker = context.number(Param.flicker)
        if flicker > 0 {
            var own = rng.stream(9000)
            sprites.append(broken(
                id: "\(prefix)/flicker", frames: frames, layer: layer, colour: nil,
                scale: .vectorScale(startX: 854 / Self.fillSource, startY: 480 / Self.fillSource,
                                    endX: 854 / Self.fillSource, endY: 480 / Self.fillSource),
                additive: true, at: (320, 240),
            ) { _ in (x: 320, y: 240, opacity: own.between(0, flicker), size: nil) })
        }

        let dropout = context.number(Param.dropout)
        if dropout > 0 {
            var own = rng.stream(9001)
            sprites.append(broken(
                id: "\(prefix)/dropout", frames: frames, layer: layer, colour: EffectColor(r: 0, g: 0, b: 0),
                scale: .vectorScale(startX: 854 / Self.fillSource, startY: 480 / Self.fillSource,
                                    endX: 854 / Self.fillSource, endY: 480 / Self.fillSource),
                at: (320, 240),
            ) { _ in own.unit() < dropout ? (x: 320, y: 240, opacity: 1, size: nil) : nil })
        }

        return sprites
    }

    /// `fill` is one of the straight shapes, drawn at 64.
    static let fillSource: Double = 64

    // ─── When it breaks ──────────────────────────────────────────────────────

    private func windows(in context: EffectContext, rng: inout EffectRandom) -> [ClosedRange<Double>] {
        let duration = context.node.duration
        let length = max(50, context.number(Param.burstLength))

        switch Trigger(rawValue: context.choice(Param.trigger)) ?? .bursts {
        case .constant:
            return [0 ... duration]

        case .bursts:
            // Gaps drawn from an exponential, the shape of events that happen
            // at a rate but not on a rhythm — which is what a failing signal
            // does.
            let rate = max(0.1, context.number(Param.burstRate))
            var own = rng.stream(1)
            var windows: [ClosedRange<Double>] = []
            var time = -log(1 - own.unit() * 0.999) / rate * 1000
            while time < duration {
                let span = length * own.between(0.6, 1.4)
                windows.append(time ... min(duration, time + span))
                time += span + max(150, -log(1 - own.unit() * 0.999) / rate * 1000)
            }
            return windows

        case .hits:
            // In SONG time, like every effect that listens.
            let start = context.node.startTime
            let frames = AudioSpectrum.levels(
                in: start ... (start + duration),
                bands: EmitterAudio.bands,
                interval: EmitterAudio.interval,
                using: context.audio,
            )
            let band = EmitterEffect.AudioBand(rawValue: context.choice(Param.listenTo)) ?? .bass
            return AudioOnsets.detect(
                AudioOnsets.energy(of: frames, bands: band.bands),
                interval: EmitterAudio.interval,
                sensitivity: context.number(Param.sensitivity),
            ).map { $0 ... min(duration, $0 + length) }
        }
    }

    // ─── Drawing ─────────────────────────────────────────────────────────────

    private typealias Frame = (time: Double, end: Double, broken: Bool)
    private typealias Placement = (x: Double, y: Double, opacity: Double, size: (x: Double, y: Double)?)

    /// A sprite that shows only on broken frames, re-placed instantly on each.
    ///
    /// Every quiet frame and every broken frame it sits out is folded into
    /// one invisible hold, so a sprite pays for the frames it is drawn on and
    /// nothing else. The hold also keeps it hidden before its first frame:
    /// osu! draws a sprite with no command at its default opacity.
    private func broken(
        id: String,
        frames: [Frame],
        layer: Layer,
        colour: EffectColor?,
        scale: Command.Payload?,
        additive: Bool = false,
        at fixed: (x: Double, y: Double)? = nil,
        place: (Frame) -> Placement?,
    ) -> StoryboardSprite {
        guard let last = frames.last else {
            return StoryboardSprite(id: id, layer: layer, origin: .centre, filePath: BuiltInSprite.fill,
                                    defaultX: 320, defaultY: 240, commands: [], loops: [])
        }
        var commands: [Command] = []
        var hiddenFrom: Double? = 0

        func closeHidden(until time: Double) {
            // Never a hold of next to nothing: it draws nothing, costs a line,
            // and at its instant it wins over what the frame is showing.
            if let from = hiddenFrom, time - from > 1e-6 {
                commands.append(Command(easing: .linear, startTime: from, endTime: time,
                                        payload: .fade(start: 0, end: 0)))
            }
            hiddenFrom = nil
        }

        for frame in frames {
            guard frame.broken, let spot = place(frame) else {
                if hiddenFrom == nil { hiddenFrom = frame.time }
                continue
            }
            closeHidden(until: frame.time)
            if fixed == nil {
                commands.append(Command(easing: .linear, startTime: frame.time, endTime: frame.time,
                                        payload: .move(startX: spot.x, startY: spot.y, endX: spot.x, endY: spot.y)))
            }
            if let size = spot.size {
                commands.append(Command(easing: .linear, startTime: frame.time, endTime: frame.time,
                                        payload: .vectorScale(startX: size.x, startY: size.y, endX: size.x, endY: size.y)))
            }
            commands.append(Command(easing: .linear, startTime: frame.time, endTime: frame.end,
                                    payload: .fade(start: spot.opacity, end: spot.opacity)))
            hiddenFrom = frame.end
        }
        closeHidden(until: last.end)

        if let scale {
            commands.append(Command(easing: .linear, startTime: 0, endTime: last.end, payload: scale))
        }
        if let colour, colour != EffectColor(r: 255, g: 255, b: 255) {
            commands.append(Command(easing: .linear, startTime: 0, endTime: last.end, payload: .color(
                startR: colour.r, startG: colour.g, startB: colour.b,
                endR: colour.r, endG: colour.g, endB: colour.b,
            )))
        }
        if additive {
            commands.append(Command(easing: .linear, startTime: 0, endTime: last.end, payload: .parameter(.additive)))
        }
        return StoryboardSprite(id: id, layer: layer, origin: .centre, filePath: BuiltInSprite.fill,
                                defaultX: fixed?.x ?? 320, defaultY: fixed?.y ?? 240,
                                commands: commands, loops: [])
    }

    /// Something held for the whole clip: one fade, one size, one colour.
    private func held(
        id: String, x: Double, y: Double, width: Double, height: Double,
        colour: EffectColor, opacity: Double, duration: Double, layer: Layer,
    ) -> StoryboardSprite {
        StoryboardSprite(
            id: id, layer: layer, origin: .centre, filePath: BuiltInSprite.fill,
            defaultX: x, defaultY: y,
            commands: [
                Command(easing: .linear, startTime: 0, endTime: duration, payload: .fade(start: opacity, end: opacity)),
                Command(easing: .linear, startTime: 0, endTime: duration, payload: .vectorScale(
                    startX: width / Self.fillSource, startY: height / Self.fillSource,
                    endX: width / Self.fillSource, endY: height / Self.fillSource,
                )),
                Command(easing: .linear, startTime: 0, endTime: duration, payload: .color(
                    startR: colour.r, startG: colour.g, startB: colour.b,
                    endR: colour.r, endG: colour.g, endB: colour.b,
                )),
            ],
            loops: [],
        )
    }

    private func pattern(prefix: String, duration: Double, layer: Layer) -> [StoryboardSprite] {
        let width = 854 / Double(Self.pattern.count)
        return Self.pattern.enumerated().map { index, colour in
            held(id: "\(prefix)/pattern\(index)", x: -107 + width * (Double(index) + 0.5), y: 240,
                 width: width + 1, height: 480, colour: colour, opacity: 1, duration: duration, layer: layer)
        }
    }

    /// Dark lines across the whole frame, evenly spaced and still.
    private func scanlines(
        prefix: String, duration: Double, layer: Layer, spacing: Double, opacity: Double,
    ) -> [StoryboardSprite] {
        let count = Int(480 / spacing)
        let thickness = max(1, spacing * 0.4)
        return (0 ..< count).map { index in
            held(id: "\(prefix)/scan\(index)", x: 320, y: spacing * (Double(index) + 0.5),
                 width: 900, height: thickness, colour: EffectColor(r: 0, g: 0, b: 0),
                 opacity: opacity, duration: duration, layer: layer)
        }
    }

    /// The lighter band rolling slowly down the screen, over and over.
    private func band(prefix: String, duration: Double, layer: Layer) -> StoryboardSprite {
        let period = 3500.0
        var commands: [Command] = [
            Command(easing: .linear, startTime: 0, endTime: duration, payload: .fade(start: 0.07, end: 0.07)),
            Command(easing: .linear, startTime: 0, endTime: duration, payload: .vectorScale(
                startX: 900 / Self.fillSource, startY: 110 / Self.fillSource,
                endX: 900 / Self.fillSource, endY: 110 / Self.fillSource,
            )),
            Command(easing: .linear, startTime: 0, endTime: duration, payload: .parameter(.additive)),
        ]
        var time = 0.0
        while time < duration {
            let end = min(duration, time + period)
            let reach = -80 + 640 * (end - time) / period
            commands.append(Command(easing: .linear, startTime: time, endTime: end,
                                    payload: .move(startX: 320, startY: -80, endX: 320, endY: reach)))
            time = end
        }
        return StoryboardSprite(id: "\(prefix)/band", layer: layer, origin: .centre, filePath: BuiltInSprite.glow,
                                defaultX: 320, defaultY: -80, commands: commands, loops: [])
    }
}
