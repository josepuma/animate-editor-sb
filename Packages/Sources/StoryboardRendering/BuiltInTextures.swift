import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Images the app supplies itself, for effects that need something to draw
/// before the user has chosen a sprite.
///
/// An effect whose default points at a file the beatmap does not contain would
/// render nothing on the first drop, which reads as the effect being broken
/// rather than as a missing asset. These paths are checked before the beatmap
/// folder is consulted.
public enum BuiltInTextures {
    /// Prefix marking a path this type supplies rather than the beatmap.
    ///
    /// Namespaced so it cannot collide with a real file: a beatmap containing
    /// its own `particle.png` must keep using it.
    public static let prefix = "__builtin__/"

    /// The shapes an effect can draw without the beatmap supplying anything.
    ///
    /// Deliberately a handful of generic forms rather than a catalogue of
    /// pictures. What makes a particle field read as fire or smoke is the
    /// motion, the colour ramp and additive blending — not a drawing of a
    /// flame. A soft dot plus the right parameters covers more of the ground
    /// than any illustration would.
    ///
    /// Every shape is drawn in white with an alpha profile, so a `_C` command
    /// tints it to whatever the effect needs. A coloured source would fight
    /// that tint.
    public enum Shape: String, CaseIterable, Sendable {
        /// A soft round dot. The workhorse: fire, smoke, glows, bokeh.
        case soft
        /// A hard core inside a wide halo — sparks, magic, anything hot.
        case glow
        /// An irregular cloud, for smoke and dust.
        case smoke
        /// Four-pointed star, for sparkles and lens glints.
        case star
        /// A plain square, for confetti and debris.
        case square
        /// A vertical streak, for rain, trails and speed lines.
        case streak
        /// A hollow ring, for shockwaves and bubbles.
        case ring
        /// A hard-edged rectangle filling its whole canvas.
        ///
        /// Separate from `square`, which insets its ink so a spinning particle
        /// keeps its corners: stretched to a bar, that transparent margin
        /// stretches too — the edges come out blurred and the bar measures a
        /// third narrower than it was asked for.
        case fill
        /// A hard-edged disc.
        ///
        /// Distinct from `soft`, which fades to nothing at its rim: that is a
        /// particle, and a shape asked for a circle wants an edge.
        case disc
        /// A hard-edged outline.
        /// Drawn on demand at a given thickness, so it is **not** one of the
        /// fixed shapes: see ``hoopPath(thickness:)``.
        case hoop

        /// The path an effect stores for this shape.
        public var path: String { "\(prefix)\(rawValue).png" }

        /// Human-readable name for the inspector's menu.
        public var title: String {
            switch self {
            case .soft: "Soft Dot"
            case .glow: "Glow"
            case .smoke: "Smoke Puff"
            case .star: "Star"
            case .square: "Square"
            case .streak: "Streak"
            case .ring: "Ring"
            case .fill: "Fill"
            case .disc: "Disc"
            case .hoop: "Hoop"
            }
        }

        public init?(path: String) {
            guard path.hasPrefix(prefix) else { return nil }
            let name = String(path.dropFirst(prefix.count)).replacingOccurrences(of: ".png", with: "")
            self.init(rawValue: name)
        }
    }

    /// Textures shipped as files rather than drawn in code.
    ///
    /// Some shapes cannot be generated: a branching bolt of lightning, a flame
    /// with a real silhouette, a directional muzzle flash. Those are drawings,
    /// and code that tried to approximate them would produce a worse version of
    /// a file that already exists.
    ///
    /// From the Kenney Particle Pack (CC0) — see `Particles/CREDITS.md`.
    public enum Texture: String, CaseIterable, Sendable {
        case lightning = "spark_01"
        case lightningWide = "spark_03"
        case bolt = "spark_05"
        case boltThin = "trace_05"
        case flame = "flame_05"
        case flameTall = "flame_06"
        case flameWisp = "flame_01"
        case ember = "fire_01"
        case muzzle = "muzzle_01"
        case muzzleWide = "muzzle_03"
        case arc = "twirl_01"
        case crescent = "twirl_02"
        case scratch = "scratch_01"
        case slash = "slash_01"
        case slashWide = "slash_04"
        case slashDeep = "slash_02"
        case slashThin = "slash_03"
        /// A soft vertical column — a beam, drawn rather than simulated.
        case beam = "trace_01"
        case beamThin = "trace_02"
        case scorch = "scorch_01"
        case rune = "symbol_01"
        case flare = "magic_03"
        case flareSoft = "magic_04"
        case runeRing = "magic_01"
        case cloud = "smoke_04"
        case cloudWisp = "smoke_07"
        case sparkle = "star_04"
        case debris = "dirt_01"
        case pane = "window_01"

