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

    // ─── Fill ────────────────────────────────────────────────────────────────

    /// Solid is the default, so a shape dropped on the canvas is the plain one.
    /// A fill that faded out of the box would be a decision made for the author
    /// that they would have to find and undo.
    @Test("a shape is solid unless asked otherwise")
    func solidByDefault() {
        let sprites = evaluator.evaluate(node())
        #expect(sprites.first?.filePath == ShapeEffect.Kind.square.sprite(thickness: 0.12))
    }

    @Test("a gradient fill names a gradient image", arguments: ShapeEffect.Kind.allCases)
    func gradientFillNamesAGradient(kind: ShapeEffect.Kind) throws {
        let sprites = evaluator.evaluate(node([
            ShapeEffect.Param.kind: .choice(kind.rawValue),
            ShapeEffect.Param.fill: .choice(ShapeEffect.Fill.gradient.rawValue),
        ]))

        let path = try #require(sprites.first?.filePath)
        let profile = try #require(
            BuiltInSprite.gradientProfile(path), "\(path) is not a gradient",
        )
        #expect(profile.shape == kind.gradientShape)
    }

    /// The angle and stops are the author's, so they have to reach the image —
    /// a parameter the effect reads and then ignores is a slider that lies.
    @Test("the gradient parameters reach the image")
    func gradientParametersReachTheImage() throws {
        let sprites = evaluator.evaluate(node([
            ShapeEffect.Param.fill: .choice(ShapeEffect.Fill.gradient.rawValue),
            ShapeEffect.Param.gradientAngle: .number(90),
            ShapeEffect.Param.gradientStart: .number(0.25),
            ShapeEffect.Param.gradientEnd: .number(0.75),
        ]))

        let path = try #require(sprites.first?.filePath)
        let profile = try #require(BuiltInSprite.gradientProfile(path))
        #expect(profile.angle == 90)
        #expect(abs(profile.start - 0.25) < 0.001)
        #expect(abs(profile.end - 0.75) < 0.001)
    }

    /// The gradient's own controls belong to a gradient and nothing else — the
    /// same rule thickness follows, and the reason `Fill` is an enum rather than
    /// a toggle: a slot that can grow keeps its conditions in one place.
    @Test(
        "the gradient controls show only for a gradient",
        arguments: [
            ShapeEffect.Param.gradientAngle,
            ShapeEffect.Param.gradientStart,
            ShapeEffect.Param.gradientEnd,
        ],
    )
    func gradientControlsAreConditional(id: String) throws {
        let parameter = try #require(ShapeEffect.descriptor.parameters.first { $0.id == id })
        let condition = try #require(parameter.shownWhen)

        for fill in ShapeEffect.Fill.allCases {
            let values: [String: EffectValue] = [ShapeEffect.Param.fill: .choice(fill.rawValue)]
            #expect(condition.holds(in: values) == (fill == .gradient), "wrong for \(fill)")
        }
    }

    // ─── Mirroring ───────────────────────────────────────────────────────────

    /// **A flip is not a rotation**, and this is the case that shows it.
    ///
    /// A rotation turns the shape about its anchor, so a left-anchored bar spun
    /// 180° swings off the far side of its own edge and leaves the stage — the
    /// image does invert, and it inverts somewhere nobody can see. A flip
    /// mirrors it where it stands.
    @Test("flipping writes a mirror command and does not move the shape")
    func flipMirrorsInPlace() throws {
        let plain = try #require(evaluator.evaluate(node()).first)
        let flipped = try #require(evaluator.evaluate(node([
            ShapeEffect.Param.flipH: .toggle(true),
        ])).first)

        #expect(flipped.defaultX == plain.defaultX, "a mirror does not move it")
        #expect(flipped.commands.contains { { if case .parameter(.flipHorizontal) = $0.payload { true } else { false } }($0) })
        #expect(!plain.commands.contains { { if case .parameter(.flipHorizontal) = $0.payload { true } else { false } }($0) })
    }

    @Test("the vertical flip is its own toggle")
    func verticalFlipIsSeparate() throws {
        let sprite = try #require(evaluator.evaluate(node([
            ShapeEffect.Param.flipV: .toggle(true),
        ])).first)

        #expect(sprite.commands.contains { { if case .parameter(.flipVertical) = $0.payload { true } else { false } }($0) })
        #expect(!sprite.commands.contains { { if case .parameter(.flipHorizontal) = $0.payload { true } else { false } }($0) })
    }

    /// Both at once is a half turn — and unlike an actual rotation it stays
    /// where it is, which is the whole reason these exist.
    @Test("both axes mirror together")
    func bothAxesMirror() throws {
        let sprite = try #require(evaluator.evaluate(node([
            ShapeEffect.Param.flipH: .toggle(true),
            ShapeEffect.Param.flipV: .toggle(true),
        ])).first)

        #expect(sprite.commands.contains { { if case .parameter(.flipHorizontal) = $0.payload { true } else { false } }($0) })
        #expect(sprite.commands.contains { { if case .parameter(.flipVertical) = $0.payload { true } else { false } }($0) })
    }

    /// Off writes nothing: a command that changes nothing is a line in the file
    /// for nothing, multiplied by every shape in the storyboard — the same rule
    /// white already follows for colour.
    @Test("not flipping writes no command")
    func noFlipIsFree() {
        let commands = evaluator.evaluate(node()).flatMap(\.commands)
        #expect(!commands.contains { $0.kind == .parameter })
    }

    /// A mirrored gradient is the case this was added for: the ramp has to fall
    /// the other way without the shape moving.
    @Test("a flipped gradient keeps its place")
    func flippedGradientStaysPut() throws {
        let values: [String: EffectValue] = [
            ShapeEffect.Param.fill: .choice(ShapeEffect.Fill.gradient.rawValue),
            ShapeEffect.Param.origin: .choice(Origin.centreLeft.rawValue),
        ]
        let plain = try #require(evaluator.evaluate(node(values)).first)

        var mirrored = values
        mirrored[ShapeEffect.Param.flipH] = .toggle(true)
        let flipped = try #require(evaluator.evaluate(node(mirrored)).first)

        #expect(flipped.defaultX == plain.defaultX)
        #expect(flipped.filePath == plain.filePath, "a mirror is free — no second texture")
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
    ///
    /// Named rather than counted. A count breaks whenever a conditional
    /// parameter is legitimately added — it did when the gradient arrived —
    /// and it never checked what the line above promises: that the
    /// *unconditional* ones stay unconditional.
    @Test("unconditional parameters are unaffected")
    func plainParametersAlwaysShow() {
        let alwaysShown = [
            ShapeEffect.Param.kind,
            ShapeEffect.Param.origin,
            ShapeEffect.Param.width,
            ShapeEffect.Param.height,
            ShapeEffect.Param.fill,
            ShapeEffect.Param.flipH,
            ShapeEffect.Param.flipV,
            ShapeEffect.Param.color,
            ShapeEffect.Param.opacity,
            ShapeEffect.Param.additive,
        ]

        for id in alwaysShown {
            let parameter = ShapeEffect.descriptor.parameters.first { $0.id == id }
            #expect(parameter != nil, "\(id) is not a parameter")
            #expect(parameter?.shownWhen == nil, "\(id) grew a condition")
        }
    }
}
