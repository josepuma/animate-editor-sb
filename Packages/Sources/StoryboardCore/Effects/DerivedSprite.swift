import Foundation

/// A sprite the app makes from another one.
///
/// A glow wants a blurred copy of whatever it is glowing around. The source is
/// the user's own file, so it cannot be changed — instead the path names a
/// *derivation* of it, and whoever loads textures produces the image on demand.
///
/// ## Why this beats stacking copies
///
/// The obvious way to fake a glow without shaders is several scaled copies at
/// falling opacity. It works, and it costs a sprite per copy: three layers over
/// two hundred particles is six hundred sprites, each with its own command
/// list. One blurred sprite per particle is a third of that — and it looks
/// better, because a real blur falls off smoothly where stacked copies always
/// band.
///
/// ## What it costs elsewhere
///
/// The derived image has to exist as a file when the storyboard is exported,
/// since a `.osb` can only name paths on disk. That is the same obligation the
/// built-in shapes already carry.
public enum DerivedSprite {
    /// Marks a path as derived rather than a file the beatmap holds.
    public static let prefix = "__derived__/"

    /// A blurred version of `source`.
    ///
    /// - Parameter radius: blur radius in source pixels, quantised so a slider
    ///   dragged across a range produces a handful of textures rather than one
    ///   per frame. Every distinct radius is a distinct image in the atlas, and
    ///   an atlas is a fixed size.
    public static func blurred(_ source: String, radius: Double) -> String {
        "\(prefix)blur\(quantise(radius))/\(source)"
    }

    /// The parts of a derived path, or `nil` when it is not one.
    public static func parse(_ path: String) -> (kind: Kind, source: String)? {
        guard path.hasPrefix(prefix) else { return nil }

        let body = path.dropFirst(prefix.count)
        guard let slash = body.firstIndex(of: "/") else { return nil }

        let descriptor = String(body[body.startIndex..<slash])
        let source = String(body[body.index(after: slash)...])
        guard !source.isEmpty else { return nil }

        if descriptor.hasPrefix("blur"), let radius = Double(descriptor.dropFirst(4)) {
            return (.blur(radius: radius), source)
        }
        if let kind = parseDots(descriptor) { return (kind, source) }
        if let kind = parseLook(descriptor) { return (kind, source) }
        if let kind = parsePanel(descriptor, extent: source) { return (kind, source) }
        return nil
    }

    public enum Kind: Equatable, Sendable {
        case blur(radius: Double)
        /// The source re-drawn as a grid of dots. All four numbers are the
        /// quantised ones the path carries, so what is parsed is exactly what
        /// was written.
        case dotMatrix(pitch: Int, dotPercent: Int, shape: DotShape, thresholdPercent: Int)
        /// A lattice of dots with no source: the unlit ones behind an LED sign.
        case dotPanel(columns: Int, rows: Int, pitch: Int, dotPercent: Int, shape: DotShape)
        /// The source's silhouette grown by `width` pixels, on a canvas grown
        /// by ``DerivedSprite/outlineMargin(width:)`` each side — all of it
        /// drawn `resolution` times larger.
        case outline(width: Int, resolution: Int)
        /// The source re-drawn as dots sized by how much ink each cell holds.
        case halftone(cell: Int, shape: DotShape)
        /// The source's luminance mapped from one colour to another, as
        /// `0xRRGGBB`.
        case duotone(dark: Int, light: Int)
        /// The source's edges as lines `width` pixels wide.
        case ink(width: Int, detailPercent: Int, resolution: Int)
        /// One cell of a `columns × rows` grid over the source, on a canvas
        /// the source's own size with everything else cleared.
        case tile(columns: Int, rows: Int, index: Int)
    }

    public static func isDerived(_ path: String) -> Bool {
        path.hasPrefix(prefix)
    }

    /// Rounds a radius to a step, so nearby values share one texture.
    ///
    /// Without this a continuous slider mints a new image for every position it
    /// passes through, and a handful of drags fills the atlas with textures
    /// nobody can tell apart.
    /// How far apart two radii must be to be different images.
    ///
    /// Public because an animated radius has to know it: the number of textures
    /// a run from one value to another will mint is exactly what makes its cost
    /// knowable before anybody writes the file.
    public static let quantumStep: Double = 2

    static func quantise(_ radius: Double) -> Int {
        Int((max(0, radius) / quantumStep).rounded()) * Int(quantumStep)
    }

