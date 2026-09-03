import Foundation
import Testing

@testable import StoryboardCore

/// The shape effect: bars, frames, letterboxes and underlines without a PNG.
@Suite("Shape")
struct ShapeEffectTests {
    private let evaluator = EffectEvaluator()

    private func node(
        _ values: [String: EffectValue] = [:],
        duration: Double = 2000,
    ) -> EffectNode {
        EffectNode(
            id: "shape",
            type: ShapeEffect.descriptor.type,
            name: "Shape",
            startTime: 0,
            duration: duration,
            seed: 1,
            values: ShapeEffect.descriptor.defaultValues.merging(values) { _, new in new },
        )
    }

    /// However large it is drawn, it stays one sprite: the whole point of a
    /// drawn shape over a tiled one is that a full-width bar costs what a dot
    /// costs.
    @Test("a shape is one sprite at any size", arguments: [10.0, 400.0, 1800.0])
    func alwaysOneSprite(width: Double) {
        let sprites = evaluator.evaluate(node([ShapeEffect.Param.width: .number(width)]))
        #expect(sprites.count == 1)
    }

    /// The size is in stage units, so a bar asked for at 854 covers the stage.
    @Test("the size is in stage units")
    func sizeIsInStageUnits() {
        let sprites = evaluator.evaluate(node([
            ShapeEffect.Param.width: .number(854),
            ShapeEffect.Param.height: .number(64),
        ]))

        var drawn: (width: Double, height: Double)?
        for command in sprites.first?.commands ?? [] {
            if case let .vectorScale(sx, sy, _, _) = command.payload {
                drawn = (sx * ShapeEffect.sourceSize, sy * ShapeEffect.sourceSize)
            }
        }

        let size = try? #require(drawn)
        #expect(abs((size?.width ?? 0) - 854) < 1)
        #expect(abs((size?.height ?? 0) - 64) < 1)
    }

    /// Both axes are set independently — a bar is a rectangle with very
    /// different ones, and a uniform scale could not express it.
    @Test("width and height are independent")
    func axesAreIndependent() {
        let sprites = evaluator.evaluate(node([
            ShapeEffect.Param.width: .number(800),
            ShapeEffect.Param.height: .number(20),
        ]))

        let vectors = sprites.flatMap(\.commands).filter { $0.kind == .vectorScale }
        #expect(!vectors.isEmpty, "a shape has to use _V, not _S")

        if case let .vectorScale(sx, sy, _, _) = vectors.first?.payload {
            #expect(sx > sy * 10, "the axes came out the same")
        }
    }

    /// A ring is exempt from the fixed list: its thickness is drawn into the
    /// texture, so it names a family of images rather than one of them.
    @Test("every kind names a real built-in image", arguments: ShapeEffect.Kind.allCases)
    func kindsUseKnownSprites(kind: ShapeEffect.Kind) {
        let path = kind.sprite(thickness: 0.12)
        if kind == .ring {
            #expect(path.hasPrefix("__builtin__/hoop"))
        } else {
            #expect(BuiltInSprite.all.contains(path))
        }
    }

    @Test("each kind draws something", arguments: ShapeEffect.Kind.allCases)
    func kindsDraw(kind: ShapeEffect.Kind) {
        let sprites = evaluator.evaluate(node([ShapeEffect.Param.kind: .choice(kind.rawValue)]))
        #expect(sprites.count == 1)
        #expect(sprites.first?.filePath == kind.sprite(thickness: 0.12))
    }

