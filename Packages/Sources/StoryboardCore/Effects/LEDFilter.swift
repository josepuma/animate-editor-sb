import Foundation

/// Redraws whatever is on the track as a grid of dots: an LED sign.
///
/// ## A texture, not a sprite per dot
///
/// The obvious way to build the look is one sprite per lit dot. Forty
/// characters at a pitch of 8 are around three thousand of them, each with its
/// own commands in the file — a storyboard osu! would struggle to open. Here
/// each glyph keeps being **one** sprite, and its image is swapped for a
/// dot-matrix version of itself (``DerivedSprite/dotMatrix(_:pitch:dotSize:shape:threshold:)``):
/// the same bargain ``BlurFilter`` makes, softness in the pixels instead of
/// sprites. Cost: ×1.
///
/// ## The lattice
///
/// Each glyph is rasterised on its own and text is laid out by font advances,
/// which are not multiples of anything. Left alone, the dots of neighbouring
/// letters land a fraction of a pitch apart — and a dot matrix whose dots do
/// not line up reads as fake immediately, because the regularity **is** the
/// look.
///
/// So every sprite is moved onto one lattice anchored at the stage origin
/// (−107, 0), and the dot texture is built so its own cells fall on it:
///
/// - the texture is an even number of whole cells each way, so every anchor of
///   the sprite (left edge, centre, right edge) is a whole number of pitches
///   from the texture's edge — the filter never needs to know the image's size;
/// - the source is centred in that canvas, so ink keeps its place relative to
///   the sprite's position;
/// - positions, and the endpoints of every movement, are rounded to the lattice.
///
/// ### Where the alignment stops
///
/// It is exact for a sprite at **scale 1 and rotation 0**. A scaled sprite's
/// dots are scaled too — its pitch is no longer the lattice's — and a rotated
/// one turns its grid; both keep their own. The same goes for a camera that
/// zooms or pans, which the filter runs too early to see. That covers text and
/// images at rest, which is what a sign is; an entrance that scales in lands on
/// the lattice when it settles.
///
/// ### Stepped movement
///
/// A sign's lights jump a dot at a time; they do not slide. With ``Param/stepMotion``
/// a movement is written as a staircase of whole-pitch jumps, so a moving
/// glyph stays on the lattice *between* its endpoints too. Every step is a
/// command, per glyph, so a move is capped at ``maximumSteps`` — a longer one
/// takes bigger jumps (still whole pitches) rather than more of them. Loops
/// inside a sprite are left alone.
///
/// ## Out of scope
///
/// Lighting individual dots over time — a scrolling marquee, a sweep across a
/// static panel — needs a sprite per dot. That is exactly the cost this filter
/// exists to avoid; it is not offered.
public struct LEDFilter: SpriteFilter {
    public init() {}

    /// The most steps one movement command is broken into.
    public static let maximumSteps = 24

    /// The largest panel texture, in pixels a side.
    private static let maximumPanelPixels = 4096

    public enum Param {
        public static let pitch = "pitch"
        public static let dotSize = "dotSize"
        public static let shape = "shape"
        public static let threshold = "threshold"
        public static let stepMotion = "stepMotion"
        public static let panel = "panel"
        public static let panelMargin = "panelMargin"
        public static let panelColour = "panelColour"
        public static let panelOpacity = "panelOpacity"
    }

    /// What sits behind the lit dots.
    public enum Panel: String, CaseIterable, Sendable {
        case off = "Off"
        /// The whole stage.
        case stage = "Stage"
        /// Around the sign: its own extent plus a margin.
        case clip = "Clip"
    }

    private enum ShapeName {
        static let round = "Round"
        static let square = "Square"
    }

    public static let descriptor = FilterDescriptor(
        type: "led",
        name: "LED",
        category: .look,
        systemImage: "circle.grid.3x3.fill",
        parameters: [
            EffectParameter(
                id: Param.pitch, name: "Pitch", group: "Dots",
                defaultValue: .number(8),
                range: 3...32,
                step: 1, unit: "px",
            ),
            EffectParameter(
                id: Param.dotSize, name: "Dot Size", group: "Dots",
                defaultValue: .number(0.7), range: 0.2...1, step: 0.05,
                presentation: .slider,
            ),
            EffectParameter(
                id: Param.shape, name: "Dot Shape", group: "Dots",
                defaultValue: .choice(ShapeName.round),
                options: [ShapeName.round, ShapeName.square],
            ),
            // How much of a cell the picture must cover to light it. Low keeps
            // thin strokes and rounds corners off; high thins everything.
            EffectParameter(
                id: Param.threshold, name: "Threshold", group: "Dots",
                defaultValue: .number(0.4), range: 0.05...0.95, step: 0.05,
                presentation: .slider,
            ),
            EffectParameter(
                id: Param.stepMotion, name: "Step Motion", group: "Motion",
                defaultValue: .toggle(true),
            ),
            EffectParameter(
                id: Param.panel, name: "Panel", group: "Panel",
                defaultValue: .choice(Panel.off.rawValue),
                options: Panel.allCases.map(\.rawValue),
            ),
            // Only a panel around the sign has a margin to set.
            EffectParameter(
                id: Param.panelMargin, name: "Margin", group: "Panel",
                defaultValue: .number(32), range: 0...400, step: 4, unit: "px",
                shownWhen: .init(parameter: Param.panel, isAnyOf: [Panel.clip.rawValue]),
            ),
            EffectParameter(
                id: Param.panelColour, name: "Unlit Colour", group: "Panel",
                defaultValue: .color(EffectColor(r: 110, g: 92, b: 18)),
                shownWhen: .init(
                    parameter: Param.panel,
                    isAnyOf: [Panel.stage.rawValue, Panel.clip.rawValue],
                ),
            ),
            EffectParameter(
                id: Param.panelOpacity, name: "Unlit Opacity", group: "Panel",
                defaultValue: .number(0.6), range: 0...1, step: 0.05,
                presentation: .slider,
                shownWhen: .init(
                    parameter: Param.panel,
                    isAnyOf: [Panel.stage.rawValue, Panel.clip.rawValue],
                ),
            ),
        ],
    )

