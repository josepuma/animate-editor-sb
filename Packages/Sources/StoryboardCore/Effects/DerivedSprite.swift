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
