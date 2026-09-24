import Foundation

/// Analysed audio, supplied by whoever can read the file.
///
/// `StoryboardCore` cannot open an audio file, so the one thing it needs from
/// outside is the levels: injected the way `TextMetrics` is, and with the same
/// deliberate fallback — a bank of bars that moves to a placeholder pattern
/// still lays out, still animates, and still shows what the parameters do,
/// which is far better than an effect that draws nothing because nobody
/// installed the analyser.
public enum AudioSpectrum {
    /// Levels per band, indexed `[frame][band]`, each in 0...1.
    public struct Frames: Sendable, Equatable {
        public var levels: [[Float]]
        /// Milliseconds between frames.
        public var interval: Double

        public init(levels: [[Float]], interval: Double) {
            self.levels = levels
            self.interval = interval
        }

        public var isEmpty: Bool { levels.isEmpty }
    }

    /// What reads the track. Core cannot, so whoever builds an evaluator hands
    /// one in — the app gives it the decoder for the open song.
    ///
    /// Asked for a stretch of the song rather than the whole thing, because
    /// that is what a clip covers: analysing five minutes to animate eight
    /// seconds is work nobody sees.
    ///
    /// **Handed to each evaluator, not installed as a global** — for the
    /// reason `ScriptRuntime.Runner` is: a test that needs real hits cannot use
    /// the stand-in, whose smooth sines have none, so it has to install
    /// something, and installing into one global under parallel suites is the
    /// race that runtime already paid for.
    public typealias Analyser = @Sendable (
        _ range: ClosedRange<Double>, _ bands: Int, _ interval: Double,
    ) -> Frames?

    /// The levels for a stretch of the song, real or stood in for.
    ///
    /// `analyser` has no default on purpose: a call site that forgot to pass
    /// one would fall back to the stand-in without a word, which is how a
    /// storyboard ends up dancing to a sine wave.
    public static func levels(
        in range: ClosedRange<Double>,
        bands: Int,
        interval: Double,
        using analyser: Analyser?,
    ) -> Frames {
        if let analyser, let real = analyser(range, bands, interval), !real.isEmpty {
            return real
        }
        return placeholder(in: range, bands: bands, interval: interval)
    }

    /// A stand-in pattern for when there is no track to read.
    ///
    /// A travelling wave rather than noise: it has to look like something a
    /// spectrum does, so the parameters can be judged against it, and it has to
    /// be the same every time so a preview does not shimmer.
    private static func placeholder(
        in range: ClosedRange<Double>,
        bands: Int,
        interval: Double,
    ) -> Frames {
        let count = max(1, Int((range.upperBound - range.lowerBound) / interval))
        var levels: [[Float]] = []
        levels.reserveCapacity(count)

        for frame in 0 ..< count {
            let time = Double(frame) * interval / 1000
            levels.append((0 ..< bands).map { band in
                let position = Double(band) / Double(max(1, bands - 1))

                // Every band uses its whole range.
                //
                // The first version multiplied each band by a tilt falling
                // towards the treble, which is how music usually sits — and it
                // gave every bar a *different ceiling and a different floor*.
                // The row read as bars floating at various heights rather than
                // as a row standing on one base, because that is what it was:
                // with a rest height of 6px the shortest bar still never fell
                // below 30. A stand-in has to reach the floor, or it says the
                // effect cannot.
                let wave = 0.5 + 0.5 * sin(time * 6 - position * 5)
                return Float(min(1, max(0, wave)))
            })
        }

        return Frames(levels: levels, interval: interval)
    }
}

/// A bank of bars that rises and falls with the music.
///
/// The thing every music video has and every storyboard tool makes hard: a row
/// of columns, bass on the left, treble on the right. The map's own audio is
/// already loaded, so it asks for nothing — no file to pick, no offset to line
/// up by ear.
///
/// **Bounded to its clip**, and that is the whole design. Each bar writes a
/// scale command per analysed frame, so a bank spanning a five-minute song at
/// thirty frames a second is hundreds of thousands of lines — a file osu! will
/// not open. Inside an eight-second clip at a sane rate it is a few thousand,
/// which is what a storyboard can carry. Put it on the drop.
public struct AudioBarsEffect: Effect {
    public init() {}