        public var path: String { "\(prefix)\(rawValue).png" }

        public var title: String {
            switch self {
            case .lightning: "Lightning"
            case .lightningWide: "Lightning Wide"
            case .bolt: "Bolt"
            case .boltThin: "Bolt Thin"
            case .flame: "Flame"
            case .flameTall: "Flame Tall"
            case .flameWisp: "Flame Wisp"
            case .ember: "Embers"
            case .muzzle: "Muzzle Flash"
            case .muzzleWide: "Muzzle Wide"
            case .arc: "Arc"
            case .crescent: "Crescent"
            case .scratch: "Scratch"
            case .slash: "Slash"
            case .slashWide: "Wave"
            case .slashDeep: "Slash Deep"
            case .slashThin: "Slash Thin"
            case .beam: "Beam"
            case .beamThin: "Beam Thin"
            case .scorch: "Scorch"
            case .rune: "Rune"
            case .flare: "Flare"
            case .flareSoft: "Flare Soft"
            case .runeRing: "Rune Ring"
            case .cloud: "Cloud"
            case .cloudWisp: "Cloud Wisp"
            case .sparkle: "Sparkle"
            case .debris: "Debris"
            case .pane: "Pane"
            }
        }

        public init?(path: String) {
            guard path.hasPrefix(prefix) else { return nil }
            let name = String(path.dropFirst(prefix.count)).replacingOccurrences(of: ".png", with: "")
            self.init(rawValue: name)
        }
    }

    /// Every built-in path, drawn and shipped alike.
    ///
    /// Callers do not distinguish the two: both are images the app supplies and
    /// the beatmap does not have.
    public static var allPaths: [String] {
        Shape.allCases.filter { $0 != .hoop }.map(\.path) + Texture.allCases.map(\.path)
    }

    /// The emitter's default particle.
    public static let particle = Shape.soft.path

    public static func isBuiltIn(_ filePath: String) -> Bool {
        filePath.hasPrefix(prefix)
    }

    /// PNG data for a built-in path, or `nil` when the path is not one.
    public static func data(for filePath: String) -> Data? {
        // The old default kept working: a project saved before the shapes had
        // names still asks for `particle.png`.
        if filePath == "\(prefix)particle.png" {
            return cached(filePath) { encode(draw(.soft, size: size(for: .soft))) }
        }
        // A hoop carries its thickness in its path, so each weight is its own
        // texture: the ring is drawn into the image, and there is no command in
        // the format that could thin it afterwards.
        if let thickness = hoopThickness(in: filePath) {
            return cached(filePath) {
                encode(draw(.hoop, size: size(for: .hoop), thickness: thickness))
            }
        }
        if let shape = Shape(path: filePath) {
            return cached(filePath) { encode(draw(shape, size: size(for: shape))) }
        }
        if let texture = Texture(path: filePath) {
            return cached(filePath) { bundled(texture) }
        }
        return nil
    }

    /// The path for a hoop of a given thickness, as a fraction of its size.
    ///
    /// Quantised to whole percent for the same reason a derived blur is: a
    /// continuous slider would mint a texture at every value it passes
    /// through, and the atlas has a fixed size.
    public static func hoopPath(thickness: Double) -> String {
        let percent = Int((min(max(thickness, 0.01), 0.5) * 100).rounded())
        return "\(prefix)hoop\(percent).png"
    }