    /// It holds for the whole clip rather than fading: a shape is placed, not
    /// performed, and an entrance written in here would have to be found and
    /// switched off before the plain case was available.
    @Test("a shape holds for its whole clip")
    func holdsThroughout() {
        let duration = 5000.0
        let sprites = evaluator.evaluate(node(duration: duration))
        let prepared = StoryboardResolver.prepare(sprites)

        for fraction in [0.0, 0.25, 0.5, 0.99] {
            var states: [SpriteRenderState] = []
            StoryboardResolver.resolve(prepared, at: duration * fraction, into: &states)
            #expect(
                states.contains { $0.visible && $0.opacity > 0.9 },
                "gone at \(fraction) of the clip",
            )
        }
    }

    /// Fully transparent means nothing at all, rather than a sprite nobody can
    /// see costing a line in the file.
    @Test("no opacity means no sprite")
    func transparentDrawsNothing() {
        #expect(evaluator.evaluate(node([ShapeEffect.Param.opacity: .number(0)])).isEmpty)
    }

    /// White writes no colour command: a tint that changes nothing is a line in
    /// the file for nothing, multiplied by every shape in the storyboard.
    @Test("white writes no colour command")
    func whiteIsFree() {
        let plain = evaluator.evaluate(node()).flatMap(\.commands)
        #expect(!plain.contains { $0.kind == .color })

        let red = evaluator.evaluate(node([
            ShapeEffect.Param.color: .color(EffectColor(r: 255, g: 0, b: 0)),
        ])).flatMap(\.commands)
        #expect(red.contains { $0.kind == .color })
    }

    /// Animating one axis must not throw away the size the shape was drawn at.
    ///
    /// The transform used to replace the sprite's scale outright, so a bar
    /// asked for at 854×80 lost the `_V` that said so the moment anyone
    /// keyframed Scale Y — and came out a square. What the effect draws is its
    /// **size**; what the transform animates is a **factor** on it, and both
    /// have to survive.
    @Test("a keyframed scale multiplies the shape's size rather than replacing it")
    func animatedScaleKeepsTheSize() {
        var document = EffectDocument()
        let node = document.add(ShapeEffect.descriptor, at: 0, duration: 2000)
        document.setValue(.number(854), for: ShapeEffect.Param.width, on: node.id)
        document.setValue(.number(80), for: ShapeEffect.Param.height, on: node.id)

        document.setKeyframe(1, for: .scaleY, at: 0, on: node.id)
        document.setKeyframe(2, for: .scaleY, at: 2000, on: node.id)

        let scales = evaluator.evaluate(document)
            .flatMap(\.commands)
            .compactMap { command -> (Double, Double, Double)? in
                guard case let .vectorScale(sx, sy, _, ey) = command.payload else { return nil }
                return (sx, sy, ey)
            }

        guard let (startX, startY, endY) = scales.first else {
            Issue.record("the shape lost its vector scale")
            return
        }

        let expectedX = 854 / ShapeEffect.sourceSize
        let expectedY = 80 / ShapeEffect.sourceSize

        // The untouched axis keeps its width exactly.
        #expect(abs(startX - expectedX) < 0.01, "the width changed: \(startX)")
        // The animated one starts at the drawn height and doubles.
        #expect(abs(startY - expectedY) < 0.01)
        #expect(abs(endY - expectedY * 2) < 0.01)
    }

    /// Thickness belongs to a ring and nothing else.
    ///
    /// A slider that does nothing is a control that lies, and the condition is
    /// declared on the **parameter** rather than decided by the inspector: the
    /// descriptor stays the only thing the UI reads, so an effect that adds a
    /// conditional parameter still needs no UI work.
    @Test("thickness shows only for a ring")
    func thicknessIsForRingsOnly() throws {
        let thickness = try #require(
            ShapeEffect.descriptor.parameters.first { $0.id == ShapeEffect.Param.thickness },
        )
        let condition = try #require(thickness.shownWhen)

        for kind in ShapeEffect.Kind.allCases {
            let values: [String: EffectValue] = [ShapeEffect.Param.kind: .choice(kind.rawValue)]
            #expect(condition.holds(in: values) == (kind == .ring), "wrong for \(kind)")
        }
    }

    /// A parameter with no condition is always shown — the default has to be
    /// "visible", or adding the mechanism would hide every existing control.
    @Test("unconditional parameters are unaffected")
    func plainParametersAlwaysShow() {
        let unconditional = ShapeEffect.descriptor.parameters.filter { $0.shownWhen == nil }
        #expect(unconditional.count == ShapeEffect.descriptor.parameters.count - 1)
    }
}
