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

    /// Installed once by whoever can read the track.
    ///
    /// Asked for a stretch of the song rather than the whole thing, because
    /// that is what a clip covers: analysing five minutes to animate eight
    /// seconds is work nobody sees.
    nonisolated(unsafe) public static var analyse: (
        @Sendable (_ range: ClosedRange<Double>, _ bands: Int, _ interval: Double) -> Frames?
    )?

    /// The levels for a stretch of the song, real or stood in for.
    public static func levels(
        in range: ClosedRange<Double>,
        bands: Int,
        interval: Double,
    ) -> Frames {
        if let analyse, let real = analyse(range, bands, interval), !real.isEmpty {
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
                // Falling towards the treble, the way most music sits, with a
                // wave running along it so the bars move against each other.
                let tilt = 1 - position * 0.55
                let wave = 0.5 + 0.5 * sin(time * 6 - position * 5)
                return Float(min(1, max(0, tilt * (0.35 + wave * 0.65))))
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

    /// The source image is 64px square, which is what the built-in shapes are
    /// drawn at.
    public static let sourceSize: Double = 512

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
                defaultValue: .text(BuiltInSprite.square),
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
        )
        guard !spectrum.isEmpty else { return [] }

        // Laid out around the clip's centre, because a transform turns and
        // scales about that point: a bank laid out from one corner would sweep
        // one end round when rotated.
        let spacing = width + gap
        let span = spacing * Double(bands) - gap
        let left = -span / 2 + width / 2

        var sprites: [StoryboardSprite] = []
        sprites.reserveCapacity(bands)

        for band in 0 ..< bands {
            // Mirrored, each half runs treble-out from the middle, so the two
            // sides answer the same frequencies rather than one holding the
            // bass and the other the treble.
            let source = mirrored
                ? abs(band - (bands - 1) / 2) * 2 * bands / max(1, bands)
                : band
            let reading = min(source, bands - 1)

            var sprite = StoryboardSprite(
                id: "\(context.node.id)/bar\(band)",
                layer: context.node.layer,
                origin: grounding.origin,
                filePath: path,
                defaultX: TransformProperty.x.defaultValue + left + spacing * Double(band),
                defaultY: TransformProperty.y.defaultValue,
                commands: [],
                loops: [],
            )

            // The bar's width never changes, so it is one command for the life
            // of the clip: only the height answers the music.
            let scaleX = width / Self.sourceSize

            var heights: [Double] = []
            heights.reserveCapacity(spectrum.levels.count)
            for frame in spectrum.levels {
                let level = Double(frame.indices.contains(reading) ? frame[reading] : 0)
                heights.append(floor + (peak - floor) * level)
            }

            var commands: [Command] = []
            commands.reserveCapacity(heights.count + 3)

            // Held for the clip rather than faded: a bank is placed, and any
            // entrance it should have belongs to whoever placed it.
            commands.append(Command(
                easing: .linear,
                startTime: 0,
                endTime: duration,
                payload: .fade(start: opacity, end: opacity),
            ))

            for (index, height) in heights.enumerated() {
                let at = Double(index) * interval
                let next = min(at + interval, duration)
                guard next > at else { continue }

                let from = index == 0 ? height : heights[index - 1]
                commands.append(Command(
                    easing: response.easing,
                    startTime: at,
                    endTime: next,
                    payload: .vectorScale(
                        startX: scaleX,
                        startY: from / Self.sourceSize,
                        endX: scaleX,
                        endY: height / Self.sourceSize,
                    ),
                ))
            }

            if base != top {
                // The tint follows the tallest reading this bar reaches, so a
                // band that never peaks stays in the base colour.
                let loudest = heights.max() ?? floor
                let reach = peak > floor ? (loudest - floor) / (peak - floor) : 0
                let tint = EffectColor(
                    r: base.r + (top.r - base.r) * reach,
                    g: base.g + (top.g - base.g) * reach,
                    b: base.b + (top.b - base.b) * reach,
                )
                commands.append(Command(
                    easing: .linear,
                    startTime: 0,
                    endTime: duration,
                    payload: .color(
                        startR: tint.r, startG: tint.g, startB: tint.b,
                        endR: tint.r, endG: tint.g, endB: tint.b,
                    ),
                ))
            } else if base != EffectColor(r: 255, g: 255, b: 255) {
                commands.append(Command(
                    easing: .linear,
                    startTime: 0,
                    endTime: duration,
                    payload: .color(
                        startR: base.r, startG: base.g, startB: base.b,
                        endR: base.r, endG: base.g, endB: base.b,
                    ),
                ))
            }

            if additive {
                commands.append(Command(
                    easing: .linear,
                    startTime: 0,
                    endTime: duration,
                    payload: .parameter(.additive),
                ))
            }

            sprite.commands = commands
            sprites.append(sprite)
        }

        return sprites
    }
}