    private static func hoopThickness(in path: String) -> CGFloat? {
        guard path.hasPrefix("\(prefix)hoop"), path.hasSuffix(".png") else { return nil }
        let body = path.dropFirst("\(prefix)hoop".count).dropLast(".png".count)
        guard let percent = Int(body) else { return nil }
        return CGFloat(percent) / 100
    }

    /// Reads a shipped texture out of the module bundle.
    private static func bundled(_ texture: Texture) -> Data? {
        guard let url = Bundle.module.url(
            forResource: texture.rawValue,
            withExtension: "png",
            subdirectory: "Particles",
        ) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Drawn large enough to scale up without softening, small enough that
    /// hundreds of them still pack into one atlas page.
    private static func size(for shape: Shape) -> Int {
        switch shape {
        case .streak: 128
        // The drawn shapes are large, because they are drawn *large*.
        //
        // A particle is a few dozen pixels on screen, so 64 is already more
        // detail than reaches the eye. A shape is a backdrop or a bar: asked
        // for at 400 across, a 64px circle is magnified six times and its curve
        // becomes a visible staircase. A straight edge survives that — a curve
        // does not, which is why only the round ones need it.
        //
        // `fill` stays small on purpose: it is a flat rectangle, and there is
        // nothing in it that magnification can spoil.
        case .disc, .hoop: 512
        default: 64
        }
    }

    // ─── Cache ───────────────────────────────────────────────────────────────

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: Data] = [:]

    /// Drawing is cheap but not free, and a texture is requested once per
    /// sprite — thousands of times for one emitter.
    private static func cached(_ key: String, make: () -> Data?) -> Data? {
        lock.lock()
        defer { lock.unlock() }

        if let existing = cache[key] { return existing }
        guard let made = make() else { return nil }
        cache[key] = made
        return made
    }

    // ─── Drawing ─────────────────────────────────────────────────────────────

    private static func draw(_ shape: Shape, size: Int, thickness: CGFloat = 0.12) -> CGImage? {
        guard let context = makeContext(size: size) else { return nil }
        let extent = CGFloat(size)

        switch shape {
        case .soft: drawSoft(in: context, extent: extent)
        case .glow: drawGlow(in: context, extent: extent)
        case .smoke: drawSmoke(in: context, extent: extent)
        case .star: drawStar(in: context, extent: extent)
        case .square: drawSquare(in: context, extent: extent)
        case .streak: drawStreak(in: context, extent: extent)
        case .ring: drawRing(in: context, extent: extent)
        case .fill: drawFill(in: context, extent: extent)
        case .disc: drawDisc(in: context, extent: extent)
        case .hoop: drawHoop(in: context, extent: extent, thickness: thickness)
        }

        return context.makeImage()
    }