    /// The distinct blur radii a run between two values passes through.
    ///
    /// This is the whole cost of animating a blur, made countable. A sprite
    /// draws one image for its entire life, so a radius that travels is not one
    /// sprite changing — it is one sprite per level, each visible over its own
    /// stretch.
    ///
    /// Only the levels actually crossed, in order, and never fewer than one.
    public static func levels(from: Double, to: Double) -> [Int] {
        let low = quantise(min(from, to))
        let high = quantise(max(from, to))
        guard high > low else { return [low] }

        let step = Int(quantumStep)
        return stride(from: low, through: high, by: step).map { $0 }
    }

    // ─── Dot matrix ──────────────────────────────────────────────────────────

    /// The shape of one dot.
    public enum DotShape: String, Sendable, Equatable, CaseIterable {
        case round = "r"
        case square = "s"
    }

    /// Bounds on a dot grid's parameters, shared by the paths that carry them
    /// and the filter that exposes them.
    public static let dotPitchRange: ClosedRange<Int> = 2...64

    /// The source re-drawn as a grid of hard-edged dots.
    ///
    /// The texture that makes an LED sign: one image per glyph instead of one
    /// sprite per dot. A line of forty characters at a pitch of 8 is roughly
    /// three thousand lit dots — as sprites, three thousand of them with their
    /// own commands; as this, forty.
    ///
    /// Every number is quantised into the path, for the reason blur radii are:
    /// a slider dragged across a range would otherwise mint a texture per
    /// position, and an atlas is a fixed size.
    ///
    /// - Parameters:
    ///   - pitch: cell size in source pixels.
    ///   - dotSize: dot diameter as a fraction of the pitch.
    ///   - threshold: how much of a cell the source must cover to light it.
    public static func dotMatrix(
        _ source: String,
        pitch: Double,
        dotSize: Double,
        shape: DotShape,
        threshold: Double,
    ) -> String {
        let p = quantisePitch(pitch)
        let d = quantisePercent(dotSize, in: 1...100)
        let t = quantisePercent(threshold, in: 1...99)
        return "\(prefix)dots\(p)-\(d)-\(shape.rawValue)-\(t)/\(source)"
    }

    /// A lattice of dots with no source, `columns × rows` cells.
    ///
    /// Its extent is named in cells and lives where a source path would: the
    /// path is `descriptor/source`, and a panel's only "source" is how big it
    /// is.
    public static func dotPanel(
        columns: Int,
        rows: Int,
        pitch: Double,
        dotSize: Double,
        shape: DotShape,
    ) -> String {
        let p = quantisePitch(pitch)
        let d = quantisePercent(dotSize, in: 1...100)
        return "\(prefix)panel\(p)-\(d)-\(shape.rawValue)/\(max(1, columns))x\(max(1, rows))"
    }

    /// How many cells a dot grid needs to cover `length` — always an even
    /// number.
    ///
    /// Even is the whole trick. A sprite's anchor is the left edge, the middle
    /// or the right edge of its texture, so the dots stay on a shared lattice
    /// for **every** origin only if half the texture is also a whole number of
    /// cells. With an odd count the centre would sit half a pitch off the
    /// lattice, and the filter would have to know the image's size to fix it —
    /// which Core, unable to open a file, does not.
    public static func cells(covering length: Double, pitch: Int) -> Int {
        let needed = max(1, Int((max(0, length) / Double(max(1, pitch))).rounded(.up)))
        return needed % 2 == 0 ? needed : needed + 1
    }

    // ─── Look ────────────────────────────────────────────────────────────────

    /// Bounds on an outline's width, in source pixels.
    public static let outlineWidthRange: ClosedRange<Int> = 1...32

    /// The source with an outline `width` pixels wide around its silhouette.
    ///
    /// Whole pixels, for the reason blur radii are quantised: a slider would
    /// otherwise mint a texture at every position it passes through.
    public static func outlined(_ source: String, width: Double, resolution: Int = 1) -> String {
        "\(prefix)outline\(quantiseOutline(width))\(resolutionSuffix(resolution))/\(source)"
    }

    /// How far the outlined canvas reaches past its source on every side.
    ///
    /// Public because the filter has to undo it: osu! anchors a sprite to its
    /// *canvas*, so a canvas grown on all sides moves everything not hung from
    /// its centre. One pixel more than the width, for the antialiased edge.
    public static func outlineMargin(width: Double) -> Int {
        quantiseOutline(width) + 1
    }