    public enum Param {
        public static let sprite = "sprite"
        public static let bands = "bands"
        public static let rate = "rate"
        public static let width = "width"
        public static let gap = "gap"
        public static let height = "height"
        public static let floorHeight = "floor"
        public static let easing = "easing"
        public static let origin = "origin"
        public static let color = "color"
        public static let colorTop = "colorTop"
        public static let opacity = "opacity"
        public static let additive = "additive"
        public static let mirrored = "mirrored"
        public static let layout = "layout"
        public static let radius = "radius"
        public static let arcSpan = "arcSpan"
        public static let sides = "sides"
        public static let element = "element"
        public static let segments = "segments"
    }

    /// Which way the bars grow.
    ///
    /// A bar rooted at the bottom is the familiar one; rooted at the top it
    /// hangs from a ceiling, and centred it opens both ways like a waveform.
    /// The choice is where the bar's *anchor* sits, which is why it maps to a
    /// storyboard origin rather than to a position.
    public enum Grounding: String, CaseIterable, Sendable {
        case bottom = "Bottom"
        case top = "Top"
        case centre = "Centre"

        var origin: Origin {
            switch self {
            case .bottom: .bottomCentre
            case .top: .topCentre
            case .centre: .centre
            }
        }
    }

    /// How a bar moves between one reading and the next.
    public enum Response: String, CaseIterable, Sendable {
        case linear = "Linear"
        case smooth = "Smooth"
        case snap = "Snap"
        case settle = "Settle"

        var easing: Easing {
            switch self {
            case .linear: .linear
            case .smooth: .sineInOut
            case .snap: .expoOut
            case .settle: .backOut
            }
        }
    }

    /// How large the default image is.
    ///
    /// A bar is a **shape**, not a particle, so it draws with `fill` — hard
    /// edged and 512 across — rather than with `square`, which is a particle
    /// that fades at its rim. Pointed at the particle, a bar asked for at 28px
    /// came out about two: the number here and the image it describes have to
    /// be the same one.
    ///
    /// This is the lesson `ShapeEffect` already learned, made again one effect
    /// along: what a shape needs is a texture that says where it *ends*.
    ///
    /// Sixty-four, not 512: only the round shapes are drawn large, because a
    /// magnified curve becomes a staircase while a straight edge survives it. A
    /// bar is four straight edges.
    public static let sourceSize: Double = 64

