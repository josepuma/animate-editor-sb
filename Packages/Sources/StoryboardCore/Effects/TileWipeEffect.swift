import Foundation

/// A wipe made of tiles: a grid of hard squares that sweeps across the stage as
/// a rippling curtain, covers it, holds, and lets it go again.
///
/// **Why an effect and not a preset.** Every piece of this exists elsewhere and
/// none of them can be composed into it without faking:
///
/// - An emitter writes one linear scale command per particle, so it cannot do
///   in → hold → out; and a wipe that covers the screen is the case the
///   emitter's coverage tests exist to reject.
/// - A `Shape` clip under a Grid filter gets every cell landing on the same
///   curve; Grid's delay orders are rows, columns, diagonal and from-centre —
///   all straight fronts. A wave front needs a delay that depends on *both*
///   axes at once, and a pop-out needs the cell's own commands to differ.
///
/// So this writes the cells itself: one sprite per cell, two scale commands
/// each — from nothing in, to nothing out — and the sprite lives only between
/// them, so nothing is on screen before or after.
///
/// **The front is a wave.** A cell's delay is a blend of how far along the
/// sweep it sits and a sine over the perpendicular axis. `Wave` is the share of
/// the sweep given to the sine: at 0 the front is straight, and the delays are
/// always inside `0...sweep` so the wipe never runs past its clip.
///
/// **Hold is when the stage is fully covered.** Every cell is in by
/// `sweep + pop` and the first one leaves at `sweep + pop + hold`, whatever the
/// wave does. The sweep takes whatever the clip has left, so the clip's length
/// is the wipe's speed.
///
/// **No seams.** Two hard rectangles that meet exactly leave a hairline —
/// each covers half of the shared pixel, and two half-covered pixels are not
/// one whole pixel. With no gap the cells overlap by a stage unit; with a gap
/// they do not, because the gap is what was asked for.
///
/// **Cost**: cells × commands. The default 16 × 9 is 144 sprites with two
/// commands each (three if tinted): under 450 lines.
public struct TileWipeEffect: Effect {
    public init() {}

    public enum Param {
        public static let columns = "columns"
        public static let rows = "rows"
        public static let direction = "direction"
        public static let wave = "wave"
        public static let cycles = "cycles"
        public static let hold = "hold"
        public static let pop = "pop"
        public static let gap = "gap"
        public static let color = "color"
    }

    /// Which way the front travels.
    public enum Direction: String, CaseIterable, Sendable {
        case leftToRight = "Left to Right"
        case rightToLeft = "Right to Left"
        case topToBottom = "Top to Bottom"
        case bottomToTop = "Bottom to Top"

        var isHorizontal: Bool { self == .leftToRight || self == .rightToLeft }
        var isReversed: Bool { self == .rightToLeft || self == .bottomToTop }
    }

    public static let descriptor = EffectDescriptor(
        type: "tileWipe",
        name: "Tile Wipe",
        category: .generate,
        systemImage: "square.grid.3x3.fill",
        parameters: [
            EffectParameter(id: Param.columns, name: "Columns", group: "Grid",
                            defaultValue: .integer(16), range: 2...48, step: 1),
            EffectParameter(id: Param.rows, name: "Rows", group: "Grid",
                            defaultValue: .integer(9), range: 1...27, step: 1),
            // 0 is a solid cover; more is the LED-meter look. In stage units,
            // between neighbouring edges, so "8" means eight pixels of stage.
            EffectParameter(id: Param.gap, name: "Gap", group: "Grid",
                            defaultValue: .number(0), range: 0...40, step: 1, unit: "px"),
            EffectParameter(id: Param.direction, name: "Direction", group: "Sweep",
                            defaultValue: .choice(Direction.leftToRight.rawValue),
                            options: Direction.allCases.map(\.rawValue)),
            // The share of the sweep spent on the ripple. 0 is a straight
            // front; the blend stays inside the sweep at every value.
            EffectParameter(id: Param.wave, name: "Wave", group: "Sweep",
                            defaultValue: .number(0.35), range: 0...0.9, step: 0.05,
                            presentation: .slider),
            EffectParameter(id: Param.cycles, name: "Wave Cycles", group: "Sweep",
                            defaultValue: .number(1.5), range: 0.25...4, step: 0.25),
            // How long the stage stays covered. The sweep takes what is left of
            // the clip, so this is the one timing an author reasons about.
            EffectParameter(id: Param.hold, name: "Cover Hold", group: "Timing",
                            defaultValue: .number(500), range: 0...10000, step: 50, unit: "ms"),
            EffectParameter(id: Param.pop, name: "Pop Time", group: "Timing",
                            defaultValue: .number(120), range: 20...1000, step: 10, unit: "ms"),
            EffectParameter(id: Param.color, name: "Colour", group: "Appearance",
                            defaultValue: .color(.white)),
        ],
    )

    /// Stage units of overlap between cells when there is no gap.
    static let seamOverlap = 1.0

