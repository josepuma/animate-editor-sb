import Foundation
import Testing

@testable import StoryboardCore

/// Every declared parameter has to actually reach the output.
///
/// A parameter read with an id that does not match its declaration silently
/// yields a default, and a parameter declared but never read compiles fine —
/// both leave a control in the inspector that does nothing when dragged. The
/// only way to know is to change each one and check the sprites differ.
@Suite("Emitter parameters take effect")
struct EmitterParameterEffectTests {
    private let evaluator = EffectEvaluator()

    private func sprites(_ overrides: [String: EffectValue]) -> [StoryboardSprite] {
        var values = EmitterEffect.descriptor.defaultValues
        // A colour ramp in the baseline, so the colour parameters have
        // something to change. All-white would make switching the midpoint on
        // correctly produce nothing, and the case would read as a broken
        // parameter rather than as a redundant one.
        values[EmitterEffect.Param.color] = .color(EffectColor(r: 255, g: 200, b: 60))
        values[EmitterEffect.Param.colorEnd] = .color(EffectColor(r: 120, g: 20, b: 0))
        values[EmitterEffect.Param.colorMid] = .color(EffectColor(r: 255, g: 90, b: 20))
        // A visible box and some spin by default, so parameters that only
        // matter against a non-zero baseline have one.
        values[EmitterEffect.Param.count] = .integer(24)
        for (key, value) in overrides { values[key] = value }

        return evaluator.evaluate(EffectNode(
            id: "fx",
            type: "emitter",
            name: "Emitter",
            startTime: 0,
            duration: 4000,
            seed: 99,
            values: values,
        ))
    }

    /// A fingerprint of everything the renderer would draw.
    private func signature(_ sprites: [StoryboardSprite]) -> String {
        sprites.map { sprite in
            let commands = sprite.commands.map { command in
                "\(command.kind.rawValue):\(command.startTime):\(command.endTime):\(payload(command))"
            }.joined(separator: "|")
            return "\(sprite.filePath);\(sprite.defaultX);\(sprite.defaultY);\(commands)"
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

    /// Each parameter paired with a value that must change the result, and any
    /// other value its effect depends on.
    ///
    /// Some parameters only matter in a context: the midpoint colour is read
    /// only when the midpoint is switched on, and testing it without that would
    /// correctly find no change — reporting a working parameter as broken.
    private static let cases: [(id: String, value: EffectValue, context: [String: EffectValue])] = [
        (EmitterEffect.Param.count, .integer(40), [:]),
        (EmitterEffect.Param.emission, .choice("Burst"), [:]),
        (EmitterEffect.Param.burstCount, .integer(7),
         [EmitterEffect.Param.emission: .choice("Repeating Bursts")]),
        (EmitterEffect.Param.sprite, .text("sb/other.png"), [:]),

        (EmitterEffect.Param.width, .number(200), [:]),
        (EmitterEffect.Param.height, .number(150), [:]),

        (EmitterEffect.Param.direction, .number(90), [:]),
        (EmitterEffect.Param.spread, .number(180), [:]),
        (EmitterEffect.Param.velocity, .number(600), [:]),
        (EmitterEffect.Param.velocityRandom, .number(0.9), [:]),

        (EmitterEffect.Param.gravity, .number(900), [:]),
        (EmitterEffect.Param.drag, .number(0.8), [:]),

        (EmitterEffect.Param.life, .number(3000), [:]),
        (EmitterEffect.Param.lifeRandom, .number(0.9), [:]),
        (EmitterEffect.Param.scaleStart, .number(3), [:]),
        (EmitterEffect.Param.scaleEnd, .number(0.2), [:]),
        (EmitterEffect.Param.scaleRandom, .number(0.9), [:]),
        (EmitterEffect.Param.stretch, .number(6), [:]),
        (EmitterEffect.Param.alignToMotion, .toggle(true), [:]),
        (EmitterEffect.Param.rotation, .number(180), [:]),
        (EmitterEffect.Param.spin, .number(720), [:]),

        (EmitterEffect.Param.color, .color(EffectColor(r: 0, g: 40, b: 255)), [:]),
        (EmitterEffect.Param.colorEnd, .color(EffectColor(r: 10, g: 20, b: 200)), [:]),
        (EmitterEffect.Param.usesColorMid, .toggle(true), [:]),
        (EmitterEffect.Param.colorVariety, .number(0.8), [:]),
        (EmitterEffect.Param.colorMid, .color(EffectColor(r: 0, g: 255, b: 0)),
         [EmitterEffect.Param.usesColorMid: .toggle(true)]),
        (EmitterEffect.Param.opacity, .number(0.4), [:]),
        (EmitterEffect.Param.fadeIn, .number(0.8), [:]),
        (EmitterEffect.Param.fadeOut, .number(0.05), [:]),
        (EmitterEffect.Param.additive, .toggle(true), [:]),
    ]

    @Test("the cases cover every declared parameter")
    func casesAreComplete() {
        let covered = Set(Self.cases.map(\.id))
        let declared = Set(EmitterEffect.descriptor.parameters.map(\.id))

        #expect(covered == declared)
    }

    /// A declaration the inspector cannot render is a control that does not
    /// work, however correct the evaluation behind it is.
    @Test("every parameter declares what its control needs")
    func declarationsAreRenderable() {
        for parameter in EmitterEffect.descriptor.parameters {
            switch parameter.kind {
            case .number, .integer:
                // A slider with no bounds has nothing to slide between.
                #expect(
                    parameter.presentation != .slider || parameter.range != nil,
                    "\(parameter.id) is a slider with no range",
                )
                #expect(parameter.range != nil, "\(parameter.id) has no range")
                #expect(parameter.step ?? 0 > 0, "\(parameter.id) has no step")

            case .choice:
                #expect(!parameter.options.isEmpty, "\(parameter.id) has no options")
                // A default outside the menu leaves it showing a selection its
                // own list does not contain.
                if case let .choice(value) = parameter.defaultValue {
                    #expect(
                        parameter.options.contains(value),
                        "\(parameter.id) defaults to an option it does not offer",
                    )
                }

            case .toggle, .color, .text:
                break
            }

            #expect(!parameter.name.isEmpty)
            #expect(!parameter.group.isEmpty)
        }
    }

    @Test("changing a parameter changes the output", arguments: cases)
    func parameterChangesOutput(
        testCase: (id: String, value: EffectValue, context: [String: EffectValue]),
    ) {
        let baseline = signature(sprites(testCase.context))

        var changed = testCase.context
        changed[testCase.id] = testCase.value

        #expect(
            baseline != signature(sprites(changed)),
            "\(testCase.id) had no effect on the output",
        )
    }
}