    public static let descriptor = EffectDescriptor(
        type: "audioBars",
        name: "Audio Bars",
        category: .audio,
        systemImage: "waveform",
        parameters: [
            EffectParameter(
                id: Param.bands,
                name: "Bars",
                group: "Bars",
                defaultValue: .integer(24),
                range: 2...64,
                step: 1,
            ),
            EffectParameter(
                id: Param.width,
                name: "Bar Width",
                group: "Bars",
                defaultValue: .number(18),
                range: 1...200,
                step: 1,
                unit: "px",
            ),
            EffectParameter(
                id: Param.gap,
                name: "Gap",
                group: "Bars",
                defaultValue: .number(6),
                range: 0...100,
                step: 1,
                unit: "px",
            ),
            EffectParameter(
                id: Param.height,
                name: "Peak Height",
                group: "Bars",
                defaultValue: .number(160),
                range: 4...480,
                step: 4,
                unit: "px",
            ),
            // What a silent band still shows.
            //
            // Zero is a bar that vanishes between beats, which reads as the
            // effect breaking rather than as quiet: a bank of bars is a row,
            // and a row with holes in it is not one.
            EffectParameter(
                id: Param.floorHeight,
                name: "Rest Height",
                group: "Bars",
                defaultValue: .number(6),
                range: 0...200,
                step: 1,
                unit: "px",
            ),
            EffectParameter(
                id: Param.origin,
                name: "Grow From",
                group: "Bars",
                defaultValue: .choice(Grounding.bottom.rawValue),
                options: Grounding.allCases.map(\.rawValue),
            ),
            // Mirrored, the bank runs treble-out from the middle rather than
            // bass-to-treble across — the layout every festival visual uses,
            // because it is symmetric and a row of columns is not.
            EffectParameter(
                id: Param.mirrored,
                name: "Mirror",
                group: "Bars",
                defaultValue: .toggle(false),
            ),
            EffectParameter(
                id: Param.element,
                name: "Draw As",
                group: "Bars",
                defaultValue: .choice(Element.bar.rawValue),
                options: Element.allCases.map(\.rawValue),
            ),
            // How many segments a meter column has. Every segment is a sprite,
            // so this multiplies the bank — but a segment only writes when it
            // switches on or off, not on every frame.
            EffectParameter(
                id: Param.segments,
                name: "Segments",
                group: "Bars",
                defaultValue: .integer(8),
                range: 3...24,
                step: 1,
                shownWhen: .init(parameter: Param.element, isAnyOf: [Element.segments.rawValue]),
            ),

            // ─── Layout ──────────────────────────────────────────────────
            //
            // A row by default, so every bank already placed stands where it
            // stood.
            EffectParameter(
                id: Param.layout,
                name: "Layout",
                group: "Layout",
                defaultValue: .choice(Layout.line.rawValue),
                options: Layout.allCases.map(\.rawValue),
            ),
            EffectParameter(
                id: Param.radius,
                name: "Radius",
                group: "Layout",
                defaultValue: .number(120),
                range: 10...400,
                step: 1,
                unit: "px",
                shownWhen: .init(
                    parameter: Param.layout,
                    isAnyOf: [Layout.circle, .arc, .polygon].map(\.rawValue),
                ),
            ),
            EffectParameter(
                id: Param.arcSpan,
                name: "Arc Span",
                group: "Layout",
                defaultValue: .number(180),
                range: 20...360,
                step: 1,
                unit: "°",
                shownWhen: .init(parameter: Param.layout, isAnyOf: [Layout.arc.rawValue]),
            ),
            EffectParameter(
                id: Param.sides,
                name: "Sides",
                group: "Layout",
                defaultValue: .integer(6),
                range: 3...12,
                step: 1,
                shownWhen: .init(parameter: Param.layout, isAnyOf: [Layout.polygon.rawValue]),
            ),

            // How often the audio is read.
            //
            // Every analysed frame is a command per bar, so this is the number
            // that decides whether the file opens. Twenty a second is fast
            // enough to read as reactive and a third of the cost of sixty.
            EffectParameter(
                id: Param.rate,
                name: "Frame Rate",
                group: "Motion",
                defaultValue: .integer(20),
                range: 5...60,
                step: 1,
                unit: "fps",
            ),
            EffectParameter(
                id: Param.easing,
                name: "Response",
                group: "Motion",
                defaultValue: .choice(Response.smooth.rawValue),
                options: Response.allCases.map(\.rawValue),
            ),

            EffectParameter(
                id: Param.sprite,
                name: "Sprite",
                group: "Look",
                // A plain path, because that is what it becomes on export.
                defaultValue: .text(BuiltInSprite.fill),
            ),
            EffectParameter(
                id: Param.color,
                name: "Colour",
                group: "Look",
                defaultValue: .color(EffectColor(r: 255, g: 255, b: 255)),
            ),
            // A second colour the loudest bars reach.
            //
            // A bank in one flat colour is a chart; a bank that shifts as it
            // peaks reads as energy, which is the reason anyone puts one on a
            // storyboard.
            EffectParameter(
                id: Param.colorTop,
                name: "Peak Colour",
                group: "Look",
                defaultValue: .color(EffectColor(r: 255, g: 255, b: 255)),
            ),
            EffectParameter(
                id: Param.opacity,
                name: "Opacity",
                group: "Look",
                defaultValue: .number(1),
                range: 0...1,
                step: 0.05,
                presentation: .slider,
            ),
            EffectParameter(
                id: Param.additive,
                name: "Additive",
                group: "Look",
                defaultValue: .toggle(false),
            ),
        ],
    )

