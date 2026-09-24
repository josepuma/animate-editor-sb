import Foundation

/// A line — or strands of lines — drawn by the song.
///
/// **The shape comes from the music, and only from it.** Every point along
/// the wave is one band, and its distance from the line is that band's level
/// at that moment. The style decides how that energy is drawn — a saw that
/// alternates, or a smooth wave travelling along the line — but it multiplies
/// the level, so silence is a flat, still line whatever the style. A wave that
/// moved on its own would be decoration with a waveform's name.
///
/// **osu! draws no lines**, only sprites, so a line is a run of segments: a
/// thin `fill` per gap between two points, re-placed, re-turned and
/// re-stretched every frame — three commands per segment per frame. A dotted
/// line costs a third of that per point, since a dot only moves. The cost is
/// real, and it is why this belongs on a drop rather than under a whole song.
public struct AudioWavesEffect: Effect {
    public init() {}

    public enum Param {
        public static let points = "points"
        public static let layout = "layout"
        public static let width = "width"
        public static let radius = "radius"
        public static let height = "height"
        public static let style = "style"
        public static let waves = "waves"
        public static let flow = "flow"
        public static let smoothness = "smoothness"
        public static let drawAs = "drawAs"
        public static let thickness = "thickness"
        public static let dotSize = "dotSize"
        public static let strands = "strands"
        public static let lag = "lag"
        public static let spread = "spread"
        public static let falloff = "falloff"
        public static let rate = "rate"
        public static let color = "color"
        public static let colorEnd = "colorEnd"
        public static let opacity = "opacity"
        public static let additive = "additive"
    }

    public enum Layout: String, CaseIterable, Sendable {
        case line = "Line"
        case circle = "Circle"
    }

    public enum Style: String, CaseIterable, Sendable {
        /// Neighbouring points go opposite ways: a saw whose teeth are as tall
        /// as each band is loud.
        case zigzag = "Zigzag"
        /// The energy carried on a smooth wave travelling along the line, with
        /// the curve interpolated between points.
        case flowing = "Flowing"
    }

    public enum Draw: String, CaseIterable, Sendable {
        case line = "Line"
        case dots = "Dots"
        case both = "Both"
    }

    /// What a segment's texture measures, so a thickness asked for in px comes
    /// out that thick. `fill` is one of the straight shapes, drawn at 64.
    public static let segmentSource: Double = 64
    /// The disc a dot is drawn with is one of the round shapes, drawn at 512.
    public static let dotSource: Double = 512