    // ─── Apply ───────────────────────────────────────────────────────────────

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        guard !sprites.isEmpty else { return sprites }

        // The pitch the texture will actually have. Quantised exactly as the
        // path quantises it, or the lattice and the dots disagree by a
        // fraction and the whole point is lost.
        let pitch = quantisedPitch(context.number(Param.pitch))
        let dotSize = context.number(Param.dotSize)
        let shape: DerivedSprite.DotShape =
            context.choice(Param.shape) == ShapeName.square ? .square : .round
        let threshold = context.number(Param.threshold)
        let stepped = context.toggle(Param.stepMotion)

        let lit = sprites.map { sprite -> StoryboardSprite in
            var copy = sprite
            copy.filePath = DerivedSprite.dotMatrix(
                sprite.filePath, pitch: Double(pitch), dotSize: dotSize,
                shape: shape, threshold: threshold,
            )
            copy.defaultX = DotGrid.snap(sprite.defaultX, origin: DotGrid.originX, pitch: Double(pitch))
            copy.defaultY = DotGrid.snap(sprite.defaultY, origin: DotGrid.originY, pitch: Double(pitch))
            copy.commands = sprite.commands.flatMap {
                Self.snapped($0, pitch: Double(pitch), stepped: stepped)
            }
            return copy
        }

        guard let panel = panel(behind: lit, pitch: pitch, dotSize: dotSize, shape: shape, in: context)
        else { return lit }

