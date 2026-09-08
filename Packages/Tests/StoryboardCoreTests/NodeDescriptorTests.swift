import Foundation
import Testing

@testable import StoryboardCore

/// Resolving a descriptor from a node rather than from a type.
///
/// Every effect that exists today has one parameter set fixed at compile time,
/// so a static descriptor was enough. A scripted effect breaks that: two script
/// nodes share one type and declare different parameters, so the descriptor has
/// to be a function of the node.
///
/// These tests exist to prove that opening that door costs the native effects
/// nothing — and to keep costing them nothing later.
@Suite("Node descriptors")
struct NodeDescriptorTests {
    private let evaluator = EffectEvaluator()

    private func node(type: String) -> EffectNode {
        EffectNode(
            id: "fx",
            type: type,
            name: "Node",
            startTime: 1000,
            duration: 4000,
            seed: 99,
        )
    }

    /// The five registered effects, by the type string each declares.
    private static let nativeTypes = [
        ImageEffect.descriptor.type,
        ShapeEffect.descriptor.type,
        TextEffect.descriptor.type,
        EmitterEffect.descriptor.type,
        AudioBarsEffect.descriptor.type,
    ]

    // MARK: - The protocol requirement

    @Test("an effect with no override answers with its static descriptor", arguments: nativeTypes)
    func defaultMatchesStatic(type: String) throws {
        let library = EffectLibrary.standard
        let effect = try #require(library.effect(for: type))

        #expect(effect.descriptor(for: node(type: type)) == Swift.type(of: effect).descriptor)
    }

    /// The node must not be able to change a native effect's answer.
    ///
    /// The default implementation ignores its argument, and that is the whole
    /// point: an effect only overrides this when its parameters genuinely
    /// depend on what is stored.
    @Test("a native effect ignores the node it is handed", arguments: nativeTypes)
    func defaultIgnoresNode(type: String) throws {
        let library = EffectLibrary.standard
        let effect = try #require(library.effect(for: type))

        var loaded = node(type: type)
        loaded.values = ["nonsense": .number(7)]
        loaded.seed = 12345
        loaded.duration = 999

        #expect(effect.descriptor(for: loaded) == effect.descriptor(for: node(type: type)))
    }

    // MARK: - Library lookup

    @Test("the library resolves a descriptor from a node", arguments: nativeTypes)
    func libraryResolvesFromNode(type: String) throws {
        let resolved = try #require(EffectLibrary.standard.descriptor(for: node(type: type)))

        #expect(resolved == EffectLibrary.standard.descriptor(for: type))
    }

    @Test("an unregistered type resolves to nothing")
    func unregisteredTypeIsNil() {
        #expect(EffectLibrary.standard.descriptor(for: node(type: "not-an-effect")) == nil)
    }

    /// The type-only lookup has to survive: the library browser lists tools
    /// with no node in hand, so it has nothing to pass.
    @Test("the type-only lookup still answers")
    func typeLookupSurvives() {
        #expect(EffectLibrary.standard.descriptor(for: EmitterEffect.descriptor.type) != nil)
    }

    // MARK: - The regression guard

    /// A fingerprint of everything the renderer would draw.
    ///
    /// Read from the evaluated output rather than re-deriving what the effect
    /// should have produced: a test that reimplements its subject's formula
    /// agrees with any formula, including a wrong one.
    private func signature(_ sprites: [StoryboardSprite]) -> String {
        sprites.map { sprite in
            let commands = sprite.commands.map { command in
                "\(command.kind.rawValue):\(command.startTime):\(command.endTime):\(payload(command))"
            }.joined(separator: "|")
            return "\(sprite.id);\(sprite.filePath);\(sprite.layer);\(sprite.origin);\(sprite.defaultX);\(sprite.defaultY);\(commands)"
        }.joined(separator: "\n")
    }

    private func payload(_ command: Command) -> String {
        switch command.payload {
        case let .fade(a, b): "\(a),\(b)"
        case let .move(a, b, c, d): "\(a),\(b),\(c),\(d)"
        case let .moveX(a, b): "\(a),\(b)"
        case let .moveY(a, b): "\(a),\(b)"
        case let .scale(a, b): "\(a),\(b)"
        case let .vectorScale(a, b, c, d): "\(a),\(b),\(c),\(d)"
        case let .rotate(a, b): "\(a),\(b)"
        case let .color(a, b, c, d, e, f): "\(a),\(b),\(c),\(d),\(e),\(f)"
        case let .parameter(kind): kind.rawValue
        }
    }