    public static let descriptor = EffectDescriptor(
        type: "audioWaves",
        name: "Audio Waves",
        category: .audio,
        systemImage: "waveform.path",
        parameters: [
            // One per band, bass first.
            EffectParameter(id: Param.points, name: "Points", group: "Wave",
                            defaultValue: .integer(32), range: 4...64, step: 1),
            EffectParameter(id: Param.layout, name: "Layout", group: "Wave",
                            defaultValue: .choice(Layout.line.rawValue),
                            options: Layout.allCases.map(\.rawValue)),
            EffectParameter(id: Param.width, name: "Length", group: "Wave",
                            defaultValue: .number(600), range: 40...854, step: 1, unit: "px",
                            shownWhen: .init(parameter: Param.layout, isAnyOf: [Layout.line.rawValue])),
            EffectParameter(id: Param.radius, name: "Radius", group: "Wave",
                            defaultValue: .number(120), range: 10...400, step: 1, unit: "px",
                            shownWhen: .init(parameter: Param.layout, isAnyOf: [Layout.circle.rawValue])),
            // How far a point at full volume reaches from the line.
            EffectParameter(id: Param.height, name: "Amplitude", group: "Wave",
                            defaultValue: .number(80), range: 4...300, step: 1, unit: "px"),
            EffectParameter(id: Param.style, name: "Style", group: "Wave",
                            defaultValue: .choice(Style.zigzag.rawValue),
                            options: Style.allCases.map(\.rawValue)),
            // How many crests the flowing wave has along its length.
            EffectParameter(id: Param.waves, name: "Waves", group: "Wave",
                            defaultValue: .number(3), range: 0.5...12, step: 0.5,
                            shownWhen: .init(parameter: Param.style, isAnyOf: [Style.flowing.rawValue])),
            // How fast the crests travel, in crests per second. Only ever seen
            // over sound: it moves the shape the energy is drawn on, and with no
            // energy there is nothing to move.
            EffectParameter(id: Param.flow, name: "Flow", group: "Wave",
                            defaultValue: .number(0.3), range: -3...3, step: 0.05,
                            shownWhen: .init(parameter: Param.style, isAnyOf: [Style.flowing.rawValue])),
            // Samples between two points. Each is a sprite per strand, so this
            // is the price of a smoother curve.
            EffectParameter(id: Param.smoothness, name: "Smoothness", group: "Wave",
                            defaultValue: .integer(3), range: 1...6, step: 1,
                            shownWhen: .init(parameter: Param.style, isAnyOf: [Style.flowing.rawValue])),

            EffectParameter(id: Param.drawAs, name: "Draw As", group: "Look",
                            defaultValue: .choice(Draw.line.rawValue),
                            options: Draw.allCases.map(\.rawValue)),
            EffectParameter(id: Param.thickness, name: "Thickness", group: "Look",
                            defaultValue: .number(3), range: 1...20, step: 0.5, unit: "px"),
            EffectParameter(id: Param.dotSize, name: "Dot Size", group: "Look",
                            defaultValue: .number(5), range: 1...30, step: 0.5, unit: "px"),
            EffectParameter(id: Param.color, name: "Colour", group: "Look",
                            defaultValue: .color(EffectColor(r: 255, g: 255, b: 255))),
            // What the last strand shades to, so a bundle reads as depth.
            EffectParameter(id: Param.colorEnd, name: "Back Colour", group: "Look",
                            defaultValue: .color(EffectColor(r: 255, g: 255, b: 255))),
            EffectParameter(id: Param.opacity, name: "Opacity", group: "Look",
                            defaultValue: .number(1), range: 0...1, step: 0.05, presentation: .slider),
            EffectParameter(id: Param.additive, name: "Additive", group: "Look",
                            defaultValue: .toggle(false)),

            // ─── Strands ─────────────────────────────────────────────────
            //
            // Copies of the wave, each hearing the SAME song a little later.
            // The delay is what makes a bundle flow like silk rather than move
            // as one block: a hit runs down the strands one after another.
            EffectParameter(id: Param.strands, name: "Strands", group: "Strands",
                            defaultValue: .integer(1), range: 1...8, step: 1),
            EffectParameter(id: Param.lag, name: "Lag", group: "Strands",
                            defaultValue: .number(60), range: 0...500, step: 5, unit: "ms"),
            EffectParameter(id: Param.spread, name: "Spread", group: "Strands",
                            defaultValue: .number(8), range: 0...80, step: 1, unit: "px"),
            // How much fainter and thinner the strands behind are.
            EffectParameter(id: Param.falloff, name: "Falloff", group: "Strands",
                            defaultValue: .number(0.5), range: 0...1, step: 0.05),

            // Every frame is a command per point — three per segment — so this
            // is the number that decides whether the file opens.
            EffectParameter(id: Param.rate, name: "Frame Rate", group: "Motion",
                            defaultValue: .integer(20), range: 5...30, step: 1, unit: "fps"),
        ],
    )

