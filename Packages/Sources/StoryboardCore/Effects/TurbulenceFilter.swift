import Foundation

/// A smooth field that drifts everything on the clip, the way wind moves a
/// cloud of particles.
///
/// Wiggle draws an independent tremor per sprite; here neighbours move
/// *together*, because the offset is read from a noise field at each sprite's
/// position. That coherence is the difference between a shiver and a current.
public struct TurbulenceFilter: SpriteFilter {
    public init() {}

    public enum Param {
        public static let amount = "amount"
        public static let scale = "scale"
        public static let speed = "speed"
        public static let rate = "rate"
    }

    public static let descriptor = FilterDescriptor(
        type: "turbulence",
        name: "Turbulence",
        category: .motion,
        systemImage: "wind",
        parameters: [
            EffectParameter(
                id: Param.amount, name: "Amount", group: "Turbulence",
                defaultValue: .number(30), range: 0...300, step: 1, unit: "px",
            ),
            EffectParameter(
                id: Param.scale, name: "Size", group: "Turbulence",
                // How far apart two sprites have to be before they stop
                // moving together.
                defaultValue: .number(200), range: 10...2000, step: 10, unit: "px",
            ),
            EffectParameter(
                id: Param.speed, name: "Evolution", group: "Turbulence",
                defaultValue: .number(0.5), range: 0...5, step: 0.05, unit: "/s",
            ),
            EffectParameter(
                id: Param.rate, name: "Sample Rate", group: "Turbulence",
                defaultValue: .number(10), range: 2...30, step: 1, unit: "/s",
            ),
        ],
    )

    public func estimatedMultiplier(in context: FilterContext) -> Double { 1 }

    public func apply(to sprites: [StoryboardSprite], in context: FilterContext) -> [StoryboardSprite] {
        let amount = context.number(Param.amount)
        guard amount > 0 else { return sprites }
        let scale = context.number(Param.scale)
        let speed = context.number(Param.speed)
        let rate = context.number(Param.rate)
        // Seeded by the filter, not the sprite: one field for the whole clip
        // is what makes neighbours agree.
        let seed = NoiseField.seed(context.idPrefix)

        return sprites.map { sprite in
            PositionResample.warp(sprite, rate: rate) { x, y, time in
                let z = speed * time / 1000
                let dx = NoiseField.value(x / scale, y / scale, z, seed: seed) * 2 - 1
                let dy = NoiseField.value(x / scale, y / scale, z, seed: seed &+ 0x9E37_79B9) * 2 - 1
                return (x + dx * amount, y + dy * amount)
            }
        }
    }
}

/// Smooth, seeded value noise in three dimensions, 0–1.
///
/// Value noise rather than gradient noise: it is a few lines, it stays inside
/// its range by construction, and at the sizes a storyboard moves things the
/// difference does not show.
enum NoiseField {
    static func value(_ x: Double, _ y: Double, _ z: Double, seed: UInt64) -> Double {
        let x0 = x.rounded(.down), y0 = y.rounded(.down), z0 = z.rounded(.down)
        let fx = smooth(x - x0), fy = smooth(y - y0), fz = smooth(z - z0)
        let ix = Int64(x0), iy = Int64(y0), iz = Int64(z0)

        func corner(_ dx: Int64, _ dy: Int64, _ dz: Int64) -> Double {
            lattice(ix + dx, iy + dy, iz + dz, seed: seed)
        }
        func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

        let x00 = lerp(corner(0, 0, 0), corner(1, 0, 0), fx)
        let x10 = lerp(corner(0, 1, 0), corner(1, 1, 0), fx)
        let x01 = lerp(corner(0, 0, 1), corner(1, 0, 1), fx)
        let x11 = lerp(corner(0, 1, 1), corner(1, 1, 1), fx)
        return lerp(lerp(x00, x10, fy), lerp(x01, x11, fy), fz)
    }

    /// A stable seed from a string. Not `hashValue`, which Swift randomises
    /// per process — the same project would wobble differently every launch,
    /// and the preview would stop matching the exported file.
    static func seed(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01B3
        }
        return hash
    }

    private static func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }

    /// SplitMix64 over the mixed coordinates: a different, repeatable number
    /// at every lattice point.
    private static func lattice(_ x: Int64, _ y: Int64, _ z: Int64, seed: UInt64) -> Double {
        var h = seed
        h ^= UInt64(bitPattern: x) &* 0x9E37_79B9_7F4A_7C15
        h ^= UInt64(bitPattern: y) &* 0xC2B2_AE3D_27D4_EB4F
        h ^= UInt64(bitPattern: z) &* 0x1656_67B1_9E37_79F9
        h = (h ^ (h >> 30)) &* 0xBF58_476D_1CE4_E5B9
        h = (h ^ (h >> 27)) &* 0x94D0_49BB_1331_11EB
        h ^= h >> 31
        return Double(h >> 11) / Double(1 << 53)
    }
}