    /// The least each effect needs stored before it draws anything.
    ///
    /// A node built from defaults alone is not a fair subject: `ImageEffect`
    /// with no file is a placeholder someone is about to fill in and correctly
    /// draws nothing, so a guard handed one would compare empty against empty
    /// and pass no matter what broke underneath it.
    private static func drawable(_ type: String) -> [String: EffectValue] {
        switch type {
        case ImageEffect.descriptor.type: ["sprite": .text(BuiltInSprite.soft)]
        case TextEffect.descriptor.type: ["text": .text("AB")]
        default: [:]
        }
    }

    /// What the evaluator draws when handed the descriptor the effect itself
    /// declares — the answer the routing change must not alter.
    ///
    /// Compared against the effect evaluated directly, not against hand-written
    /// expectations: nobody writes 2000 sprites' worth by hand, and a wrong
    /// expectation would only teach the suite to accept a wrong answer.
    ///
    /// It is deliberately not enough to assert the output is non-empty. Handing
    /// `TextEffect` a foreign descriptor makes it draw nothing, so emptiness
    /// catches that one — but the other four read parameters the foreign
    /// descriptor lacks, fall back to defaults, and produce something anyway.
    /// A guard that only checks for output would call four of five healthy.
    ///
    /// Measured, by routing the evaluator through `EmitterEffect.descriptor` on
    /// purpose: this catches `text` (2 sprites → 0) and `audioBars` (24 bars →
    /// 7, 1920 commands → 140). `image`, `shape` and `emitter` still pass,
    /// because a node carrying only defaults gives them nothing to disagree
    /// about — their reads either share a name with an emitter parameter or
    /// fall back to the same value either way.
    ///
    /// That limit is recorded rather than papered over. Two of five failing is
    /// enough to catch the routing being wrong at all, which is what this
    /// guards; proving it per effect would need a node whose stored values
    /// distinguish each one, and the effects' own parameter suites already do
    /// that job.
    @Test("every native effect still draws what its own descriptor says", arguments: nativeTypes)
    func nativeOutputIsUnchanged(type: String) throws {
        let effect = try #require(EffectLibrary.standard.effect(for: type))

        var placed = node(type: type)
        placed.values = Self.drawable(type)

        let throughEvaluator = signature(evaluator.evaluate(placed))

        // The same node, evaluated with the descriptor asked of the effect
        // directly. This is what the evaluator must be doing internally.
        var rng = EffectRandom(seed: placed.seed)
        let direct = signature(effect.evaluate(
            in: EffectContext(descriptor: Swift.type(of: effect).descriptor, node: placed),
            rng: &rng,
        ))

        #expect(!direct.isEmpty, "\(type) drew nothing, so this guard would pass no matter what broke")

        // The evaluator shifts by `startTime` and stamps the layer afterwards,
        // so the two are not textually equal — but every sprite and command the
        // effect produced has to be there, in the same order and the same
        // count. A foreign descriptor changes what the effect reads, and that
        // shows up here as a different shape even when output survives.
        #expect(
            throughEvaluator.split(separator: "\n").count == direct.split(separator: "\n").count,
            "\(type) produced a different number of sprites through the evaluator",
        )
        #expect(
            throughEvaluator.filter { $0 == "|" }.count == direct.filter { $0 == "|" }.count,
            "\(type) produced a different number of commands through the evaluator",
        )
        #expect(
            throughEvaluator.split(separator: "\n").map { $0.split(separator: ";").first }
                == direct.split(separator: "\n").map { $0.split(separator: ";").first },
            "\(type) produced different sprite ids through the evaluator",
        )
    }

    /// Two evaluations of one node have to agree.
    ///
    /// Kept apart from the comparison above because it is a different claim:
    /// that one is about the routing, this one about the effect being a pure
    /// function of what it was handed. If this fails, nothing else in the suite
    /// means anything.
    @Test("evaluating the same node twice draws the same thing", arguments: nativeTypes)
    func evaluationIsRepeatable(type: String) {
        var placed = node(type: type)
        placed.values = Self.drawable(type)

        #expect(signature(evaluator.evaluate(placed)) == signature(evaluator.evaluate(placed)))
    }
}