    public func evaluate(in context: EffectContext, rng _: inout EffectRandom) -> [StoryboardSprite] {
        let duration = context.node.duration
        let opacity = context.number(Param.opacity)
        guard duration > 0, opacity > 0 else { return [] }

        let points = max(4, context.integer(Param.points))
        let layout = Layout(rawValue: context.choice(Param.layout)) ?? .line
        let style = Style(rawValue: context.choice(Param.style)) ?? .zigzag
        let draw = Draw(rawValue: context.choice(Param.drawAs)) ?? .line
        let height = context.number(Param.height)
        let strands = max(1, context.integer(Param.strands))
        let lag = max(0, context.number(Param.lag))
        let spread = context.number(Param.spread)
        let falloff = min(max(context.number(Param.falloff), 0), 1)
        let interval = 1000 / Double(max(5, context.integer(Param.rate)))
        let subdivide = style == .flowing ? max(1, context.integer(Param.smoothness)) : 1
        let front = context.color(Param.color)
        let back = context.color(Param.colorEnd)
        let additive = context.toggle(Param.additive)

        // Asked for in SONG time, reaching back far enough that the last
        // strand has something to hear from its first frame.
        let reach = lag * Double(strands - 1)
        let start = context.node.startTime
        let frames = AudioSpectrum.levels(
            in: (start - reach) ... (start + duration),
            bands: points,
            interval: interval,
            using: context.audio,
        ).levels
        guard !frames.isEmpty else { return [] }

        /// A band's level at a clip-local moment, read `delay` ms late.
        func level(_ band: Int, at time: Double, delay: Double) -> Double {
            let index = Int(((time - delay + reach) / interval).rounded(.down))
            let frame = frames[min(max(0, index), frames.count - 1)]
            return Double(frame.indices.contains(band) ? frame[band] : 0)
        }

        let base = Base(layout: layout, points: points, subdivide: subdivide,
                        width: context.number(Param.width), radius: context.number(Param.radius))
        let steps = max(1, Int((duration / interval).rounded(.up)))
        let times = (0 ... steps).map { min(duration, Double($0) * interval) }

        var sprites: [StoryboardSprite] = []

        // Back to front: the strand drawn last sits on top, and the lead
        // strand is the one in front.
        for strand in (0 ..< strands).reversed() {
            let depth = strands > 1 ? Double(strand) / Double(strands - 1) : 0
            let delay = lag * Double(strand)
            let fade = opacity * (1 - falloff * depth)
            let size = 1 - falloff * 0.5 * depth
            let shade = EffectColor(
                r: front.r + (back.r - front.r) * depth,
                g: front.g + (back.g - front.g) * depth,
                b: front.b + (back.b - front.b) * depth,
            )

            // Every sample of this strand at every frame.
            let paths: [[(x: Double, y: Double)]] = times.map { time in
                let offsets = (0 ..< points).map { band -> Double in
                    let energy = level(band, at: time, delay: delay) * height
                    switch style {
                    case .zigzag:
                        return band.isMultiple(of: 2) ? energy : -energy
                    case .flowing:
                        let along = base.fraction(ofPoint: band)
                        let phase = 2 * .pi * (context.number(Param.waves) * along
                            - context.number(Param.flow) * time / 1000)
                        return energy * sin(phase)
                    }
                }
                return base.samples(offsets: offsets, shift: spread * Double(strand))
            }

            let prefix = "\(context.node.id)/s\(strand)"
            let colour = shade == EffectColor(r: 255, g: 255, b: 255) ? nil : shade

            if draw != .dots {
                sprites += segments(
                    prefix: prefix, paths: paths, times: times, closed: base.closed,
                    thickness: context.number(Param.thickness) * size, opacity: fade,
                    colour: colour, additive: additive, layer: context.node.layer,
                )
            }
            if draw != .line {
                sprites += dots(
                    prefix: prefix, paths: paths, times: times,
                    size: context.number(Param.dotSize) * size, opacity: fade,
                    colour: colour, additive: additive, layer: context.node.layer,
                )
            }
        }
        return sprites
    }

    // ─── The line the wave rides on ──────────────────────────────────────────

    /// Where the samples sit before the song moves them, and which way "away
    /// from the line" is at each.
    private struct Base {
        let layout: Layout
        let points: Int
        let subdivide: Int
        let width: Double
        let radius: Double

        var closed: Bool { layout == .circle }

        /// How far along the wave a point is, 0…1.
        func fraction(ofPoint index: Int) -> Double {
            closed ? Double(index) / Double(points) : Double(index) / Double(points - 1)
        }

        /// The samples, displaced by `offsets` (one per point, interpolated
        /// between them) and shifted a strand's spread outward.
        func samples(offsets: [Double], shift: Double) -> [(x: Double, y: Double)] {
            let gaps = closed ? points : points - 1
            let count = gaps * subdivide + (closed ? 0 : 1)
            return (0 ..< count).map { sample in
                let position = Double(sample) / Double(subdivide)
                let offset = interpolate(offsets, at: position) + shift
                let along = closed ? position / Double(points) : position / Double(points - 1)
                switch layout {
                case .line:
                    // Up is away from the line: storyboard Y grows downward.
                    let x = TransformProperty.x.defaultValue - width / 2 + width * along
                    return (x, TransformProperty.y.defaultValue - offset)
                case .circle:
                    let angle = -Double.pi / 2 + 2 * .pi * along
                    let r = radius + offset
                    return (TransformProperty.x.defaultValue + cos(angle) * r,
                            TransformProperty.y.defaultValue + sin(angle) * r)
                }
            }
        }

        /// Catmull-Rom between points, so a flowing wave curves rather than
        /// zigzagging between its samples. At a whole position it is the point
        /// itself — the curve passes through every band.
        private func interpolate(_ values: [Double], at position: Double) -> Double {
            let i = Int(position.rounded(.down))
            let t = position - Double(i)
            guard t > 1e-9 else { return value(values, i) }
            let p0 = value(values, i - 1), p1 = value(values, i)
            let p2 = value(values, i + 1), p3 = value(values, i + 2)
            let t2 = t * t, t3 = t2 * t
            return 0.5 * ((2 * p1) + (-p0 + p2) * t
                + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
        }

        private func value(_ values: [Double], _ index: Int) -> Double {
            if closed { return values[((index % points) + points) % points] }
            return values[min(max(0, index), points - 1)]
        }
    }