    public func evaluate(in context: EffectContext, rng: inout EffectRandom) -> [StoryboardSprite] {
        let bands = max(2, context.integer(Param.bands))
        let rate = max(5, Double(context.integer(Param.rate)))
        let width = context.number(Param.width)
        let gap = context.number(Param.gap)
        let peak = context.number(Param.height)
        let floor = min(context.number(Param.floorHeight), peak)
        let grounding = Grounding(rawValue: context.choice(Param.origin)) ?? .bottom
        let response = Response(rawValue: context.choice(Param.easing)) ?? .smooth
        let mirrored = context.toggle(Param.mirrored)
        let opacity = context.number(Param.opacity)
        let additive = context.toggle(Param.additive)
        let base = context.color(Param.color)
        let top = context.color(Param.colorTop)
        let path = context.text(Param.sprite)

        let duration = context.node.duration
        guard duration > 0, opacity > 0 else { return [] }

        let interval = 1000 / rate
        // Asked for in *song* time, because that is where the audio is: a clip
        // knows where it sits, and the analyser has no idea what a local zero
        // means.
        let start = context.node.startTime
        let spectrum = AudioSpectrum.levels(
            in: start ... (start + duration),
            bands: bands,
            interval: interval,
            using: context.audio,
        )
        guard !spectrum.isEmpty else { return [] }

        let layout = Layout(rawValue: context.choice(Param.layout)) ?? .line
        let element = Element(rawValue: context.choice(Param.element)) ?? .bar
        let placements = Self.placements(
            layout,
            count: bands,
            spacing: width + gap,
            radius: context.number(Param.radius),
            arcSpan: context.number(Param.arcSpan),
            sides: context.integer(Param.sides),
        )

        // Which way the bar extends from its root, along its own direction:
        // out from the root, back towards it, or straddling it.
        let extent: Double = switch grounding {
        case .bottom: 1
        case .top: -1
        case .centre: 0
        }

        var sprites: [StoryboardSprite] = []
        sprites.reserveCapacity(element == .segments ? bands * context.integer(Param.segments) : bands)

        for band in 0 ..< bands {
            // Mirrored, each half runs treble-out from the middle, so the two
            // sides answer the same frequencies rather than one holding the
            // bass and the other the treble.
            let source = mirrored
                ? abs(band - (bands - 1) / 2) * 2 * bands / max(1, bands)
                : band
            let reading = min(source, bands - 1)
            let place = placements[band]

            let levels = spectrum.levels.map { frame in
                Double(frame.indices.contains(reading) ? frame[reading] : 0)
            }
            let heights = levels.map { floor + (peak - floor) * $0 }

            let root = (
                x: TransformProperty.x.defaultValue + place.x,
                y: TransformProperty.y.defaultValue + place.y,
            )
            // A row points straight up, which is no rotation at all — and
            // writing one anyway would rewrite every bank already placed.
            let turn: Command? = abs(place.rotation) < 1e-9 ? nil : Command(
                easing: .linear, startTime: 0, endTime: duration,
                payload: .rotate(start: place.rotation, end: place.rotation),
            )
            let id = "\(context.node.id)/bar\(band)"

            switch element {
            case .bar:
                var commands = [hold(opacity, over: duration)]
                // The width never changes, so it is part of every frame's
                // command rather than a command of its own.
                let scaleX = width / Self.sourceSize
                for (index, height) in heights.enumerated() {
                    let at = Double(index) * interval
                    let next = min(at + interval, duration)
                    guard next > at else { continue }
                    let from = index == 0 ? height : heights[index - 1]
                    commands.append(Command(
                        easing: response.easing, startTime: at, endTime: next,
                        payload: .vectorScale(
                            startX: scaleX, startY: from / Self.sourceSize,
                            endX: scaleX, endY: height / Self.sourceSize,
                        ),
                    ))
                }
                if let turn { commands.append(turn) }
                commands += tint(base: base, top: top, heights: heights, floor: floor, peak: peak, over: duration)
                if additive { commands.append(glow(over: duration)) }
                sprites.append(StoryboardSprite(
                    id: id, layer: context.node.layer, origin: grounding.origin, filePath: path,
                    defaultX: root.x, defaultY: root.y, commands: commands, loops: [],
                ))

            case .dots:
                sprites.append(dot(
                    id: id, context: context, path: path, width: width, root: root,
                    direction: place.direction, heights: heights, extent: extent, peak: peak, floor: floor,
                    interval: interval, duration: duration, easing: response.easing,
                    opacity: opacity, additive: additive,
                    commands: tint(base: base, top: top, heights: heights, floor: floor, peak: peak, over: duration),
                ))

            case .segments:
                sprites += segments(
                    id: id, context: context, path: path, width: width, root: root, turn: turn,
                    direction: place.direction, levels: levels, extent: extent, peak: peak,
                    count: max(3, context.integer(Param.segments)), interval: interval,
                    duration: duration, opacity: opacity, additive: additive, base: base, top: top,
                )
            }
        }

        return sprites
    }

