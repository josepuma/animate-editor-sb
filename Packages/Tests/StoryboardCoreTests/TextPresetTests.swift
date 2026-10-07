import Foundation
import Testing

@testable import StoryboardCore

@Suite("Text presets")
struct TextPresetTests {
    /// Placed as the editor places it, layers and filters included: a
    /// compound judged on its title alone is judged on half of it.
    private func sprites(_ preset: EffectPreset, text: String? = nil) -> [StoryboardSprite] {
        PlacedPreset.sprites(preset, text: text)
    }

    /// All of them are the one effect with different numbers — no special cases
    /// in the evaluator, which is what keeps the library honest.
    @Test("every preset belongs to the text effect", arguments: TextEffect.presets)
    func presetsAreTextEffects(preset: EffectPreset) {
        #expect(preset.effectType == TextEffect.descriptor.type)
    }

    @Test("every preset draws something", arguments: TextEffect.presets)
    func presetsDraw(preset: EffectPreset) {
        #expect(!sprites(preset).isEmpty)
    }

    /// A preset that is invisible halfway through its own block reads as
    /// broken, whatever its numbers say. The emitter library had exactly this
    /// bug, found by exactly this test.
    @Test("every preset is visible partway through", arguments: TextEffect.presets)
    func presetsAreVisibleMidway(preset: EffectPreset) {
        var states: [SpriteRenderState] = []
        StoryboardResolver.resolve(
            StoryboardResolver.prepare(sprites(preset)),
            at: preset.duration * 0.5,
            into: &states,
        )

        #expect(states.contains { $0.visible && $0.opacity > 0.01 })
    }

    @Test("presets have distinct names and ids")
    func namesAreUnique() {
        #expect(Set(TextEffect.presets.map(\.id)).count == TextEffect.presets.count)
        #expect(Set(TextEffect.presets.map(\.name)).count == TextEffect.presets.count)
    }

    /// Twelve presets that all animate the same way would be one preset listed
    /// twelve times. The signature names every axis a preset can turn, so two
    /// presets apart only on a new axis still count as two.
    @Test("presets differ from one another")
    func presetsDiffer() {
        let axes = [
            P.stagger, P.easing, P.riseFrom, P.driftFrom, P.scaleFrom, P.staggerFrom,
            P.unit, P.staggerMode, P.staggerSpread, P.waveAmount,
            P.scatterX, P.scatterY, P.scatterRotation, P.scatterScale,
            P.stretchFromX, P.stretchFromY, P.pivot, P.spinFrom, P.exit,
            P.holdMotion, P.colourMode, P.exitStagger, P.exitOrder,
        ]
        // What a preset brings besides its numbers is part of what it is: two
        // with the same title movement and different layers are two presets.
        let signatures = TextEffect.presets.map { preset in
            "\(axes.map { preset.values[$0] })"
                + " \(preset.values[TextGlyphParticles.Param.mode].map(String.init(describing:)) ?? "")"
                + " \(preset.filters.map { "\($0.type) \($0.values.sorted { $0.key < $1.key }) \($0.animations.keys.sorted())" })"
                + " \(preset.layers.map { "\($0.effectType) \($0.values.sorted { $0.key < $1.key }) \($0.delay)" })"
        }

        #expect(Set(signatures).count == signatures.count)
    }

    /// Different numbers are not enough: what the presets draw has to differ.
    /// Compared on commands, never on sprite ids, which carry the node's own id.
    @Test("presets draw differently from one another")
    func presetsDrawDifferently() {
        let drawn = TextEffect.presets.map { preset in
            sprites(preset).map { "\($0.origin) \(String(reflecting: $0.commands))" }
        }
        #expect(Set(drawn).count == drawn.count)
    }

    // ─── The Text Animator presets ───────────────────────────────────────────

    private typealias P = TextEffect.Param

    private static let animatorIDs = [
        "word-pop", "line-slide", "assemble", "slam", "stretch-in",
        "spiral-in", "split-reveal", "cascade-wave", "title-drop", "unfold-up",
    ]

    /// S8.1: all ten, beside the fifteen that were already there.
    @Test("the animator presets are in the library")
    func animatorPresetsExist() {
        let ids = TextEffect.presets.map(\.id)
        #expect(Self.animatorIDs.allSatisfy(ids.contains))
        #expect(TextEffect.presets.count == 50)
    }

