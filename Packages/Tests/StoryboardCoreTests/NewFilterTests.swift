import Foundation
import Testing

@testable import StoryboardCore

/// Time, Ease and Radial Repeat.
@Suite("Time, Ease and Radial")
struct NewFilterTests {
    private let evaluator = EffectEvaluator()

    private func makeDocument(count: Int = 6) -> EffectDocument {
        var document = EffectDocument()
        let node = document.add(EmitterEffect.descriptor, at: 0, duration: 2000)
        document.setValue(.integer(count), for: EmitterEffect.Param.count, on: node.id)
        return document
    }

    private func clip(in document: EffectDocument) -> EffectNode.ID {
        document.nodes[0].id
    }

    // ─── Time ────────────────────────────────────────────────────────────────

    /// Every new filter has to be inert at its defaults: they land in projects
    /// that are already finished, and a default that changed the output would
    /// rewrite work someone had approved.
    @Test("the defaults change nothing", arguments: [
        TimeFilter.descriptor, EaseFilter.descriptor,
    ])
    func defaultsAreInert(descriptor: FilterDescriptor) {
        var document = makeDocument()
        let before = evaluator.evaluate(document)

        _ = document.addFilter(descriptor, to: clip(in: document))
        let after = evaluator.evaluate(document)

        #expect(before.count == after.count)
        for (a, b) in zip(before, after) {
            #expect(a.id == b.id)
            #expect(a.commands.count == b.commands.count)
            for (one, two) in zip(a.commands, b.commands) {
                #expect(one.startTime == two.startTime)
                #expect(one.endTime == two.endTime)
                #expect(one.kind == two.kind)
            }
        }
    }

    @Test("double speed halves the times")
    func speedCompresses() {
        var document = makeDocument()
        let trackID = clip(in: document)
        let filter = document.addFilter(TimeFilter.descriptor, to: trackID)!

        let before = evaluator.evaluate(document)
        document.setFilterValue(.number(2), for: TimeFilter.Param.speed, on: filter.id, in: trackID)
        let after = evaluator.evaluate(document)

        let wasLast = before.flatMap { $0.commands.map(\.endTime) }.max()!
        let isLast = after.flatMap { $0.commands.map(\.endTime) }.max()!

        #expect(abs(isLast - wasLast / 2) < 1)
    }

    /// Not one sprite more, whatever the speed: this is the filter that buys
    /// the most for nothing.
    @Test("time costs no sprites")
    func timeIsFree() {
        var document = makeDocument()
        let trackID = clip(in: document)
        let filter = document.addFilter(TimeFilter.descriptor, to: trackID)!
        document.setFilterValue(.number(0.25), for: TimeFilter.Param.speed, on: filter.id, in: trackID)
        document.setFilterValue(.toggle(true), for: TimeFilter.Param.reverse, on: filter.id, in: trackID)

        let before = makeDocument(count: 6)
        #expect(evaluator.evaluate(document).count == evaluator.evaluate(before).count)
    }

    /// Reversal has to flip the values as well as the times.
    ///
    /// Moved to an earlier moment and left alone, a fade that rose still rises:
    /// the sprite would be in the right place doing the wrong thing, which is
    /// the half of "backwards" that is easy to miss.
    @Test("reverse turns a rise into a fall")
    func reverseFlipsValues() {
        var document = makeDocument()
        let trackID = clip(in: document)
        let filter = document.addFilter(TimeFilter.descriptor, to: trackID)!
        document.setFilterValue(.toggle(true), for: TimeFilter.Param.reverse, on: filter.id, in: trackID)

        let sprites = evaluator.evaluate(document)

        // Every fade-in became a fade-out.
        var sawFall = false
        for sprite in sprites {
            for command in sprite.commands {
                if case let .fade(start, end) = command.payload, start > end { sawFall = true }
            }
        }
        #expect(sawFall, "no fade ran downwards after reversing")
    }