    /// The source as halftone dots, one per `cell` pixels.
    ///
    /// Same size as the source, so the anchor stays exactly where it was.
    public static func halftone(_ source: String, cell: Double, shape: DotShape) -> String {
        "\(prefix)halftone\(quantisePitch(cell))-\(shape.rawValue)/\(source)"
    }

    /// The source's luminance mapped from `dark` to `light`.
    ///
    /// The colours go into the path whole: a colour well picks discrete
    /// values, so there is no slider to sweep a texture into existence per
    /// step.
    public static func duotone(_ source: String, dark: EffectColor, light: EffectColor) -> String {
        "\(prefix)duo\(hex(dark))-\(hex(light))/\(source)"
    }

    /// Bounds on an ink line's width, in source pixels.
    public static let inkWidthRange: ClosedRange<Int> = 1...12

    /// The source's edges as lines.
    ///
    /// - Parameter detail: how faint an edge inside the silhouette can be and
    ///   still be drawn — 0 draws only the outer contour.
    public static func inked(_ source: String, width: Double, detail: Double, resolution: Int = 1) -> String {
        let w = min(inkWidthRange.upperBound, max(inkWidthRange.lowerBound, Int(width.rounded())))
        let d = min(100, max(0, Int((detail * 100).rounded())))
        return "\(prefix)ink\(w)-\(d)\(resolutionSuffix(resolution))/\(source)"
    }

    // ─── Line resolution ─────────────────────────────────────────────────────

    /// The most a line texture is drawn larger than its source.
    public static let maximumLineResolution = 3

    /// How many times larger to draw Outline and Ink for a sprite drawing
    /// `path`, which the filter then draws at that fraction of its scale.
    ///
    /// A line is pixel-sized in its texture, and a texture pixel is a
    /// storyboard unit — about 2¼ screen pixels at 1080p. Drawn at the
    /// source's own resolution, every step of a curve is a visible block:
    /// Ink on a 56px kanji read as pixelated, and averaging it smoother only
    /// smeared a 1px line across two. Drawn three times larger and shown at a
    /// third, the steps are under a screen pixel and `Width` means what it
    /// says.
    ///
    /// Capped so the texture stays within osu!'s 2048: text and built-ins
    /// have sizes Core knows (a 400px glyph with the widest outline is under
    /// 600). A beatmap's own image does not — Core cannot open it — so it
    /// stays at 1, which is what it always was.
    public static func lineResolution(for path: String) -> Int {
        let side: Double
        if path.hasPrefix(TextSprite.prefix) {
            side = 600
        } else if BuiltInSprite.isKnown(path) {
            let size = BuiltInSprite.fileSizes[path] ?? (512, 512)
            side = max(size.width, size.height) + Double(outlineMargin(width: Double(outlineWidthRange.upperBound)) * 2)
        } else {
            return 1
        }
        return max(1, min(maximumLineResolution, Int(2048 / side)))
    }

    private static func resolutionSuffix(_ resolution: Int) -> String {
        resolution > 1 ? "x\(min(resolution, maximumLineResolution))" : ""
    }

    /// `"35x3"` → (35, 3); `"35"` → (35, 1).
    private static func withResolution(_ part: Substring) -> (value: Int, resolution: Int)? {
        let pieces = part.split(separator: "x")
        guard let value = pieces.first.flatMap({ Int($0) }) else { return nil }
        guard pieces.count == 2 else { return pieces.count == 1 ? (value, 1) : nil }
        guard let resolution = Int(pieces[1]), resolution >= 1 else { return nil }
        return (value, resolution)
    }

    /// Bounds on a grid of pieces, per axis.
    public static let tileRange: ClosedRange<Int> = 1...16

    /// Cell `index` of a `columns × rows` grid over `source`, counted row by
    /// row from the top left.
    ///
    /// The canvas stays the source's size with only the cell left in it, so
    /// every piece shares the original's anchor: placed where the sprite is,
    /// the pieces assemble into it exactly, and Core never needs to know how
    /// big the image is — which it cannot. The cost is memory: a piece is a
    /// whole canvas, mostly empty.
    public static func tiled(_ source: String, columns: Int, rows: Int, index: Int) -> String {
        let c = min(tileRange.upperBound, max(tileRange.lowerBound, columns))
        let r = min(tileRange.upperBound, max(tileRange.lowerBound, rows))
        return "\(prefix)tile\(c)x\(r)-\(min(max(index, 0), c * r - 1))/\(source)"
    }

    private static func quantiseOutline(_ width: Double) -> Int {
        min(outlineWidthRange.upperBound, max(outlineWidthRange.lowerBound, Int(width.rounded())))
    }

