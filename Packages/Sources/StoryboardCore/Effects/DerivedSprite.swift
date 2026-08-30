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

        guard descriptor.hasPrefix("blur"),
              let radius = Double(descriptor.dropFirst(4))
        else { return nil }

        return (.blur(radius: radius), source)
    }

    public enum Kind: Equatable, Sendable {
        case blur(radius: Double)
    }

    public static func isDerived(_ path: String) -> Bool {
        path.hasPrefix(prefix)
    }

    /// Rounds a radius to a step, so nearby values share one texture.
    ///
    /// Without this a continuous slider mints a new image for every position it
    /// passes through, and a handful of drags fills the atlas with textures
    /// nobody can tell apart.
    static func quantise(_ radius: Double) -> Int {
        let step = 2.0
        return Int((max(0, radius) / step).rounded()) * Int(step)
    }
}
