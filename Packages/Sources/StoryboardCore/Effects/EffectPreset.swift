import Foundation

/// A named set of parameter values for an effect.
///
/// Presets are where a particle system becomes usable. Nobody dials twenty-five
/// parameters from nothing: they pick something close and adjust it, which is
/// what made Particle Illusion's library its most valuable part. A preset is
/// just values — no code, no special case in the evaluator — so a scripted
/// effect will be able to ship them the same way.
public struct EffectPreset: Sendable, Identifiable {
    public let id: String
    public var name: String
    /// Which effect these values belong to, matching `EffectDescriptor.type`.
    public let effectType: String
    /// One line on what it looks like, for the picker.
    public var summary: String
    /// How long the placed block should be.
    ///
    /// Part of the preset because a burst and a continuous stream want very
    /// different lengths: a shockwave is over in under a second, and dropping
    /// one into a five-second block leaves four seconds of nothing that reads
    /// as the effect having failed.
    public var duration: Double
    public var values: [String: EffectValue]

    /// Further layers the preset brings with it.
    ///
    /// What makes a compound preset: a circle of fire is a base, embers and a
    /// halo, each with its own sprite and numbers. Dropped from the library it
    /// arrives whole — one item to place, several to tune.
    ///
    /// Described rather than built: a preset is values, and a layer is more
    /// values. Whoever places it turns these into nodes, which is the only
    /// place that knows how to make an id or a seed.
    public var layers: [Layer]

    /// The pack this belongs to, if it is not simply one of its effect's own
    /// presets.
    ///
    /// A compound is several emitters wearing one name, so filing it under
    /// "Emitter" beside fifteen single-emitter presets says the wrong thing
    /// twice: it buries the ones that are worth reaching for, and it implies
    /// they are variations on the row above rather than built things. `nil`
    /// keeps a preset with its effect, which is right for the plain ones.
    public var pack: String?

    /// One layer of a compound preset.
    public struct Layer: Sendable {
        public let effectType: String
        public var name: String
        public var values: [String: EffectValue]

        public init(effectType: String, name: String, values: [String: EffectValue]) {
            self.effectType = effectType
            self.name = name
            self.values = values
        }
    }

    public init(
        id: String,
        name: String,
        effectType: String,
        summary: String,
        duration: Double = 4000,
        values: [String: EffectValue],
        layers: [Layer] = [],
        pack: String? = nil,
    ) {
        self.layers = layers
        self.pack = pack
        self.id = id
        self.name = name
        self.effectType = effectType
        self.summary = summary
        self.duration = duration
        self.values = values
    }
}

/// Built-in shape paths, spelled here because `StoryboardCore` sits below the
/// renderer that draws them.
///
/// A test checks these against `BuiltInTextures.Shape`.
public enum BuiltInSprite {
    public static let soft = "__builtin__/soft.png"
    public static let glow = "__builtin__/glow.png"
    public static let smoke = "__builtin__/smoke.png"
    public static let star = "__builtin__/star.png"
    public static let square = "__builtin__/square.png"
    public static let streak = "__builtin__/streak.png"
    public static let ring = "__builtin__/ring.png"

    public static let shapes = [soft, glow, smoke, star, square, streak, ring]

    /// Textures shipped as files, for the shapes code cannot draw — a branching
    /// bolt, a flame with a real silhouette, a directional flash.
    ///
    /// From the Kenney Particle Pack (CC0). A test checks these against what
    /// the renderer actually ships.
    public static let lightning = "__builtin__/spark_01.png"
    public static let lightningWide = "__builtin__/spark_03.png"
    public static let bolt = "__builtin__/spark_05.png"
    public static let boltThin = "__builtin__/trace_05.png"
    public static let flame = "__builtin__/flame_05.png"
    public static let flameTall = "__builtin__/flame_06.png"
    public static let flameWisp = "__builtin__/flame_01.png"
    public static let ember = "__builtin__/fire_01.png"
    public static let muzzle = "__builtin__/muzzle_01.png"
    public static let muzzleWide = "__builtin__/muzzle_03.png"
    public static let arc = "__builtin__/twirl_01.png"
    public static let crescent = "__builtin__/twirl_02.png"
    public static let scratch = "__builtin__/scratch_01.png"
    public static let slash = "__builtin__/slash_01.png"
    /// A broad, clean arc — the shape a wave front makes.
    public static let slashWide = "__builtin__/slash_04.png"
    public static let slashDeep = "__builtin__/slash_02.png"
    public static let slashThin = "__builtin__/slash_03.png"
    /// A soft vertical column: a beam as a drawing, not as a stream of
    /// particles pretending to be one.
    public static let beam = "__builtin__/trace_01.png"
    public static let beamThin = "__builtin__/trace_02.png"
    public static let scorch = "__builtin__/scorch_01.png"
    public static let rune = "__builtin__/symbol_01.png"
    public static let flare = "__builtin__/magic_03.png"
    public static let flareSoft = "__builtin__/magic_04.png"
    public static let runeRing = "__builtin__/magic_01.png"
    public static let cloud = "__builtin__/smoke_04.png"
    public static let cloudWisp = "__builtin__/smoke_07.png"
    public static let sparkle = "__builtin__/star_04.png"
    public static let debris = "__builtin__/dirt_01.png"
    public static let pane = "__builtin__/window_01.png"

    public static let textures = [
        lightning, lightningWide, bolt, boltThin,
        flame, flameTall, flameWisp, ember,
        muzzle, muzzleWide, arc, crescent,
        scratch, slash, slashWide, slashDeep, slashThin,
        beam, beamThin, scorch, rune,
        flare, flareSoft, runeRing,
        cloud, cloudWisp, sparkle, debris, pane,
    ]

    public static let all = shapes + textures
}