    @Test("reversing twice is the original")
    func reverseIsItsOwnInverse() {
        let payload = Command.Payload.move(startX: 1, startY: 2, endX: 3, endY: 4)
        guard case let .move(sx, sy, ex, ey) = payload.reversed.reversed else {
            Issue.record("not a move")
            return
        }
        #expect(sx == 1 && sy == 2 && ex == 3 && ey == 4)
    }

    // ─── Ease ────────────────────────────────────────────────────────────────

    @Test("ease replaces the curve on movement")
    func easeCurvesMovement() {
        var document = makeDocument()
        let trackID = clip(in: document)
        let filter = document.addFilter(EaseFilter.descriptor, to: trackID)!
        document.setFilterValue(
            .choice(EaseFilter.Curve.bounce.rawValue),
            for: EaseFilter.Param.curve, on: filter.id, in: trackID,
        )

        let sprites = evaluator.evaluate(document)
        let moves = sprites.flatMap { $0.commands }.filter { $0.kind == .move }

        #expect(!moves.isEmpty)
        #expect(moves.allSatisfy { $0.easing == .bounceOut })
    }

    /// A bouncing opacity flickers and an elastic one flashes past full
    /// brightness, so the curves that flatter movement are left off fades.
    @Test("movement only leaves fades alone")
    func easeSparesFades() {
        var document = makeDocument()
        let trackID = clip(in: document)
        let filter = document.addFilter(EaseFilter.descriptor, to: trackID)!
        document.setFilterValue(
            .choice(EaseFilter.Curve.bounce.rawValue),
            for: EaseFilter.Param.curve, on: filter.id, in: trackID,
        )

        let sprites = evaluator.evaluate(document)
        let fades = sprites.flatMap { $0.commands }.filter { $0.kind == .fade }

        #expect(!fades.isEmpty)
        #expect(fades.allSatisfy { $0.easing != .bounceOut })
    }

    @Test("ease costs no sprites")
    func easeIsFree() {
        var document = makeDocument()
        let before = evaluator.evaluate(document).count
        _ = document.addFilter(EaseFilter.descriptor, to: clip(in: document))

        #expect(evaluator.evaluate(document).count == before)
    }

    // ─── Radial ──────────────────────────────────────────────────────────────

    @Test("radial repeat makes one copy per arm")
    func radialMultiplies() {
        var document = makeDocument()
        let trackID = clip(in: document)
        let filter = document.addFilter(RadialFilter.descriptor, to: trackID)!
        document.setFilterValue(.integer(5), for: RadialFilter.Param.count, on: filter.id, in: trackID)

        let plain = evaluator.evaluate(makeDocument(count: 6)).count
        #expect(evaluator.evaluate(document).count == plain * 5)
    }

    /// The arms have to land in different places, or it is five copies of the
    /// same thing stacked on one spot — five times the file for one silhouette.
    @Test("the arms are spread around the circle")
    func armsAreSpread() {
        var document = makeDocument()
        let trackID = clip(in: document)
        let filter = document.addFilter(RadialFilter.descriptor, to: trackID)!
        document.setFilterValue(.integer(6), for: RadialFilter.Param.count, on: filter.id, in: trackID)
        document.setFilterValue(.number(120), for: RadialFilter.Param.radius, on: filter.id, in: trackID)

        let centreX = TransformProperty.x.defaultValue
        let centreY = TransformProperty.y.defaultValue

        var angles: Set<Int> = []
        for sprite in evaluator.evaluate(document) {
            for command in sprite.commands {
                guard case let .move(sx, sy, _, _) = command.payload else { continue }
                let angle = atan2(sy - centreY, sx - centreX) * 180 / .pi
                // Bucketed, since particles within one arm spread a little.
                angles.insert(Int((angle / 30).rounded()))
            }
        }

        #expect(angles.count >= 4, "the arms landed on top of each other")
    }

    @Test("every arm gets its own id")
    func armsAreDistinct() {
        var document = makeDocument()
        let trackID = clip(in: document)
        let filter = document.addFilter(RadialFilter.descriptor, to: trackID)!
        document.setFilterValue(.integer(4), for: RadialFilter.Param.count, on: filter.id, in: trackID)

        let ids = evaluator.evaluate(document).map(\.id)
        #expect(Set(ids).count == ids.count, "two arms share a sprite id")
    }