    /// Premultiplied, so every shape composites correctly under both blend
    /// modes.
    private static func makeContext(size: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        )
    }

    private static func white(_ alpha: CGFloat) -> CGColor {
        CGColor(red: 1, green: 1, blue: 1, alpha: alpha)
    }

    private static func radial(_ stops: [(CGFloat, CGFloat)]) -> CGGradient? {
        CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: stops.map { white($0.1) } as CFArray,
            locations: stops.map(\.0),
        )
    }

    private static func fillRadial(
        _ context: CGContext,
        extent: CGFloat,
        centre: CGPoint? = nil,
        radius: CGFloat? = nil,
        stops: [(CGFloat, CGFloat)],
    ) {
        guard let gradient = radial(stops) else { return }
        let middle = centre ?? CGPoint(x: extent / 2, y: extent / 2)
        context.drawRadialGradient(
            gradient,
            startCenter: middle, startRadius: 0,
            endCenter: middle, endRadius: radius ?? extent / 2,
            options: [],
        )
    }

    // ─── Shapes ──────────────────────────────────────────────────────────────

    /// The hold before the falloff keeps a small particle from reading as a
    /// blur: a gradient that starts fading at the centre leaves nothing solid
    /// at the sizes these are drawn at.
    private static func drawSoft(in context: CGContext, extent: CGFloat) {
        fillRadial(context, extent: extent, stops: [(0, 1), (0.45, 0.9), (1, 0)])
    }

    /// A tight core inside a wide, faint halo — the profile of anything hot
    /// enough to glow. The sharp step at 0.18 is what separates it from `soft`;
    /// a smooth ramp would just be a bigger dot.
    private static func drawGlow(in context: CGContext, extent: CGFloat) {
        fillRadial(context, extent: extent, stops: [
            (0, 1), (0.12, 1), (0.18, 0.55), (0.45, 0.16), (1, 0),
        ])
    }

    /// Overlapping blobs, so the silhouette is lumpy rather than round.
    ///
    /// Smoke that is a circle reads as a ball. The offsets are fixed rather
    /// than random: every particle shares this one texture, and the variation
    /// that matters comes from rotation and scale at the sprite level.
    private static func drawSmoke(in context: CGContext, extent: CGFloat) {
        let blobs: [(x: CGFloat, y: CGFloat, r: CGFloat, a: CGFloat)] = [
            (0.50, 0.52, 0.30, 0.85),
            (0.34, 0.42, 0.24, 0.65),
            (0.66, 0.44, 0.26, 0.70),
            (0.44, 0.66, 0.22, 0.60),
            (0.62, 0.64, 0.20, 0.55),
        ]

        for blob in blobs {
            fillRadial(
                context,
                extent: extent,
                centre: CGPoint(x: blob.x * extent, y: blob.y * extent),
                radius: blob.r * extent,
                stops: [(0, blob.a), (0.5, blob.a * 0.6), (1, 0)],
            )
        }
    }

    /// Four tapered points over a small core.
    ///
    /// Drawn as filled triangles rather than lines: a line of even width reads
    /// as a cross, while a point that narrows reads as light.
    private static func drawStar(in context: CGContext, extent: CGFloat) {
        let centre = CGPoint(x: extent / 2, y: extent / 2)
        let long = extent * 0.5
        let waist = extent * 0.055

        context.setFillColor(white(0.95))
        for corner in 0..<4 {
            let angle = CGFloat(corner) * .pi / 2
            let tip = CGPoint(
                x: centre.x + cos(angle) * long,
                y: centre.y + sin(angle) * long,
            )
            let side = angle + .pi / 2

            context.beginPath()
            context.move(to: tip)
            context.addLine(to: CGPoint(
                x: centre.x + cos(side) * waist,
                y: centre.y + sin(side) * waist,
            ))
            context.addLine(to: CGPoint(
                x: centre.x - cos(side) * waist,
                y: centre.y - sin(side) * waist,
            ))
            context.closePath()
            context.fillPath()
        }

        fillRadial(context, extent: extent, radius: extent * 0.16, stops: [(0, 1), (1, 0)])
    }

    /// Soft-edged rather than a hard rectangle: a crisp square shows every
    /// rotation step as jagged edges once it is scaled down.
    /// The whole canvas, edge to edge.
    ///
    /// No inset and no feather: a shape is measured by the size it is asked
    /// for, so every transparent pixel is a pixel of the bar somebody wanted.
    private static func drawFill(in context: CGContext, extent: CGFloat) {
        context.setFillColor(white(1))
        context.fill(CGRect(x: 0, y: 0, width: extent, height: extent))
    }

    /// A filled circle with a crisp edge.
    ///
    /// One texel of feather and no more: enough that the rim is not a staircase
    /// of pixels, little enough that it still reads as an edge. A shape is
    /// judged by where it stops, so a soft falloff is the wrong answer here
    /// however right it is for a particle.
    private static func drawDisc(in context: CGContext, extent: CGFloat) {
        context.setFillColor(white(1))
        // Inset by a texel, for the same reason the hoop is: filled to the very
        // edge, the antialiased pixel at the widest points has nowhere to go
        // and the circle comes out with two flat sides.
        context.fillEllipse(in: CGRect(x: 1, y: 1, width: extent - 2, height: extent - 2))
    }

    /// A ring with crisp edges, drawn as an outline rather than a glow.
    private static func drawHoop(
        in context: CGContext,
        extent: CGFloat,
        thickness fraction: CGFloat,
    ) {
        let thickness = extent * fraction
        // A texel of margin beyond the stroke's own half-width.
        //
        // A stroke is centred on the path, so half of it sits outside — and
        // even inset by exactly that half, the pixel antialiasing adds falls
        // off the canvas and the ring comes out flat on its left and right,
        // where the curve runs parallel to the edge.
        let inset = thickness / 2 + 1

        context.setStrokeColor(white(1))
        context.setLineWidth(thickness)
        context.strokeEllipse(in: CGRect(
            x: inset, y: inset,
            width: extent - inset * 2, height: extent - inset * 2,
        ))
    }

    private static func drawSquare(in context: CGContext, extent: CGFloat) {
        let inset = extent * 0.18
        let rect = CGRect(x: inset, y: inset, width: extent - inset * 2, height: extent - inset * 2)

        context.setFillColor(white(0.95))
        context.fill(rect)

        // A one-texel feather at the edge, which is what keeps the diagonal
        // edges of a spinning square from crawling.
        context.setStrokeColor(white(0.45))
        context.setLineWidth(1)
        context.stroke(rect.insetBy(dx: -0.5, dy: -0.5))
    }

    /// A vertical streak: brightest and widest at the middle, tapering to
    /// nothing at both ends.
    ///
    /// Vertical because a sprite is rotated to point where it is going, and
    /// pointing "up" is the convention the emitter's rotation is written
    /// against.
    ///
    /// Drawn row by row rather than by clipping a strip and filling it. A clip
    /// has hard edges by definition, so the earlier version came out a solid
    /// bar with square sides — and stretched by a preset it read as a plank
    /// rather than as a trail of light. Both axes have to soften: **the sides
    /// as much as the ends**, or the shape announces its own bounding box.
    private static func drawStreak(in context: CGContext, extent: CGFloat) {
        let maxWidth = extent * 0.16
        let steps = Int(extent)

        for step in 0 ..< steps {
            let y = CGFloat(step)
            // −1 at the bottom, 0 at the middle, +1 at the top.
            let along = (y / extent) * 2 - 1
            // Squared, so the taper is a spindle rather than a diamond: a
            // trail of light narrows slowly and then falls away quickly.
            let profile = max(0, 1 - along * along)

            let width = maxWidth * profile
            guard width > 0.5 else { continue }

            // A soft core: the row is drawn as a short horizontal gradient, so
            // the sides fade instead of ending.
            let alpha = profile * profile
            guard let row = horizontal([(0, 0), (0.5, alpha), (1, 0)]) else { continue }

            context.saveGState()
            context.clip(to: CGRect(x: (extent - width) / 2, y: y, width: width, height: 1))
            context.drawLinearGradient(
                row,
                start: CGPoint(x: (extent - width) / 2, y: y),
                end: CGPoint(x: (extent + width) / 2, y: y),
                options: [],
            )
            context.restoreGState()
        }
    }

    /// A gradient across white with the given stops, for drawing one row.
    private static func horizontal(_ stops: [(CGFloat, CGFloat)]) -> CGGradient? {
        let space = CGColorSpaceCreateDeviceRGB()
        let colours = stops.map { white($0.1) } as CFArray
        return CGGradient(
            colorsSpace: space,
            colors: colours,
            locations: stops.map(\.0),
        )
    }

    /// A hollow ring with soft edges, for shockwaves and bubbles.
    private static func drawRing(in context: CGContext, extent: CGFloat) {
        let radius = extent * 0.36
        let thickness = extent * 0.09

        context.setStrokeColor(white(0.9))
        context.setLineWidth(thickness)
        context.strokeEllipse(in: CGRect(
            x: extent / 2 - radius,
            y: extent / 2 - radius,
            width: radius * 2,
            height: radius * 2,
        ))

        // A fainter, wider pass outside the first softens the edge, so the ring
        // does not alias into a dotted circle when it is scaled up.
        context.setStrokeColor(white(0.3))
        context.setLineWidth(thickness * 2)
        context.strokeEllipse(in: CGRect(
            x: extent / 2 - radius,
            y: extent / 2 - radius,
            width: radius * 2,
            height: radius * 2,
        ))
    }

    private static func encode(_ image: CGImage?) -> Data? {
        guard let image else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil,
        ) else { return nil }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
