import Foundation
import Testing

@testable import StoryboardCore

/// `Follow`: every sprite travels the curve over its own life.
///
/// `Emit Along` only moves where a sprite is born, so a particle that flies —
/// Chevron March runs 800px at 420px/s — leaves the path behind the instant it
/// is out, and the curve is lost. Measured on the sprites that come out, never
/// on the filter's own numbers.
@Suite("Motion path: follow")
struct PathFollowTests {
    private let evaluator = EffectEvaluator()

    /// Six sprites that would fly right at 420px/s if nothing stopped them —
    /// so any sprite still on a vertical path is the filter's doing.
    private func document(
        path: MotionPath,
        mode: PathFilter.Mode = .follow,
        faceAlong: Bool = false,
        laps: Double = 1,
        width: Double = 0,
    ) -> EffectDocument {
        var document = EffectDocument()
        let node = document.add(EmitterEffect.descriptor, at: 0, duration: 3000)
        let set = { (value: EffectValue, key: String) in
            document.setValue(value, for: key, on: node.id)
        }
        set(.integer(6), EmitterEffect.Param.count)
        set(.choice(EmitterEffect.Emission.continuous.rawValue), EmitterEffect.Param.emission)
        set(.number(420), EmitterEffect.Param.velocity)
        set(.number(0), EmitterEffect.Param.direction)
        set(.number(0), EmitterEffect.Param.spread)
        set(.number(0), EmitterEffect.Param.velocityRandom)
        set(.number(width), EmitterEffect.Param.width)
        set(.number(0), EmitterEffect.Param.height)
        set(.number(1000), EmitterEffect.Param.life)
        set(.number(0), EmitterEffect.Param.lifeRandom)
        set(.number(0), EmitterEffect.Param.gravity)
        set(.number(0), EmitterEffect.Param.drag)

        let filter = document.addFilter(PathFilter.descriptor, to: node.id)!
        let setFilter = { (value: EffectValue, key: String) in
            document.setFilterValue(value, for: key, on: filter.id, in: node.id)
        }
        setFilter(.path(path), PathFilter.Param.path)
        setFilter(.choice(mode.rawValue), PathFilter.Param.mode)
        setFilter(.toggle(faceAlong), PathFilter.Param.alignToPath)
        setFilter(.number(laps), PathFilter.Param.loops)
        return document
    }

    private let horizontal = MotionPath(points: [.init(x: 100, y: 240), .init(x: 500, y: 240)])
    private let vertical = MotionPath(points: [.init(x: 320, y: 60), .init(x: 320, y: 420)])
    /// An arch, so a straight chord between samples would show.
    private let arch = MotionPath(points: [
        .init(x: 100, y: 400, outX: 0, outY: -300),
        .init(x: 540, y: 400, inX: 0, inY: -300),
    ])

    private func life(of sprite: StoryboardSprite) -> (birth: Double, death: Double) {
        let birth = sprite.commands.map(\.startTime).min() ?? 0
        let death = sprite.commands.map(\.endTime).max() ?? birth
        return (birth, death)
    }

    /// Where a sprite is, `fraction` of the way through its own life.
    private func state(_ sprite: StoryboardSprite, at fraction: Double) -> SpriteRenderState {
        let (birth, death) = life(of: sprite)
        let prepared = StoryboardResolver.prepare([sprite])[0]
        return StoryboardResolver.state(of: prepared, at: birth + (death - birth) * fraction)
    }

    private func close(_ a: Double, _ b: Double, within tolerance: Double = 1.5) -> Bool {
        abs(a - b) <= tolerance
    }

    @Test("every sprite starts at the path's first point and ends at its last")
    func travelsEndToEnd() throws {
        let sprites = evaluator.evaluate(document(path: vertical))
        try #require(sprites.count == 6)

        for sprite in sprites {
            let start = state(sprite, at: 0)
            let end = state(sprite, at: 1)
            #expect(close(start.x, 320) && close(start.y, 60), "born at \(start.x), \(start.y)")
            #expect(close(end.x, 320) && close(end.y, 420), "died at \(end.x), \(end.y)")
        }
    }

    /// The emitter asked for 420px/s to the right. On a vertical path, any x
    /// that moves is the sprite's own velocity leaking through.
    @Test("a sprite's own velocity does not pull it off the path")
    func ownMotionIsReplaced() {
        for sprite in evaluator.evaluate(document(path: vertical)) {
            for fraction in stride(from: 0.0, through: 1.0, by: 0.125) {
                let at = state(sprite, at: fraction)
                #expect(close(at.x, 320), "x drifted to \(at.x) at \(fraction)")
            }
        }
    }

    @Test("steady pacing is halfway along the path halfway through a life")
    func steadyIsLinearInLength() {
        for sprite in evaluator.evaluate(document(path: horizontal)) {
            let middle = state(sprite, at: 0.5)
            #expect(close(middle.x, 300), "halfway through its life at x \(middle.x)")
        }
    }

    /// Sprites born at different times are at different places at the same
    /// moment: that is what makes a march rather than one stack.
    @Test("sprites born later are further behind on the path")
    func staggeredBirthsMarch() {
        let sprites = evaluator.evaluate(document(path: horizontal))
            .sorted { life(of: $0).birth < life(of: $1).birth }
        let moment = 1500.0
        let xs = sprites.compactMap { sprite -> Double? in
            let (birth, death) = life(of: sprite)
            guard birth <= moment, moment <= death else { return nil }
            return StoryboardResolver.state(of: StoryboardResolver.prepare([sprite])[0], at: moment).x
        }
        #expect(xs.count >= 2, "need two sprites alive at once to compare")
        #expect(zip(xs, xs.dropFirst()).allSatisfy { $0 > $1 }, "not in march order: \(xs)")
    }