    // ─── Drawing ─────────────────────────────────────────────────────────────

    private func held(_ opacity: Double, colour: EffectColor?, additive: Bool, until end: Double) -> [Command] {
        var commands = [Command(easing: .linear, startTime: 0, endTime: end,
                                payload: .fade(start: opacity, end: opacity))]
        if let colour {
            commands.append(Command(easing: .linear, startTime: 0, endTime: end, payload: .color(
                startR: colour.r, startG: colour.g, startB: colour.b,
                endR: colour.r, endG: colour.g, endB: colour.b,
            )))
        }
        if additive {
            commands.append(Command(easing: .linear, startTime: 0, endTime: end, payload: .parameter(.additive)))
        }
        return commands
    }

    /// A dot per sample, moving frame to frame.
    private func dots(
        prefix: String, paths: [[(x: Double, y: Double)]], times: [Double],
        size: Double, opacity: Double, colour: EffectColor?, additive: Bool, layer: Layer,
    ) -> [StoryboardSprite] {
        guard let first = paths.first, let end = times.last else { return [] }
        let scale = size / Self.dotSource

        return first.indices.map { sample in
            var commands = held(opacity, colour: colour, additive: additive, until: end)
            commands.append(Command(easing: .linear, startTime: 0, endTime: end,
                                    payload: .scale(start: scale, end: scale)))
            for step in 0 ..< times.count - 1 where times[step + 1] > times[step] {
                let a = paths[step][sample], b = paths[step + 1][sample]
                commands.append(Command(easing: .linear, startTime: times[step], endTime: times[step + 1],
                                        payload: .move(startX: a.x, startY: a.y, endX: b.x, endY: b.y)))
            }
            return StoryboardSprite(
                id: "\(prefix)/dot\(sample)", layer: layer, origin: .centre, filePath: BuiltInSprite.disc,
                defaultX: first[sample].x, defaultY: first[sample].y, commands: commands, loops: [],
            )
        }
    }

    /// A segment per gap between samples: placed at the midpoint, turned along
    /// the gap and stretched to its length, every frame.
    ///
    /// Turned by the gap's direction plus a quarter — the rotation that points
    /// a sprite drawn "up" along it, the same `Placement.rotation` Audio Bars
    /// uses. Unwrapped frame to frame, or a segment crossing ±π spins a full
    /// turn between two frames where it only moved a degree.
    private func segments(
        prefix: String, paths: [[(x: Double, y: Double)]], times: [Double], closed: Bool,
        thickness: Double, opacity: Double, colour: EffectColor?, additive: Bool, layer: Layer,
    ) -> [StoryboardSprite] {
        guard let first = paths.first, let end = times.last, first.count >= 2 else { return [] }
        let gaps = closed ? first.count : first.count - 1
        let width = thickness / Self.segmentSource

        func geometry(_ path: [(x: Double, y: Double)], _ gap: Int) -> (x: Double, y: Double, turn: Double, length: Double) {
            let a = path[gap], b = path[(gap + 1) % path.count]
            let dx = b.x - a.x, dy = b.y - a.y
            return ((a.x + b.x) / 2, (a.y + b.y) / 2, atan2(dy, dx) + .pi / 2, hypot(dx, dy))
        }

        return (0 ..< gaps).map { gap in
            var commands = held(opacity, colour: colour, additive: additive, until: end)
            var previous = geometry(paths[0], gap)
            for step in 0 ..< times.count - 1 where times[step + 1] > times[step] {
                var next = geometry(paths[step + 1], gap)
                while next.turn - previous.turn > .pi { next.turn -= 2 * .pi }
                while next.turn - previous.turn < -.pi { next.turn += 2 * .pi }
                let (t0, t1) = (times[step], times[step + 1])
                commands.append(Command(easing: .linear, startTime: t0, endTime: t1,
                                        payload: .move(startX: previous.x, startY: previous.y, endX: next.x, endY: next.y)))
                commands.append(Command(easing: .linear, startTime: t0, endTime: t1,
                                        payload: .rotate(start: previous.turn, end: next.turn)))
                commands.append(Command(easing: .linear, startTime: t0, endTime: t1, payload: .vectorScale(
                    startX: width, startY: previous.length / Self.segmentSource,
                    endX: width, endY: next.length / Self.segmentSource,
                )))
                previous = next
            }
            let start = geometry(paths[0], gap)
            return StoryboardSprite(
                id: "\(prefix)/seg\(gap)", layer: layer, origin: .centre, filePath: BuiltInSprite.fill,
                defaultX: start.x, defaultY: start.y, commands: commands, loops: [],
            )
        }
    }
}