    private func hold(_ opacity: Double, over duration: Double) -> Command {
        // Held for the clip rather than faded: a bank is placed, and any
        // entrance it should have belongs to whoever placed it.
        Command(easing: .linear, startTime: 0, endTime: duration, payload: .fade(start: opacity, end: opacity))
    }

    private func glow(over duration: Double) -> Command {
        Command(easing: .linear, startTime: 0, endTime: duration, payload: .parameter(.additive))
    }

    private func colour(_ c: EffectColor, over duration: Double) -> Command {
        Command(
            easing: .linear, startTime: 0, endTime: duration,
            payload: .color(startR: c.r, startG: c.g, startB: c.b, endR: c.r, endG: c.g, endB: c.b),
        )
    }

    private static let white = EffectColor(r: 255, g: 255, b: 255)

    /// The bar's colour: the base, pulled toward the peak colour as far as
    /// this band's loudest reading reached — so a band that never peaks stays
    /// in the base colour. White writes nothing: a tint that changes nothing
    /// is a line of file for nothing, times every bar.
    private func tint(
        base: EffectColor,
        top: EffectColor,
        heights: [Double],
        floor: Double,
        peak: Double,
        over duration: Double,
    ) -> [Command] {
        if base != top {
            let loudest = heights.max() ?? floor
            let reach = peak > floor ? (loudest - floor) / (peak - floor) : 0
            return [colour(mix(base, top, reach), over: duration)]
        }
        return base == Self.white ? [] : [colour(base, over: duration)]
    }

    private func mix(_ a: EffectColor, _ b: EffectColor, _ t: Double) -> EffectColor {
        EffectColor(r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t)
    }

    /// The size a texture is drawn at, so a dot or a segment asked for in px
    /// comes out that size: the round shapes are 512, the straight ones 64.
    private func sourceSize(of path: String) -> Double {
        // The disc is one of the shapes but drawn large, so it is asked first.
        if path == BuiltInSprite.disc { return 512 }
        return BuiltInSprite.shapes.contains(path) ? 64 : 512
    }

