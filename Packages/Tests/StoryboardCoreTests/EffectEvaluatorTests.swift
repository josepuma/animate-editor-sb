import Testing

@testable import StoryboardCore

@Suite("EffectEvaluator")
struct EffectEvaluatorTests {
    private func emitter(
        id: String = "fx1",
        startTime: Double = 0,
        duration: Double = 2000,
        seed: UInt64 = 42,
        layer: Layer = .foreground,
        values: [String: EffectValue] = [:],
    ) -> EffectNode {
        var merged: [String: EffectValue] = [
            EmitterEffect.Param.count: .integer(12),
            EmitterEffect.Param.gravity: .number(400),
        ]
        for (key, value) in values { merged[key] = value }

        return EffectNode(
            id: id,
            type: "emitter",
            name: "Emitter",
            layer: layer,
            startTime: startTime,
            duration: duration,
            seed: seed,
            values: merged,
        )
    }

    private let evaluator = EffectEvaluator()

    // ─── Determinism ─────────────────────────────────────────────────────────

    @Test("the same node evaluates to the same sprites every time")
    func deterministic() {
        let node = emitter()

        let first = evaluator.evaluate(node)
        let second = evaluator.evaluate(node)

        #expect(first.count == second.count)
        for (a, b) in zip(first, second) {
            #expect(a.id == b.id)
            #expect(a.defaultX == b.defaultX)
            #expect(a.defaultY == b.defaultY)
            #expect(a.commands.count == b.commands.count)
            for (x, y) in zip(a.commands, b.commands) {
                #expect(x.startTime == y.startTime)
                #expect(x.endTime == y.endTime)
            }
        }
    }

    /// Adjacent seeds are the case that matters: someone nudging a seed field
    /// steps it by one, and a generator whose neighbouring streams correlate
    /// would hand back the same field while appearing to reroll it.
    @Test("a different seed produces a different field")
    func seedChangesOutput() {
        let a = evaluator.evaluate(emitter(seed: 1))
        let b = evaluator.evaluate(emitter(seed: 2))

        #expect(a.count == b.count)
        // A default emitter has no size, so every particle starts at the same
        // point and the seed shows up in the trajectories instead.
        #expect(zip(a, b).contains { first, second in
            zip(first.commands, second.commands).contains { !$0.hasSamePayload(as: $1) }
        })
    }

    /// The property the whole design rests on: dragging a block on the timeline
    /// moves the same particles rather than drawing new ones.
    @Test("moving a node shifts its output without changing it")
    func draggingShiftsRatherThanRegenerates() {
        let atZero = evaluator.evaluate(emitter(startTime: 0))
        let moved = evaluator.evaluate(emitter(startTime: 5000))

        #expect(atZero.count == moved.count)
        #expect(!atZero.isEmpty)

        for (original, shifted) in zip(atZero, moved) {
            // Same art: identical positions and identical command payloads.
            #expect(original.defaultX == shifted.defaultX)
            #expect(original.defaultY == shifted.defaultY)
            #expect(original.commands.count == shifted.commands.count)

            for (a, b) in zip(original.commands, shifted.commands) {
                #expect(b.startTime == a.startTime + 5000)
                #expect(b.endTime == a.endTime + 5000)
                #expect(a.kind == b.kind)
            }
        }
    }

    /// Particles outlive the emitter by design — one born at the last instant
    /// still has its whole life to run, exactly as a layer's particles keep
    /// falling after the emitter stops. What must hold is that nothing starts
    /// before the node does, and that the tail is bounded by one lifetime
    /// rather than running on unchecked.
    @Test("output starts with the node and outlives it by at most one lifetime")
    func outputStaysWithinRange() {
        let life: Double = 1200
        let lifeRandom = 0.2
        let node = emitter(
            startTime: 3000,
            duration: 2000,
            values: [
                EmitterEffect.Param.life: .number(life),
                EmitterEffect.Param.lifeRandom: .number(lifeRandom),
            ],
        )
        let sprites = evaluator.evaluate(node)
        let longestLife = life * (1 + lifeRandom)

        #expect(!sprites.isEmpty)
        for sprite in sprites {
            for command in sprite.commands {
                #expect(command.startTime >= node.startTime)
                #expect(command.endTime >= command.startTime)
                #expect(command.endTime <= node.endTime + longestLife + 1e-9)
            }
        }
    }

    // ─── Node state ──────────────────────────────────────────────────────────

    @Test("a hidden node produces nothing")
    func hiddenNodeIsSkipped() {
        var node = emitter()
        node.isVisible = false

        #expect(evaluator.evaluate(node).isEmpty)
    }

    @Test("an unknown effect type produces nothing rather than failing")
    func unknownTypeIsSkipped() {
        let node = EffectNode(
            id: "fx1",
            type: "does-not-exist",
            name: "Ghost",
            startTime: 0,
            duration: 1000,
        )

        #expect(evaluator.evaluate(node).isEmpty)
    }

    @Test("the node's layer wins over whatever the effect produced")
    func layerComesFromTheNode() {
        let sprites = evaluator.evaluate(emitter(layer: .overlay))

        #expect(!sprites.isEmpty)
        #expect(sprites.allSatisfy { $0.layer == .overlay })
    }

    @Test("two nodes of the same effect produce distinct sprite ids")
    func idsDoNotCollide() {
        let sprites = evaluator.evaluate([emitter(id: "a"), emitter(id: "b")])
        let ids = Set(sprites.map(\.id))

        #expect(ids.count == sprites.count)
    }

    @Test("a loop's start moves but its body stays relative")
    func loopBodiesAreNotShiftedTwice() {
        let body = [Command(easing: .linear, startTime: 0, endTime: 500, payload: .fade(start: 0, end: 1))]
        let sprite = StoryboardSprite(
            id: "s",
            layer: .foreground,
            origin: .centre,
            filePath: "a.png",
            defaultX: 0,
            defaultY: 0,
            loops: [LoopGroup(startTime: 100, loopCount: 3, commands: body)],
        )

        let library = EffectLibrary(effects: [StubEffect(sprites: [sprite])])
        let shifted = EffectEvaluator(library: library).evaluate(
            EffectNode(id: "n", type: "stub", name: "Stub", startTime: 1000, duration: 500),
        )

        let loop = try! #require(shifted.first?.loops.first)
        #expect(loop.startTime == 1100)
        #expect(loop.commands[0].startTime == 0)
        #expect(loop.commands[0].endTime == 500)
    }
}