    public func evaluate(in context: EffectContext, rng _: inout EffectRandom) -> [StoryboardSprite] {
        let columns = max(1, context.integer(Param.columns))
        let rows = max(1, context.integer(Param.rows))
        let direction = Direction(rawValue: context.choice(Param.direction)) ?? .leftToRight
        let wave = min(max(context.number(Param.wave), 0), 1)
        let cycles = context.number(Param.cycles)
        let gap = max(0, context.number(Param.gap))
        let colour = context.color(Param.color)
        let duration = context.duration
        guard duration > 0 else { return [] }

        // The fixed part of the timeline, scaled down together if the clip is
        // too short for it: a wipe that cannot fit still has to end inside its
        // clip, and it is the sweep that gives way.
        var pop = max(1, context.number(Param.pop))
        var hold = max(0, context.number(Param.hold))
        let fixed = hold + 2 * pop
        if fixed > duration {
            pop *= duration / fixed
            hold *= duration / fixed
        }
        let sweep = max(0, (duration - hold - 2 * pop) / 2)

        let stage = StageSnap.Stage.self
        let pitchX = stage.width / Double(columns)
        let pitchY = stage.height / Double(rows)
        // Joined cells overlap; separated ones do not.
        let overlap = gap < 0.05 ? Self.seamOverlap : 0
        let sourceSize = ShapeEffect.sourceSize
        let scaleX = max(0.001, pitchX - gap + overlap) / sourceSize
        let scaleY = max(0.001, pitchY - gap + overlap) / sourceSize

        func position(_ index: Int, of count: Int) -> Double {
            count > 1 ? Double(index) / Double(count - 1) : 0
        }

        var sprites: [StoryboardSprite] = []
        sprites.reserveCapacity(columns * rows)

        for row in 0 ..< rows {
            for column in 0 ..< columns {
                // Along the sweep and across it, whichever way that is.
                let (along, across): (Double, Double) = if direction.isHorizontal {
                    (position(column, of: columns), position(row, of: rows))
                } else {
                    (position(row, of: rows), position(column, of: columns))
                }
                let front = direction.isReversed ? 1 - along : along

                // 0…1, so the blend below stays in 0…1 and the last cell lands
                // no later than the sweep's end.
                let ripple = 0.5 + 0.5 * sin(2 * .pi * cycles * across)
                let delay = sweep * ((1 - wave) * front + wave * ripple)

                let landsAt = delay
                let leavesAt = sweep + pop + hold + delay

                var sprite = StoryboardSprite(
                    id: "\(context.idPrefix)/r\(row)c\(column)",
                    layer: context.node.layer,
                    origin: .centre,
                    filePath: BuiltInSprite.fill,
                    defaultX: stage.minX + (Double(column) + 0.5) * pitchX,
                    defaultY: stage.minY + (Double(row) + 0.5) * pitchY,
                )

                // In from nothing, out to nothing. The sprite is alive only
                // between these two, so nothing draws before or after the wipe;
                // held at full size in between by the first command's end value.
                sprite.commands.append(Command(
                    easing: .quadOut, startTime: landsAt, endTime: landsAt + pop,
                    payload: .vectorScale(startX: 0, startY: 0, endX: scaleX, endY: scaleY),
                ))
                sprite.commands.append(Command(
                    easing: .quadIn, startTime: leavesAt, endTime: leavesAt + pop,
                    payload: .vectorScale(startX: scaleX, startY: scaleY, endX: 0, endY: 0),
                ))

                if colour != .white {
                    sprite.commands.append(Command(
                        easing: .linear, startTime: landsAt, endTime: landsAt,
                        payload: .color(
                            startR: colour.r, startG: colour.g, startB: colour.b,
                            endR: colour.r, endG: colour.g, endB: colour.b,
                        ),
                    ))
                }
                sprites.append(sprite)
            }
        }
        return sprites
    }
}

// ─── Presets ─────────────────────────────────────────────────────────────────

public extension TileWipeEffect {
    /// Flat, because it is drawn: hard squares, no additive, and timing that
    /// snaps — a cell pops in and out in a tenth of a second, and the stage
    /// stays covered for half of one.
    ///
    /// Not registered in `EffectLibrary.standard` or the editor's preset list
    /// from here; see the note in CLAUDE.md.
    static let presets: [EffectPreset] = [tileWipe]

    static let tileWipe: EffectPreset = {
        let overrides: [String: EffectValue] = [
            Param.columns: .integer(16), Param.rows: .integer(9),
            Param.gap: .number(0),
            Param.direction: .choice(Direction.leftToRight.rawValue),
            Param.wave: .number(0.35), Param.cycles: .number(1.5),
            Param.hold: .number(500), Param.pop: .number(120),
            // The poster's signal yellow.
            Param.color: .color(EffectColor(r: 230, g: 195, b: 65)),
        ]
        return EffectPreset(
            id: "tile-wipe",
            name: "Tile Wipe",
            effectType: descriptor.type,
            summary: "Hard squares sweeping across as a rippling curtain",
            duration: 2400,
            values: descriptor.defaultValues.merging(overrides) { _, new in new },
            overrides: overrides,
            pack: "Flat",
        )
    }()
}