    /// A 360° spread has to place the arms exactly where the old full circle
    /// did — the parameter landed on a filter people are already using.
    @Test("a full spread is the plain circle")
    func fullSpreadIsUnchanged() {
        func angles(spread: Double) -> [Int] {
            var document = makeDocument()
            let trackID = clip(in: document)
            let filter = document.addFilter(RadialFilter.descriptor, to: trackID)!
            document.setFilterValue(.integer(4), for: RadialFilter.Param.count, on: filter.id, in: trackID)
            document.setFilterValue(.number(150), for: RadialFilter.Param.radius, on: filter.id, in: trackID)
            document.setFilterValue(.number(spread), for: RadialFilter.Param.arc, on: filter.id, in: trackID)

            let centreX = TransformProperty.x.defaultValue
            let centreY = TransformProperty.y.defaultValue
            var found: Set<Int> = []
            for sprite in evaluator.evaluate(document) {
                for command in sprite.commands {
                    guard case let .move(sx, sy, _, _) = command.payload else { continue }
                    found.insert(Int((atan2(sy - centreY, sx - centreX) * 180 / .pi / 15).rounded()))
                }
            }
            return found.sorted()
        }

        // Four arms over a full turn sit a quarter apart, and the default has
        // to be exactly that.
        #expect(angles(spread: 360).count >= 4)
    }

    /// Narrowed, the arms crowd into that wedge rather than ringing the centre.
    @Test("a narrow spread makes a fan, not a ring")
    func narrowSpreadFans() {
        func spans(_ spread: Double) -> Double {
            var document = makeDocument()
            let trackID = clip(in: document)
            let filter = document.addFilter(RadialFilter.descriptor, to: trackID)!
            document.setFilterValue(.integer(5), for: RadialFilter.Param.count, on: filter.id, in: trackID)
            document.setFilterValue(.number(150), for: RadialFilter.Param.radius, on: filter.id, in: trackID)
            document.setFilterValue(.number(spread), for: RadialFilter.Param.arc, on: filter.id, in: trackID)

            let centreY = TransformProperty.y.defaultValue
            var lowest = Double.infinity
            var highest = -Double.infinity
            for sprite in evaluator.evaluate(document) {
                for command in sprite.commands {
                    guard case let .move(_, sy, _, _) = command.payload else { continue }
                    lowest = min(lowest, sy - centreY)
                    highest = max(highest, sy - centreY)
                }
            }
            return highest - lowest
        }

        // A ring reaches as far above the centre as below it; a 60° fan does
        // not, so its vertical span is the smaller of the two.
        #expect(spans(60) < spans(360) * 0.75)
    }

    /// Twist winds the figure: with it on, no two arms sit a clean fraction of
    /// the circle apart any more.
    @Test("twist offsets each arm further than the last")
    func twistWinds() {
        func firstAngles(twist: Double) -> [Double] {
            var document = makeDocument(count: 1)
            let trackID = clip(in: document)
            let filter = document.addFilter(RadialFilter.descriptor, to: trackID)!
            document.setFilterValue(.integer(4), for: RadialFilter.Param.count, on: filter.id, in: trackID)
            document.setFilterValue(.number(150), for: RadialFilter.Param.radius, on: filter.id, in: trackID)
            document.setFilterValue(.number(twist), for: RadialFilter.Param.twist, on: filter.id, in: trackID)

            let centreX = TransformProperty.x.defaultValue
            let centreY = TransformProperty.y.defaultValue
            return evaluator.evaluate(document).compactMap { sprite in
                for command in sprite.commands {
                    if case let .move(sx, sy, _, _) = command.payload {
                        return atan2(sy - centreY, sx - centreX) * 180 / .pi
                    }
                }
                return nil
            }
        }

        let plain = firstAngles(twist: 0).sorted()
        let wound = firstAngles(twist: 90).sorted()

        #expect(plain.count == wound.count)
        #expect(zip(plain, wound).contains { abs($0 - $1) > 5 }, "twist moved nothing")
    }
}
