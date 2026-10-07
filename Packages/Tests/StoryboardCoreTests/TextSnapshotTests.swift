import Foundation
import Testing

@testable import StoryboardCore

/// The Text Animator work adds axes to `TextEffect` without moving anything
/// that already exists. These tests hold that: production against a frozen
/// copy of the old implementation (`LegacyTextEffect`), sprite by sprite and
/// command by command, with no tolerance.
///
/// Compared through `String(reflecting:)` because sprites and commands are not
/// `Equatable`, and doubles print their exact value — which is what "no
/// epsilon" means here.
@Suite("Text snapshot")
struct TextSnapshotTests {
    private static let texts = [
        "HELLO  WORLD",
        "ab c\n\nxyz",
        "ABCDEFGHIJKLMNOPQRSTU",
        "あいう えお",
    ]
    private static let seeds: [UInt64] = [1, 8371, 99123]

    /// Every preset the effect shipped with, plus the bare defaults.
    private static let cases: [(name: String, duration: Double, values: [String: EffectValue])] =
        [("defaults", 3000, [:])]
            + TextEffect.presets
            .filter { legacyPresetIDs.contains($0.id) }
            .map { ($0.id, $0.duration, $0.values) }

    private static let legacyPresetIDs: Set<String> = [
        "typewriter", "fade-up", "drop", "pop-in", "sweep", "scatter",
        "text-shockwave", "unfold", "cascade", "wave", "glitch", "reveal-centre",
        "drift-apart", "burst", "led-sign",
    ]

    private func node(
        text: String, seed: UInt64, duration: Double, values: [String: EffectValue],
    ) -> EffectNode {
        var document = EffectDocument()
        var node = document.add(TextEffect.descriptor, at: 0, duration: duration)
        node.values = values
        node.values[TextEffect.Param.text] = .text(text)
        node.seed = seed
        return node
    }

    private func dump(_ sprites: [StoryboardSprite]) -> [String] {
        sprites.map { String(reflecting: $0) }
    }

    private func production(_ node: EffectNode) -> [String] {
        let context = EffectContext(descriptor: TextEffect.descriptor, node: node)
        var rng = EffectRandom(seed: node.seed)
        return dump(TextEffect().evaluate(in: context, rng: &rng))
    }

    private func oracle(_ node: EffectNode) -> [String] {
        let context = EffectContext(descriptor: TextEffect.descriptor, node: node)
        var rng = EffectRandom(seed: node.seed)
        return dump(LegacyTextEffect().evaluate(in: context, rng: &rng))
    }

    /// A measurer installed by another suite would change every width and make
    /// both sides agree about something they should not be sharing.
    @Test("the snapshot runs on the fallback metrics")
    func fallbackMetrics() {
        #expect(TextMetrics.measure == nil)
    }

    @Test("every legacy preset is in the matrix")
    func matrixIsComplete() {
        let found = Set(Self.cases.map(\.name)).subtracting(["defaults"])
        #expect(found == Self.legacyPresetIDs)
    }

    /// S1.1 – S1.5: defaults and the fifteen shipped presets, over multi-line,
    /// repeated-space, 21-character and Japanese text, under three seeds.
    /// Random order, Explode and Drift are in there through the presets that
    /// use them (scatter, text-shockwave/burst, drift-apart).
    @Test("the existing behaviour is unchanged")
    func unchanged() {
        var compared = 0
        for item in Self.cases {
            for text in Self.texts {
                for seed in Self.seeds {
                    let subject = node(
                        text: text, seed: seed, duration: item.duration, values: item.values,
                    )
                    let expected = oracle(subject)
                    #expect(
                        production(subject) == expected,
                        "\(item.name) · \(text.debugDescription) · seed \(seed)",
                    )
                    #expect(!expected.isEmpty)
                    compared += 1
                }
            }
        }
        #expect(compared == 16 * 4 * 3)
    }

    /// The oracle has to be able to disagree, or the test above proves nothing:
    /// different seeds must give different Random-order output.
    @Test("the oracle is sensitive to the seed")
    func oracleSeesSeeds() {
        let scatter = TextEffect.presets.first { $0.id == "scatter" }!
        let a = node(text: "ABCDEFGH", seed: 1, duration: scatter.duration, values: scatter.values)
        let b = node(text: "ABCDEFGH", seed: 8371, duration: scatter.duration, values: scatter.values)
        #expect(oracle(a) != oracle(b))
    }

    /// S1.6: a node saved before any new key existed has no entries for them
    /// and has to read exactly as the defaults do.
    @Test("a node without the newer keys evaluates as its defaults")
    func absentKeysAreDefaults() throws {
        var document = EffectDocument()
        var stored = document.add(TextEffect.descriptor, at: 0, duration: 3000)
        stored.values = [TextEffect.Param.text: .text("HELLO WORLD")]
        stored.seed = 7

        // Round-tripped through JSON, as a saved project is.
        let data = try JSONEncoder().encode(stored)
        let decoded = try JSONDecoder().decode(EffectNode.self, from: data)

        var full = stored
        full.values = TextEffect.descriptor.defaultValues
        full.values[TextEffect.Param.text] = .text("HELLO WORLD")

        #expect(production(decoded) == production(full))
        #expect(production(decoded) == oracle(decoded))
    }
}