    /// S8.1: unique across every preset the editor lists, not only the text
    /// ones — the panel groups them all by id.
    @Test("preset ids are unique across the whole catalogue")
    func idsUniqueInCatalogue() {
        let all = TextEffect.presets + ShapeEffect.presets + AudioBarsEffect.presets
            + AudioWavesEffect.presets + EmitterEffect.presets + EmitterEffect.compoundPresets
            + TileWipeEffect.presets
        #expect(Set(all.map(\.id)).count == all.count)
    }

    /// S8.3: visible at half its block, and visible on the stage rather than
    /// off it.
    @Test("every preset is on stage partway through", arguments: TextEffect.presets)
    func presetsOnStageMidway(preset: EffectPreset) {
        var states: [SpriteRenderState] = []
        StoryboardResolver.resolve(
            StoryboardResolver.prepare(sprites(preset, text: "the quick brown\nfox jumps")),
            at: preset.duration * 0.5,
            into: &states,
        )
        #expect(states.contains {
            $0.visible && $0.opacity > 0.01 && (-107...747).contains($0.x) && (0...480).contains($0.y)
        })
    }

    /// S8.6: the pivot is the box's bottom edge, and the name says "up".
    @Test("unfold-up unfolds from the bottom edge")
    func unfoldUp() throws {
        let preset = try #require(TextEffect.presets.first { $0.id == "unfold-up" })
        let drawn = sprites(preset)
        #expect(drawn.allSatisfy { $0.origin == .bottomCentre })
        for sprite in drawn {
            let entrance = try #require(sprite.commands.first {
                if case .vectorScale = $0.payload { true } else { false }
            })
            guard case let .vectorScale(startX, startY, _, _) = entrance.payload else { return }
            #expect(startY < 0.1 && startX == 1)
        }
        let text = TextEffect.presets.map { "\($0.id) \($0.name) \($0.summary)" }.joined()
        #expect(!text.contains("unfold-baseline"))
        // CLAUDE.md is ignored by git, so a clean checkout (CI) has none to read.
        if FileManager.default.fileExists(atPath: Self.claudeMD.path) {
            let docs = try String(contentsOf: Self.claudeMD, encoding: .utf8)
            #expect(!docs.contains("unfold-baseline"))
        }
    }

    private static let claudeMD = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // StoryboardCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // Packages
        .deletingLastPathComponent()   // the repository root
        .appendingPathComponent("CLAUDE.md")

    /// S8.7: a typical line stays a sprite per drawn glyph and a bounded run
    /// of commands each. Ten is what the effect can write at most today —
    /// two fades, entrance move, scale and turn, travel, exit move and tumble,
    /// colour and blend — so a preset past it is a preset doing something the
    /// effect never did.
    @Test("the animator presets stay inside the effect's cost", arguments: animatorIDs)
    func costBounded(id: String) throws {
        let preset = try #require(TextEffect.presets.first { $0.id == id })
        let line = "the quick brown fox jumps"
        let drawn = sprites(preset, text: line)
        #expect(drawn.count == line.filter { !$0.isWhitespace }.count)
        #expect(drawn.allSatisfy { $0.commands.count <= 10 })
    }

    /// Each preset's own move, read from what it draws: take its defining axis
    /// away and its check fails, whether or not it still differs from the rest.
    @Test("each animator preset does its own move", arguments: animatorIDs)
    func character(id: String) throws {
        let preset = try #require(TextEffect.presets.first { $0.id == id })
        let drawn = sprites(preset, text: "ab cd\nef gh")
        let arrivals = drawn.map { $0.commands.first?.startTime ?? -1 }
        func has(_ sprite: StoryboardSprite, _ test: (Command.Payload) -> Bool) -> Bool {
            sprite.commands.contains { test($0.payload) }
        }
        let vectors = drawn.compactMap { sprite -> (Double, Double)? in
            for command in sprite.commands {
                if case let .vectorScale(x, y, _, _) = command.payload { return (x, y) }
            }
            return nil
        }
        let moveStarts = drawn.compactMap { sprite -> Double? in
            for command in sprite.commands {
                if case let .move(x, _, _, _) = command.payload { return x - sprite.defaultX }
            }
            return nil
        }
        let words = [arrivals[0] == arrivals[1], arrivals[2] == arrivals[3], arrivals[2] > arrivals[0]]
        let lines = Set(arrivals[0...3]).count == 1 && Set(arrivals[4...7]).count == 1

        switch id {
        case "word-pop":
            #expect(words.allSatisfy { $0 } && !lines)
            #expect(drawn.allSatisfy { has($0) { if case .scale(0.3, 1) = $0 { true } else { false } } })
        case "line-slide":
            #expect(lines && arrivals[4] > arrivals[0])
            #expect(moveStarts.count == drawn.count && moveStarts.allSatisfy { $0 == -220 })
        case "assemble":
            #expect(Set(moveStarts).count == drawn.count, "every glyph from its own place")
            #expect(Set(arrivals).count > 1)
        case "slam":
            #expect(words.allSatisfy { $0 })
            #expect(vectors.count == drawn.count && drawn.allSatisfy { !has($0) { if case .scale = $0 { true } else { false } } })
        case "stretch-in":
            #expect(vectors.count == drawn.count && vectors.allSatisfy { $0 == (3, 0.2) })
        case "spiral-in":
            #expect(arrivals.first == arrivals.last && arrivals[0] < arrivals[2], "from both ends")
            #expect(drawn.allSatisfy { has($0) { if case .rotate = $0 { true } else { false } } })
        case "split-reveal":
            #expect(arrivals.first == arrivals.last)
            #expect(vectors.count == drawn.count && vectors.allSatisfy { $0 == (0.05, 1) })
        case "cascade-wave":
            #expect(arrivals != arrivals.sorted(), "a wave is not a sweep")
        case "title-drop":
            #expect(lines)
            #expect(drawn.allSatisfy { $0.origin == .bottomCentre })
        case "unfold-up":
            #expect(drawn.allSatisfy { $0.origin == .bottomCentre })
            #expect(vectors.allSatisfy { $0 == (1, 0.05) })
        default:
            Issue.record("no check for \(id)")
        }
    }

    // ─── The motion presets ──────────────────────────────────────────────────

    static let motionIDs = [
        "karaoke-sweep", "soft-float", "echo-lines", "breathing", "shake-hold",
        "glitch-in", "scan-line", "zigzag-wave", "gradient-title", "mirror-out",
    ]
    /// The ones that write a hold, and so may spend its steps.
    private static let holdIDs: Set<String> = ["soft-float", "breathing", "shake-hold", "glitch-in", "zigzag-wave"]

    @Test("the motion presets are in the library, after the animator ones")
    func motionPresetsExist() {
        let ids = TextEffect.presets.map(\.id)
        #expect(Array(ids.dropLast(TextEffect.fxPresets.count).suffix(10)) == Self.motionIDs)
    }

    /// A hold is at most 48 steps on top of the ten the effect could already
    /// write, so a hold preset is bounded at 64 commands a glyph and every
    /// other preset stays at ten. Over a typical line: a sprite per glyph.
    @Test("the motion presets stay inside their declared cost", arguments: motionIDs)
    func motionCostBounded(id: String) throws {
        let preset = try #require(TextEffect.presets.first { $0.id == id })
        let line = "the quick brown fox jumps"
        let drawn = sprites(preset, text: line)
        let bound = Self.holdIDs.contains(id) ? 64 : 10
        #expect(drawn.count == line.filter { !$0.isWhitespace }.count)
        #expect(drawn.allSatisfy { $0.commands.count <= bound }, "\(id): \(drawn.map(\.commands.count).max() ?? 0)")
        #expect(drawn.allSatisfy { TextOverlapGuard.violations($0).isEmpty })
    }

    /// Each preset's own move, read from what it draws.
    @Test("each motion preset does its own move", arguments: motionIDs)
    func motionCharacter(id: String) throws {
        let preset = try #require(TextEffect.presets.first { $0.id == id })
        let drawn = sprites(preset, text: "ab cd\nef gh")
        try #require(drawn.count == 8)
        let landed = drawn.map { sprite in sprite.commands.first { $0.kind == .fade }.map(\.endTime) ?? 0 }
        func kinds(_ sprite: StoryboardSprite, _ kind: CommandKind) -> [Command] {
            sprite.commands.filter { $0.kind == kind }
        }
        func held(_ sprite: StoryboardSprite, _ kind: CommandKind, after: Double) -> [Command] {
            kinds(sprite, kind).filter { $0.startTime >= after && $0.endTime <= preset.duration - 200 }
        }
        func exitStart(_ sprite: StoryboardSprite) -> Double {
            sprite.commands.filter { $0.kind == .fade }.last?.startTime ?? 0
        }
        func offset(_ sprite: StoryboardSprite, at time: Double) throws -> (x: Double, y: Double) {
            let state = try #require(StoryboardResolver.resolve(StoryboardResolver.prepare([sprite]), at: time).first)
            return (state.x - sprite.defaultX, state.y - sprite.defaultY)
        }
        let colourStarts = drawn.map { kinds($0, .color).first?.startTime ?? -1 }

        switch id {
        case "karaoke-sweep":
            #expect(colourStarts[0] == colourStarts[1] && colourStarts[2] == colourStarts[3], "words light as one")
            #expect(colourStarts[0] < colourStarts[2] && colourStarts[2] < colourStarts[4])
            #expect(drawn.allSatisfy { kinds($0, .color).count == 1 })
        case "soft-float":
            #expect(drawn.allSatisfy { held($0, .move, after: 0).count > 2 })
            let middle = preset.duration / 2
            #expect(try abs(offset(drawn[0], at: middle).x) > 0.1 || abs(offset(drawn[0], at: middle + 700).x) > 0.1)
        case "echo-lines":
            #expect(exitStart(drawn[4]) < exitStart(drawn[0]), "the last line in is the first out")
            #expect(Set(drawn[0...3].map(exitStart)).count == 1)
            let exit = try #require(kinds(drawn[0], .move).last)
            guard case let .move(sx, _, ex, _) = exit.payload else { return }
            #expect(ex - sx == -120, "back out the way it came")
        case "breathing":
            #expect(drawn.allSatisfy { held($0, .scale, after: 0).count > 2 })
            #expect(drawn.allSatisfy { kinds($0, .move).isEmpty })
        case "shake-hold":
            let time = preset.duration * 0.6
            let (a, b) = (try offset(drawn[0], at: time), try offset(drawn[1], at: time))
            #expect(abs(a.x - b.x) < 1e-6 && abs(a.y - b.y) < 1e-6, "a word shakes as one")
            #expect(drawn.allSatisfy { held($0, .move, after: 0).count > 10 })
        case "glitch-in":
            let steps = held(drawn[0], .move, after: landed[0])
            let jumps = zip(steps, steps.dropFirst()).filter { a, b in
                guard case let .move(_, _, ax, ay) = a.payload, case let .move(bx, by, _, _) = b.payload else { return false }
                return abs(ax - bx) > 0.5 || abs(ay - by) > 0.5
            }
            #expect(jumps.count > 2, "jumps, not slides")
            #expect(landed != landed.sorted(), "out of order")
        case "scan-line":
            #expect(drawn.allSatisfy { kinds($0, .color).count == 2 }, "lit, then back")
            #expect(Set(colourStarts[0...3]).count == 1 && colourStarts[4] > colourStarts[0])
        case "zigzag-wave":
            let time = landed[0] + 600
            #expect(try abs(offset(drawn[0], at: time).y - offset(drawn[1], at: time).y) > 0.5)
            #expect(drawn.allSatisfy { held($0, .move, after: 0).count > 2 })
        case "gradient-title":
            let ends = drawn.map { sprite -> Double in
                guard case let .color(_, g, _, _, _, _)? = kinds(sprite, .color).first?.payload else { return 255 }
                return g
            }
            #expect(ends[0] == 255 && ends[3] == 120 && ends[4] == 255 && ends[7] == 120, "per line, white to pink")
            #expect(ends[1] > ends[3] && ends[1] < 255)
        case "mirror-out":
            let starts = drawn.map(exitStart)
            #expect(starts == starts.sorted() && Set(starts).count == drawn.count, "first in, first out")
            let exit = try #require(kinds(drawn[0], .move).last)
            guard case let .move(_, sy, _, ey) = exit.payload else { return }
            #expect(ey - sy == 40, "sinks back to where it rose from")
        default:
            Issue.record("no check for \(id)")
        }
    }
}