    private static func hex(_ colour: EffectColor) -> String {
        let channel = { (value: Double) in min(255, max(0, Int(value.rounded()))) }
        return String(format: "%02x%02x%02x", channel(colour.r), channel(colour.g), channel(colour.b))
    }

    private static func parseLook(_ descriptor: String) -> Kind? {
        if descriptor.hasPrefix("outline"), let parsed = withResolution(descriptor.dropFirst(7)) {
            return .outline(width: parsed.value, resolution: parsed.resolution)
        }
        if descriptor.hasPrefix("halftone") {
            let parts = descriptor.dropFirst(8).split(separator: "-")
            guard parts.count == 2, let cell = Int(parts[0]), let shape = DotShape(rawValue: String(parts[1]))
            else { return nil }
            return .halftone(cell: cell, shape: shape)
        }
        if descriptor.hasPrefix("duo") {
            let parts = descriptor.dropFirst(3).split(separator: "-")
            guard parts.count == 2, parts.allSatisfy({ $0.count == 6 }),
                  let dark = Int(parts[0], radix: 16), let light = Int(parts[1], radix: 16)
            else { return nil }
            return .duotone(dark: dark, light: light)
        }
        if descriptor.hasPrefix("tile") {
            let parts = descriptor.dropFirst(4).split(separator: "-")
            let grid = parts.first?.split(separator: "x") ?? []
            guard parts.count == 2, grid.count == 2,
                  let columns = Int(grid[0]), let rows = Int(grid[1]), let index = Int(parts[1])
            else { return nil }
            return .tile(columns: columns, rows: rows, index: index)
        }
        if descriptor.hasPrefix("ink") {
            let parts = descriptor.dropFirst(3).split(separator: "-")
            guard parts.count == 2, let width = Int(parts[0]), let detail = withResolution(parts[1]) else { return nil }
            return .ink(width: width, detailPercent: detail.value, resolution: detail.resolution)
        }
        return nil
    }

    private static func quantisePitch(_ pitch: Double) -> Int {
        min(dotPitchRange.upperBound, max(dotPitchRange.lowerBound, Int(pitch.rounded())))
    }

    private static func quantisePercent(_ fraction: Double, in range: ClosedRange<Int>) -> Int {
        min(range.upperBound, max(range.lowerBound, Int((fraction * 100).rounded())))
    }

    private static func parseDots(_ descriptor: String) -> Kind? {
        guard descriptor.hasPrefix("dots") else { return nil }
        let parts = descriptor.dropFirst(4).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 4,
              let pitch = Int(parts[0]), let dot = Int(parts[1]),
              let shape = DotShape(rawValue: String(parts[2])),
              let threshold = Int(parts[3])
        else { return nil }
        return .dotMatrix(pitch: pitch, dotPercent: dot, shape: shape, thresholdPercent: threshold)
    }

    private static func parsePanel(_ descriptor: String, extent: String) -> Kind? {
        guard descriptor.hasPrefix("panel") else { return nil }
        let parts = descriptor.dropFirst(5).split(separator: "-", omittingEmptySubsequences: false)
        let size = extent.split(separator: "x", omittingEmptySubsequences: false)
        guard parts.count == 3, size.count == 2,
              let pitch = Int(parts[0]), let dot = Int(parts[1]),
              let shape = DotShape(rawValue: String(parts[2])),
              let columns = Int(size[0]), let rows = Int(size[1])
        else { return nil }
        return .dotPanel(columns: columns, rows: rows, pitch: pitch, dotPercent: dot, shape: shape)
    }
}

/// The lattice LED dots sit on, anchored to the stage.
///
/// One lattice for every sprite under the filter, and for the panel behind
/// them: dots that belong to one sign have to line up across glyphs that were
/// rasterised separately.
public enum DotGrid {
    /// The stage's top-left corner, in storyboard coordinates. The wide stage
    /// starts left of the frame.
    public static let originX: Double = StageSnap.Stage.minX
    public static let originY: Double = StageSnap.Stage.minY

    /// `value` moved to the nearest multiple of `pitch` from `origin`.
    public static func snap(_ value: Double, origin: Double, pitch: Double) -> Double {
        origin + ((value - origin) / pitch).rounded() * pitch
    }

    /// The nearest lattice line at or below `value`.
    public static func floor(_ value: Double, origin: Double, pitch: Double) -> Double {
        origin + ((value - origin) / pitch).rounded(.down) * pitch
    }
}
