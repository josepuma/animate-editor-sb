import Foundation
import Testing

@testable import StoryboardCore

/// The LED filter and the derived paths it depends on.
///
/// The paths are half of the contract: Core writes them and the renderer reads
/// them back separately, so a disagreement between the two produces a texture
/// nobody asked for and no error to say so.
@Suite("LED filter")
struct LEDFilterTests {
    private let evaluator = EffectEvaluator()

    // ─── Paths ───────────────────────────────────────────────────────────────

    @Test("a dot-matrix path round-trips through parse")
    func dotMatrixPathRoundTrips() throws {
        let path = DerivedSprite.dotMatrix(
            "sb/a.png", pitch: 8, dotSize: 0.7, shape: .round, threshold: 0.5,
        )
        let parsed = try #require(DerivedSprite.parse(path))

        #expect(parsed.source == "sb/a.png")
        #expect(parsed.kind == .dotMatrix(
            pitch: 8, dotPercent: 70, shape: .round, thresholdPercent: 50,
        ))
        #expect(DerivedSprite.isDerived(path))
    }

    @Test("a dot panel path round-trips through parse")
    func dotPanelPathRoundTrips() throws {
        let path = DerivedSprite.dotPanel(
            columns: 108, rows: 60, pitch: 8, dotSize: 0.55, shape: .square,
        )
        let parsed = try #require(DerivedSprite.parse(path))

        #expect(parsed.kind == .dotPanel(
            columns: 108, rows: 60, pitch: 8, dotPercent: 55, shape: .square,
        ))
    }

    /// A slider dragged across its range must not mint a texture per position:
    /// every distinct path is another image in a fixed-size atlas.
    @Test("nearby values share a path, distant ones do not")
    func quantisation() {
        func path(
            pitch: Double = 8, dot: Double = 0.7, threshold: Double = 0.5,
            shape: DerivedSprite.DotShape = .round,
        ) -> String {
            DerivedSprite.dotMatrix(
                "x.png", pitch: pitch, dotSize: dot, shape: shape, threshold: threshold,
            )
        }

        #expect(path(pitch: 8.2) == path(pitch: 7.8))
        #expect(path(dot: 0.701) == path(dot: 0.699))
        #expect(path(threshold: 0.503) == path(threshold: 0.497))

        #expect(path(pitch: 9) != path())
        #expect(path(dot: 0.75) != path())
        #expect(path(threshold: 0.6) != path())
        #expect(path(shape: .square) != path())
    }

    /// Composed with another derivation, as a glow over LED text is: the
    /// source is itself a derived path, and only the first slash splits.
    @Test("a derived source nests")
    func nestedSource() throws {
        let inner = DerivedSprite.blurred("sb/a.png", radius: 4)
        let outer = DerivedSprite.dotMatrix(
            inner, pitch: 8, dotSize: 0.7, shape: .round, threshold: 0.5,
        )
        #expect(try #require(DerivedSprite.parse(outer)).source == inner)

        let blurredOuter = DerivedSprite.blurred(outer, radius: 8)
        let parsed = try #require(DerivedSprite.parse(blurredOuter))
        #expect(parsed.source == outer)
    }

    @Test("the cell count is even and covers the length", arguments: [
        (1.0, 8), (8.0, 8), (9.0, 8), (48.0, 8), (50.0, 8), (854.0, 8), (100.0, 10),
    ])
    func cellsAreEven(length: Double, pitch: Int) {
        let cells = DerivedSprite.cells(covering: length, pitch: pitch)
        #expect(cells % 2 == 0)
        #expect(Double(cells * pitch) >= length)
        // Not one pair of cells more than needed.
        #expect(Double((cells - 2) * pitch) < length)
    }

    // ─── Registration ────────────────────────────────────────────────────────

    @Test("the filter is in the library, under Stylise")
    func registered() throws {
        #expect(FilterLibrary.standard.filter(for: LEDFilter.descriptor.type) != nil)
        #expect(LEDFilter.descriptor.category == .stylise)
    }

    // ─── Building a clip ─────────────────────────────────────────────────────

    /// Text with the filter on it, the case this exists for.
    private func led(
        text: String = "LED",
        set values: [String: EffectValue] = [:],
    ) -> (document: EffectDocument, track: EffectNode.ID) {
        var document = EffectDocument()
        var node = document.add(TextEffect.descriptor, at: 0, duration: 2000)
        node.values[TextEffect.Param.text] = .text(text)
        document[node.id] = node

        let filter = document.addFilter(LEDFilter.descriptor, to: node.id)!
        for (id, value) in values {
            document.setFilterValue(value, for: id, on: filter.id, in: node.id)
        }
        return (document, node.id)
    }

    private func onGrid(_ value: Double, origin: Double, pitch: Double) -> Bool {
        let steps = (value - origin) / pitch
        return abs(steps - steps.rounded()) < 1e-6
    }

    @Test("every glyph draws its dot-matrix image")
    func glyphsAreReplaced() throws {
        let sprites = evaluator.evaluate(led().document)
        #expect(sprites.count == 3)

        for sprite in sprites {
            let parsed = try #require(DerivedSprite.parse(sprite.filePath))
            guard case .dotMatrix = parsed.kind else {
                Issue.record("not a dot matrix: \(sprite.filePath)")
                continue
            }
            #expect(TextSprite.isText(parsed.source))
        }
    }

    /// The whole point. Each glyph is its own texture and the layout works in
    /// font advances that are nowhere near multiples of the pitch, so unless
    /// the filter moves them onto one lattice the dots of neighbouring letters
    /// sit a fraction of a step apart — and that reads as fake at a glance.
    @Test("every glyph sits on the stage-anchored lattice", arguments: [6.0, 8.0, 10.0, 13.0])
    func positionsAreOnTheLattice(pitch: Double) {
        let sprites = evaluator.evaluate(led(set: [
            LEDFilter.Param.pitch: .number(pitch),
        ]).document)

        for sprite in sprites {
            #expect(
                onGrid(sprite.defaultX, origin: DotGrid.originX, pitch: pitch),
                "x \(sprite.defaultX) is off the \(pitch)px lattice",
            )
            #expect(
                onGrid(sprite.defaultY, origin: DotGrid.originY, pitch: pitch),
                "y \(sprite.defaultY) is off the \(pitch)px lattice",
            )
        }
    }

    /// A typed value can be fractional. The texture's pitch is the rounded one
    /// the path carries, so the lattice has to use that same integer — a snap
    /// to 8 for a texture drawn at 9 lines nothing up.
    @Test("the lattice uses the pitch the path carries")
    func latticeMatchesThePath() throws {
        let sprites = evaluator.evaluate(led(set: [
            LEDFilter.Param.pitch: .number(8.6),
        ]).document)

        for sprite in sprites {
            let parsed = try #require(DerivedSprite.parse(sprite.filePath))
            guard case let .dotMatrix(pitch, _, _, _) = parsed.kind else {
                Issue.record("not a dot matrix")
                continue
            }
            #expect(pitch == 9)
            #expect(onGrid(sprite.defaultX, origin: DotGrid.originX, pitch: Double(pitch)))
            #expect(onGrid(sprite.defaultY, origin: DotGrid.originY, pitch: Double(pitch)))
        }
    }

    /// Without the filter the layout is off-lattice, so the test above cannot
    /// pass by accident.
    @Test("the unfiltered layout is not on the lattice")
    func layoutIsOffLatticeToBeginWith() {
        var document = EffectDocument()
        var node = document.add(TextEffect.descriptor, at: 0, duration: 2000)
        node.values[TextEffect.Param.text] = .text("LED")
        document[node.id] = node

        let sprites = evaluator.evaluate(document)
        #expect(sprites.contains { !onGrid($0.defaultX, origin: DotGrid.originX, pitch: 8) })
    }

    // ─── Movement ────────────────────────────────────────────────────────────

    /// A sprite that travels from x=100 to x=300 over two seconds.
    private func travelling(
        step: Bool = true,
        pitch: Double = 8,
        from: Double = 100,
        to: Double = 300,
    ) -> [StoryboardSprite] {
        var document = EffectDocument()
        let node = document.add(ShapeEffect.descriptor, at: 0, duration: 2000)
        document.setKeyframe(from, for: .x, at: 0, on: node.id)
        document.setKeyframe(to, for: .x, at: 2000, on: node.id)
        let filter = document.addFilter(LEDFilter.descriptor, to: node.id)!
        document.setFilterValue(.number(pitch), for: LEDFilter.Param.pitch, on: filter.id, in: node.id)
        document.setFilterValue(.toggle(step), for: LEDFilter.Param.stepMotion, on: filter.id, in: node.id)
        return evaluator.evaluate(document)
    }

    private func moves(_ sprite: StoryboardSprite) -> [Command] {
        sprite.commands.filter { $0.kind == .move || $0.kind == .moveX || $0.kind == .moveY }
    }

    private func xs(_ command: Command) -> [Double] {
        switch command.payload {
        case let .move(sx, _, ex, _): [sx, ex]
        case let .moveX(s, e): [s, e]
        default: []
        }
    }

    @Test("every movement endpoint lands on the lattice")
    func movementLandsOnLattice() throws {
        for step in [true, false] {
            let sprite = try #require(travelling(step: step).first)
            let commands = moves(sprite)
            #expect(!commands.isEmpty)

            for command in commands {
                for x in xs(command) {
                    #expect(onGrid(x, origin: DotGrid.originX, pitch: 8), "x \(x), step \(step)")
                }
            }
        }
    }

    /// Stepped movement is what a sign does — it jumps a dot at a time — and
    /// what keeps the dots on the lattice *between* the endpoints too.
    @Test("stepped movement advances in whole pitches")
    func steppedMovement() throws {
        let sprite = try #require(travelling(step: true).first)
        let commands = moves(sprite).sorted { $0.startTime < $1.startTime }
        #expect(commands.count > 3, "expected a staircase, got \(commands.count) commands")

        let positions = commands.compactMap { xs($0).last }
        for (a, b) in zip(positions, positions.dropFirst()) {
            #expect(b >= a, "moved backwards")
            #expect(onGrid(b - a, origin: 0, pitch: 8), "a step of \(b - a) is not whole pitches")
        }
        // Each is an instant, so between two of them the sprite is held on
        // the lattice rather than sliding across it.
        #expect(commands.allSatisfy { $0.startTime == $0.endTime })
    }

    @Test("without stepping the motion is one command with snapped ends")
    func smoothMovement() throws {
        let sprite = try #require(travelling(step: false).first)
        #expect(moves(sprite).count == 1)
    }

    /// Every step is a line in the file, per glyph. A long move is coarser
    /// rather than longer.
    @Test("a long move is capped, and stays on the lattice")
    func stepsAreCapped() throws {
        let sprite = try #require(travelling(from: -100, to: 700).first)
        let commands = moves(sprite)

        #expect(commands.count <= LEDFilter.maximumSteps + 1)
        #expect(commands.count > 3)
        for command in commands {
            for x in xs(command) {
                #expect(onGrid(x, origin: DotGrid.originX, pitch: 8))
            }
        }
        #expect(abs((xs(commands.last!).last ?? 0) - 700) <= 4)
    }

    /// A still sprite has no movement to step: nothing is written.
    @Test("a sprite that does not move gains no movement commands")
    func stillSpriteStaysStill() {
        let sprites = evaluator.evaluate(led().document)
        for sprite in sprites {
            #expect(moves(sprite).isEmpty)
        }
    }

    // ─── Cost ────────────────────────────────────────────────────────────────

    @Test("without a panel one sprite goes in, one comes out")
    func noPanelIsTimesOne() throws {
        var plain = EffectDocument()
        var node = plain.add(TextEffect.descriptor, at: 0, duration: 2000)
        node.values[TextEffect.Param.text] = .text("LED")
        plain[node.id] = node

        let (document, _) = led()
        #expect(evaluator.evaluate(document).count == evaluator.evaluate(plain).count)

        let context = FilterContext(
            descriptor: LEDFilter.descriptor,
            node: FilterNode(id: "led", type: "led", values: LEDFilter.descriptor.defaultValues),
        )
        #expect(LEDFilter().estimatedMultiplier(in: context) == 1)
    }

    @Test("a panel adds exactly one sprite, drawn behind")
    func panelAddsOne() throws {
        let without = evaluator.evaluate(led().document)
        let with = evaluator.evaluate(led(set: [LEDFilter.Param.panel: .choice(LEDFilter.Panel.stage.rawValue)]).document)

        #expect(with.count == without.count + 1)

        let panel = try #require(with.first)
        let parsed = try #require(DerivedSprite.parse(panel.filePath))
        guard case .dotPanel = parsed.kind else {
            Issue.record("the first sprite is not the panel: \(panel.filePath)")
            return
        }
        // Behind: nothing else is a panel, and it comes first in draw order.
        #expect(with.dropFirst().allSatisfy { !$0.filePath.contains("panel") })
    }

    @Test("the panel lives as long as the sign")
    func panelSpansTheClip() throws {
        let sprites = evaluator.evaluate(led(set: [LEDFilter.Param.panel: .choice(LEDFilter.Panel.stage.rawValue)]).document)
        let panel = try #require(sprites.first)
        let rest = sprites.dropFirst()

        let birth = rest.flatMap(\.commands).map(\.startTime).min()!
        let death = rest.flatMap(\.commands).map(\.endTime).max()!

        #expect(panel.commands.map(\.startTime).min()! <= birth)
        #expect(panel.commands.map(\.endTime).max()! >= death)
        #expect(panel.commands.contains { $0.kind == .fade })
        #expect(panel.commands.contains { $0.kind == .color })
        // Not a zero-length sprite: it would never be drawn.
        #expect(panel.commands.map(\.endTime).max()! > panel.commands.map(\.startTime).min()!)
    }

    @Test("a stage panel starts at the stage's corner, on the lattice")
    func stagePanel() throws {
        let sprites = evaluator.evaluate(led(set: [
            LEDFilter.Param.panel: .choice(LEDFilter.Panel.stage.rawValue),
        ]).document)
        let panel = try #require(sprites.first)

        #expect(panel.origin == .topLeft)
        #expect(panel.defaultX == DotGrid.originX)
        #expect(panel.defaultY == DotGrid.originY)

        let parsed = try #require(DerivedSprite.parse(panel.filePath))
        guard case let .dotPanel(columns, rows, pitch, _, _) = parsed.kind else {
            Issue.record("not a panel")
            return
        }
        #expect(Double(columns * pitch) >= StageSnap.Stage.width)
        #expect(Double(rows * pitch) >= StageSnap.Stage.height)
    }

    /// A panel around the sign, not around the stage: the sign's own extent
    /// plus a margin, snapped outwards onto the lattice.
    @Test("a clip panel hugs the sign")
    func clipPanel() throws {
        let sprites = evaluator.evaluate(led(set: [
            LEDFilter.Param.panel: .choice(LEDFilter.Panel.clip.rawValue),
            LEDFilter.Param.panelMargin: .number(20),
        ]).document)
        let panel = try #require(sprites.first)
        let glyphs = Array(sprites.dropFirst())

        #expect(onGrid(panel.defaultX, origin: DotGrid.originX, pitch: 8))
        #expect(onGrid(panel.defaultY, origin: DotGrid.originY, pitch: 8))

        let parsed = try #require(DerivedSprite.parse(panel.filePath))
        guard case let .dotPanel(columns, rows, pitch, _, _) = parsed.kind else {
            Issue.record("not a panel")
            return
        }
        let right = panel.defaultX + Double(columns * pitch)
        let bottom = panel.defaultY + Double(rows * pitch)

        #expect(panel.defaultX <= glyphs.map(\.defaultX).min()! - 20)
        #expect(right >= glyphs.map(\.defaultX).max()! + 20)
        #expect(panel.defaultY <= glyphs.map(\.defaultY).min()! - 20)
        #expect(bottom >= glyphs.map(\.defaultY).max()! + 20)
        // Much smaller than the stage.
        #expect(Double(columns * pitch) < StageSnap.Stage.width / 2)
    }

    // ─── The library ─────────────────────────────────────────────────────────

    /// An LED sign is text, dots and a glow on one track — the preset that
    /// shows it.
    @Test("the LED Sign preset brings the filters that make a sign")
    func ledSignPreset() throws {
        let preset = try #require(TextEffect.presets.first { $0.id == "led-sign" })
        #expect(preset.effectType == TextEffect.descriptor.type)

        let types = preset.filters.map(\.type)
        #expect(types.contains(LEDFilter.descriptor.type))
        #expect(types.contains(GlowFilter.descriptor.type))
        // Tint, then dots, then glow. Tint after the dots would paint the
        // panel's unlit dots too; glow before them would be turned into dots.
        #expect(types.firstIndex(of: TintFilter.descriptor.type)!
            < types.firstIndex(of: LEDFilter.descriptor.type)!)
        // The glow blurs the dot image, not the reverse.
        #expect(types.firstIndex(of: LEDFilter.descriptor.type)!
            < types.firstIndex(of: GlowFilter.descriptor.type)!)

        let nodes = preset.filterNodes(using: .standard) { "f\($0)" }
        #expect(nodes.count == preset.filters.count)
    }

    @Test("a sign built from the preset evaluates to dots")
    func ledSignEvaluates() throws {
        let preset = try #require(TextEffect.presets.first { $0.id == "led-sign" })

        var document = EffectDocument()
        var node = document.add(TextEffect.descriptor, at: 0, duration: preset.duration)
        for (key, value) in preset.values { node.values[key] = value }
        node.filters = preset.filterNodes(using: .standard) { "\(node.id)-f\($0)" }
        document[node.id] = node

        let sprites = evaluator.evaluate(document)
        #expect(!sprites.isEmpty)
        // The glow blurs the dot image, so the path nests: blur over dots.
        #expect(sprites.contains { $0.filePath.contains("/dots") })
    }
}