    /// A dot riding where the bar's tip would be.
    ///
    /// It MOVES instead of scaling: one move per frame, the same cost as a
    /// bar. Drawn with the disc when the bank is left on its default bar
    /// texture — a square dot is a pixel, not a point — and with whatever the
    /// author chose otherwise.
    private func dot(
        id: String,
        context: EffectContext,
        path: String,
        width: Double,
        root: (x: Double, y: Double),
        direction: Double,
        heights: [Double],
        extent: Double,
        peak: Double,
        floor: Double,
        interval: Double,
        duration: Double,
        easing: Easing,
        opacity: Double,
        additive: Bool,
        commands tinting: [Command],
    ) -> StoryboardSprite {
        let file = path == BuiltInSprite.fill ? BuiltInSprite.disc : path
        // Out from the root, back towards it, or around it: a centred dot rides
        // either side of its line, which is what makes a row of them a wave.
        let along = { (height: Double) -> Double in
            extent == 0 ? height - (floor + peak) / 2 : height * extent
        }
        let at = { (height: Double) -> (x: Double, y: Double) in
            (root.x + cos(direction) * along(height), root.y + sin(direction) * along(height))
        }
        let size = width / sourceSize(of: file)

        var commands = [hold(opacity, over: duration)]
        commands.append(Command(
            easing: .linear, startTime: 0, endTime: duration,
            payload: .scale(start: size, end: size),
        ))
        for (index, height) in heights.enumerated() {
            let start = Double(index) * interval
            let next = min(start + interval, duration)
            guard next > start else { continue }
            let from = at(index == 0 ? height : heights[index - 1])
            let to = at(height)
            commands.append(Command(
                easing: easing, startTime: start, endTime: next,
                payload: .move(startX: from.x, startY: from.y, endX: to.x, endY: to.y),
            ))
        }
        commands += tinting
        if additive { commands.append(glow(over: duration)) }

        let first = at(heights.first ?? floor)
        return StoryboardSprite(
            id: id, layer: context.node.layer, origin: .centre, filePath: file,
            defaultX: first.x, defaultY: first.y, commands: commands, loops: [],
        )
    }

    /// A column of segments lighting up to the level, like an LED meter.
    ///
    /// Each segment only writes when it switches — lit or unlit — so a column
    /// holding still costs nothing, where a bar pays every frame. The colour
    /// ramps up the column, base at the root to peak at the top: green to red
    /// is the meter everyone knows.
    private func segments(
        id: String,
        context: EffectContext,
        path: String,
        width: Double,
        root: (x: Double, y: Double),
        turn: Command?,
        direction: Double,
        levels: [Double],
        extent: Double,
        peak: Double,
        count: Int,
        interval: Double,
        duration: Double,
        opacity: Double,
        additive: Bool,
        base: EffectColor,
        top: EffectColor,
    ) -> [StoryboardSprite] {
        let step = peak / Double(count)
        // A little gap between segments, or the column is one bar with lines
        // drawn across it.
        let length = step * 0.72
        let source = sourceSize(of: path)
        // A lit segment at the bank's opacity; an unlit one faint rather than
        // gone, so the meter's shape is there even in silence.
        let unlit = opacity * 0.12

        return (0 ..< count).map { index in
            let threshold = (Double(index) + 0.5) / Double(count)
            let offset: Double = extent == 0
                ? (Double(index) + 0.5) * step - peak / 2
                : (Double(index) + 0.5) * step * extent

            var commands: [Command] = []
            // Runs of one state, written as holds: a segment pays for each
            // switch, not for each frame.
            var runStart = 0.0
            var runLit = (levels.first ?? 0) >= threshold
            for (frame, level) in levels.enumerated() {
                let lit = level >= threshold
                let time = Double(frame) * interval
                if lit != runLit, time > runStart {
                    let value = runLit ? opacity : unlit
                    commands.append(Command(
                        easing: .linear, startTime: runStart, endTime: time,
                        payload: .fade(start: value, end: value),
                    ))
                    runStart = time
                    runLit = lit
                }
            }
            let last = runLit ? opacity : unlit
            commands.append(Command(
                easing: .linear, startTime: runStart, endTime: duration,
                payload: .fade(start: last, end: last),
            ))

            commands.append(Command(
                easing: .linear, startTime: 0, endTime: duration,
                payload: .vectorScale(
                    startX: width / source, startY: length / source,
                    endX: width / source, endY: length / source,
                ),
            ))
            if let turn { commands.append(turn) }
            let ramp = count > 1 ? Double(index) / Double(count - 1) : 0
            let shade = mix(base, top, ramp)
            if shade != Self.white { commands.append(colour(shade, over: duration)) }
            if additive { commands.append(glow(over: duration)) }

            return StoryboardSprite(
                id: "\(id)/seg\(index)", layer: context.node.layer, origin: .centre, filePath: path,
                defaultX: root.x + cos(direction) * offset,
                defaultY: root.y + sin(direction) * offset,
                commands: commands, loops: [],
            )
        }
    }

}