private extension Command {
    /// Whether two commands carry the same values, ignoring timing.
    ///
    /// `Command.Payload` is deliberately not `Equatable` in the model — nothing
    /// in the engine compares commands — so the comparison the tests need lives
    /// here rather than widening the public type.
    func hasSamePayload(as other: Command) -> Bool {
        switch (payload, other.payload) {
        case let (.fade(a1, a2), .fade(b1, b2)):
            a1 == b1 && a2 == b2
        case let (.move(a1, a2, a3, a4), .move(b1, b2, b3, b4)):
            a1 == b1 && a2 == b2 && a3 == b3 && a4 == b4
        case let (.moveX(a1, a2), .moveX(b1, b2)),
             let (.moveY(a1, a2), .moveY(b1, b2)),
             let (.scale(a1, a2), .scale(b1, b2)),
             let (.rotate(a1, a2), .rotate(b1, b2)):
            a1 == b1 && a2 == b2
        case let (.vectorScale(a1, a2, a3, a4), .vectorScale(b1, b2, b3, b4)):
            a1 == b1 && a2 == b2 && a3 == b3 && a4 == b4
        case let (.color(a1, a2, a3, a4, a5, a6), .color(b1, b2, b3, b4, b5, b6)):
            a1 == b1 && a2 == b2 && a3 == b3 && a4 == b4 && a5 == b5 && a6 == b6
        case let (.parameter(a), .parameter(b)):
            a == b
        default:
            false
        }
    }
}

/// An effect that returns a fixed sprite list, for testing the evaluator's own
/// behaviour without the emitter's maths in the way.
private struct StubEffect: Effect {
    static let descriptor = EffectDescriptor(
        type: "stub",
        name: "Stub",
        category: .generate,
        systemImage: "circle",
        parameters: [],
    )

    let sprites: [StoryboardSprite]

    func evaluate(in context: EffectContext, rng: inout EffectRandom) -> [StoryboardSprite] {
        sprites
    }
}