    /// Straight moves between samples cut the corner of a curve; enough of
    /// them keep the error below what reads on screen.
    @Test("a curve is followed, not cut across")
    func curveIsSampledFinely() throws {
        let sprite = try #require(evaluator.evaluate(document(path: arch)).first)
        for fraction in stride(from: 0.05, through: 0.95, by: 0.05) {
            let at = state(sprite, at: fraction)
            let want = try #require(arch.position(at: fraction))
            let error = hypot(at.x - want.x, at.y - want.y)
            #expect(error < 2, "\(error)px off the curve at \(fraction)")
        }
    }

    @Test("two laps are at the end of the path halfway through a life")
    func lapsRepeatTheCourse() throws {
        let sprite = try #require(evaluator.evaluate(document(path: horizontal, laps: 2)).first)
        #expect(close(state(sprite, at: 0.25).x, 300), "first lap midway")
        #expect(close(state(sprite, at: 0.75).x, 300), "second lap midway")
        // Never swept back across the path between laps.
        let justAfter = state(sprite, at: 0.51).x
        #expect(justAfter < 150, "the second lap did not restart at the beginning: \(justAfter)")
    }

    /// A sprite's "up" faces its heading when its rotation is heading + 90°:
    /// up is (0, −1), and the shader turns it to (sin r, −cos r). A chevron
    /// is drawn pointing up, so this is what makes it lead.
    @Test(
        "face along path turns a sprite's up toward where it is heading",
        arguments: [PathFilter.Mode.follow, .emitAlong],
    )
    func facingLeads(_ mode: PathFilter.Mode) {
        for (path, heading) in [(horizontal, 0.0), (vertical, Double.pi / 2)] {
            for sprite in evaluator.evaluate(document(path: path, mode: mode, faceAlong: true)) {
                let r = state(sprite, at: 0.5).rotation
                let up = (x: sin(r), y: -cos(r))
                #expect(
                    close(up.x, cos(heading), within: 0.02) && close(up.y, sin(heading), within: 0.02),
                    "\(mode) faces (\(up.x), \(up.y)) heading \(heading)",
                )
            }
        }
    }

    /// osu! does not add two `_M` commands that overlap in time — they fight,
    /// and the editor's resolver hides it by letting the later one win. So
    /// the sprite's own flight has to be gone from the file, not outvoted.
    @Test("the file holds no position commands that overlap")
    func noFightingMoves() {
        for sprite in evaluator.evaluate(document(path: arch)) {
            let moves = sprite.commands
                .filter { if case .move = $0.payload { true } else if case .moveX = $0.payload { true } else if case .moveY = $0.payload { true } else { false } }
                .sorted { $0.startTime < $1.startTime }
            for (a, b) in zip(moves, moves.dropFirst()) {
                #expect(b.startTime >= a.endTime - 1e-6, "moves overlap: \(a.startTime)–\(a.endTime) and \(b.startTime)–\(b.endTime)")
            }
        }
    }

    /// With 1.5 laps the turn lands inside a sample step rather than on its
    /// edge — the case where interpolating straight across would drag the
    /// sprite back over the whole path instead of jumping to the start.
    @Test("a lap that turns over mid-step jumps back to the start")
    func lapTurnsInsideAStep() throws {
        let sprite = try #require(evaluator.evaluate(document(path: horizontal, laps: 1.5)).first)
        // The course reaches the end at two thirds of the life.
        let before = state(sprite, at: 0.66).x
        let after = state(sprite, at: 0.67).x
        #expect(before > 480, "not at the end before the turn: \(before)")
        #expect(after < 120, "not back at the start after the turn: \(after)")
    }

    /// An emitter with an area carries its shape along the curve rather than
    /// collapsing onto a single line.
    @Test("an emitter's area rides along the path")
    func areaIsKept() {
        let xs = evaluator.evaluate(document(path: vertical, width: 200)).map { state($0, at: 0.5).x }
        let spread = (xs.max() ?? 0) - (xs.min() ?? 0)
        #expect(spread > 80, "the area collapsed onto the path: \(spread)px across")
    }

    /// Heading left, the angle sits at ±π; a path that wobbles there crosses
    /// it, and without unwrapping the sprite spins a full turn at the seam.
    @Test("facing turns the short way across ±π")
    func facingDoesNotSpin() throws {
        let wobble = MotionPath(points: [
            .init(x: 540, y: 240, outX: -150, outY: 80),
            .init(x: 100, y: 240, inX: 150, inY: 80),
        ])
        let sprite = try #require(evaluator.evaluate(document(path: wobble, faceAlong: true)).first)
        var previous = state(sprite, at: 0).rotation
        for fraction in stride(from: 0.02, through: 1.0, by: 0.02) {
            let r = state(sprite, at: fraction).rotation
            #expect(abs(r - previous) < 0.5, "rotation jumped \(r - previous) at \(fraction)")
            previous = r
        }
    }

    /// Emit Along stays the default: filters land in finished projects, and a
    /// default that changed the output would rewrite approved work.
    @Test("emit along is the default")
    func defaultIsEmitAlong() {
        let parameter = PathFilter.descriptor.parameters.first { $0.id == PathFilter.Param.mode }
        #expect(parameter?.defaultValue == .choice(PathFilter.Mode.emitAlong.rawValue))
    }
}