        // Behind the dots: in front, the unlit ones would cover the lit.
        return [panel] + lit
    }

    /// One image swap per sprite, and one extra sprite for the panel.
    public func estimatedMultiplier(in context: FilterContext) -> Double { 1 }

    private func quantisedPitch(_ value: Double) -> Int {
        min(
            DerivedSprite.dotPitchRange.upperBound,
            max(DerivedSprite.dotPitchRange.lowerBound, Int(value.rounded())),
        )
    }

    // ─── Movement ────────────────────────────────────────────────────────────

    /// A movement command with its endpoints on the lattice, as a staircase
    /// when asked; any other command untouched.
    private static func snapped(_ command: Command, pitch: Double, stepped: Bool) -> [Command] {
        func x(_ value: Double) -> Double { DotGrid.snap(value, origin: DotGrid.originX, pitch: pitch) }
        func y(_ value: Double) -> Double { DotGrid.snap(value, origin: DotGrid.originY, pitch: pitch) }

        switch command.payload {
        case let .move(sx, sy, ex, ey):
            return staircase(
                command, from: (sx, sy), to: (ex, ey), pitch: pitch, stepped: stepped,
                snap: { (x($0), y($1)) },
                make: { .move(startX: $0, startY: $1, endX: $0, endY: $1) },
                whole: { .move(startX: $0.0, startY: $0.1, endX: $1.0, endY: $1.1) },
            )
        case let .moveX(start, end):
            return staircase(
                command, from: (start, 0), to: (end, 0), pitch: pitch, stepped: stepped,
                snap: { value, _ in (x(value), 0) },
                make: { value, _ in .moveX(start: value, end: value) },
                whole: { .moveX(start: $0.0, end: $1.0) },
            )
        case let .moveY(start, end):
            return staircase(
                command, from: (0, start), to: (0, end), pitch: pitch, stepped: stepped,
                snap: { _, value in (0, y(value)) },
                make: { _, value in .moveY(start: value, end: value) },
                whole: { .moveY(start: $0.1, end: $1.1) },
            )
        default:
            return [command]
        }
    }

    /// Breaks one movement into instantaneous holds a pitch or more apart.
    ///
    /// Each hold is a zero-length command: the sprite sits on the lattice until
    /// the next one, which is what makes it jump rather than glide. Positions
    /// are sampled along the command's own easing, so a decelerating move
    /// still decelerates — in steps.
    private static func staircase(
        _ command: Command,
        from: (Double, Double),
        to: (Double, Double),
        pitch: Double,
        stepped: Bool,
        snap: (Double, Double) -> (Double, Double),
        make: (Double, Double) -> Command.Payload,
        whole: ((Double, Double), (Double, Double)) -> Command.Payload,
    ) -> [Command] {
        let start = snap(from.0, from.1)
        let end = snap(to.0, to.1)
        let duration = command.endTime - command.startTime
        let distance = max(abs(to.0 - from.0), abs(to.1 - from.1))
        let wanted = Int((distance / pitch).rounded(.up))

        // Nothing to step: a single glide between snapped endpoints, or a hold.
        guard stepped, duration > 0, wanted > 1 else {
            return [Command(timing: command.timing, payload: whole(start, end))]
        }

        let steps = min(maximumSteps, wanted)
        var commands: [Command] = []
        var last: (Double, Double)?

        func hold(at time: Double, _ position: (Double, Double)) {
            // A step that lands where the last one did is not a step.
            if let last, last.0 == position.0, last.1 == position.1 { return }
            last = position
            commands.append(Command(
                easing: .linear, startTime: time, endTime: time,
                payload: make(position.0, position.1),
            ))
        }

        for index in 0..<steps {
            let progress = Double(index) / Double(steps)
            let eased = applyEasing(command.easing, progress)
            hold(at: command.startTime + duration * progress, snap(
                from.0 + (to.0 - from.0) * eased,
                from.1 + (to.1 - from.1) * eased,
            ))
        }
        hold(at: command.endTime, end)
        return commands
    }

    // ─── Panel ───────────────────────────────────────────────────────────────

    /// The unlit dots behind the sign, or `nil` when there is no panel.
    private func panel(
        behind sprites: [StoryboardSprite],
        pitch: Int,
        dotSize: Double,
        shape: DerivedSprite.DotShape,
        in context: FilterContext,
    ) -> StoryboardSprite? {
        let mode = Panel(rawValue: context.choice(Param.panel)) ?? .off
        let opacity = context.number(Param.panelOpacity)
        guard mode != .off, opacity > 0, let first = sprites.first else { return nil }

        let step = Double(pitch)
        let left: Double
        let top: Double
        let width: Double
        let height: Double

        switch mode {
        case .stage, .off:
            left = DotGrid.originX
            top = DotGrid.originY
            width = StageSnap.Stage.width
            height = StageSnap.Stage.height
        case .clip:
            // Where the sprites are, by their positions: Core cannot open the
            // images, so their extent is not known — the margin is how the
            // author says how much room a glyph needs around its centre.
            let points = sprites.flatMap(Self.positions)
            let margin = context.number(Param.panelMargin)
            let minX = points.map(\.x).min() ?? 0
            let maxX = points.map(\.x).max() ?? 0
            let minY = points.map(\.y).min() ?? 0
            let maxY = points.map(\.y).max() ?? 0

            left = DotGrid.floor(minX - margin, origin: DotGrid.originX, pitch: step)
            top = DotGrid.floor(minY - margin, origin: DotGrid.originY, pitch: step)
            width = maxX + margin - left
            height = maxY + margin - top
        }

        // Even cell counts, for the same reason the dot texture has them, and
        // never past what the atlas takes.
        let limit = (Self.maximumPanelPixels / pitch) & ~1
        let columns = min(limit, DerivedSprite.cells(covering: width, pitch: pitch))
        let rows = min(limit, DerivedSprite.cells(covering: height, pitch: pitch))

        let starts = sprites.flatMap(\.commands).map(\.startTime)
        let ends = sprites.flatMap(\.commands).map(\.endTime)
        let birth = starts.min() ?? 0
        // A sprite of zero length is never drawn.
        let death = max(ends.max() ?? birth, birth + 1)

        let tint = context.color(Param.panelColour)
        return StoryboardSprite(
            id: "\(context.idPrefix)/panel",
            layer: first.layer,
            origin: .topLeft,
            filePath: DerivedSprite.dotPanel(
                columns: columns, rows: rows, pitch: step, dotSize: dotSize, shape: shape,
            ),
            defaultX: left,
            defaultY: top,
            commands: [
                Command(
                    easing: .linear, startTime: birth, endTime: death,
                    payload: .fade(start: opacity, end: opacity),
                ),
                Command(
                    easing: .linear, startTime: birth, endTime: birth,
                    payload: .color(
                        startR: tint.r, startG: tint.g, startB: tint.b,
                        endR: tint.r, endG: tint.g, endB: tint.b,
                    ),
                ),
            ],
        )
    }

    /// Every position a sprite occupies: where it rests and where it goes.
    private static func positions(of sprite: StoryboardSprite) -> [(x: Double, y: Double)] {
        var points: [(x: Double, y: Double)] = [(sprite.defaultX, sprite.defaultY)]
        for command in sprite.commands {
            switch command.payload {
            case let .move(sx, sy, ex, ey):
                points.append((sx, sy))
                points.append((ex, ey))
            case let .moveX(start, end):
                points.append((start, sprite.defaultY))
                points.append((end, sprite.defaultY))
            case let .moveY(start, end):
                points.append((sprite.defaultX, start))
                points.append((sprite.defaultX, end))
            default:
                break
            }
        }
        return points
    }
}
