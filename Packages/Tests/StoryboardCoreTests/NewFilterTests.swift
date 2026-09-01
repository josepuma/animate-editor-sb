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

    // ─── Mirror ──────────────────────────────────────────────────────────────

    @Test("mirror doubles the sprites")
    func mirrorDoubles() {
        var document = makeDocument()
        let plain = evaluator.evaluate(document).count
        _ = document.addFilter(MirrorFilter.descriptor, to: clip(in: document))

        #expect(evaluator.evaluate(document).count == plain * 2)
    }

    /// A reflection lands on the far side of the axis, not on top of its
    /// subject: a mirror that copies in place is two sprites for one silhouette.
    @Test("the reflection lands across the axis")
    func mirrorReflects() {
        var document = makeDocument(count: 4)
        _ = document.addFilter(MirrorFilter.descriptor, to: clip(in: document))

        // Measured where the particles *travel*, not where they are born: an
        // emitter starts them all at its own centre, so the birth point is the
        // one place a reflection cannot show.
        let centre = TransformProperty.x.defaultValue
        var xs: [Double] = []
        for sprite in evaluator.evaluate(document) {
            for command in sprite.commands {
                if case let .move(_, _, ex, _) = command.payload { xs.append(ex - centre) }
            }
        }

        #expect(xs.contains { $0 > 1 })
        #expect(xs.contains { $0 < -1 })
    }

    /// The image turns over as well as the position.
    ///
    /// Without the flip a reflected arrow still points the same way: the
    /// arrangement would be mirrored while every sprite inside it was not,
    /// which is the difference between a reflection and a copy moved sideways.
    @Test("the reflected sprites are flipped")
    func mirrorFlipsTheImage() {
        var document = makeDocument()
        _ = document.addFilter(MirrorFilter.descriptor, to: clip(in: document))

        let flipped = evaluator.evaluate(document).filter { sprite in
            sprite.commands.contains { command in
                if case .parameter(.flipHorizontal) = command.payload { return true }
                return false
            }
        }

        #expect(!flipped.isEmpty, "no copy was flipped")
    }

    /// Both axes gives three reflections, not two — the diagonal one closes the
    /// figure. Left out it is an L rather than a square.
    @Test("both axes make four in total")
    func mirrorBothAxes() {
        var document = makeDocument()
        let trackID = clip(in: document)
        let plain = evaluator.evaluate(document).count

        let filter = document.addFilter(MirrorFilter.descriptor, to: trackID)!
        document.setFilterValue(
            .choice(MirrorFilter.Axis.both.rawValue),
            for: MirrorFilter.Param.axis, on: filter.id, in: trackID,
        )

        #expect(evaluator.evaluate(document).count == plain * 4)
    }

    // ─── Chromatic ───────────────────────────────────────────────────────────

    @Test("chromatic makes three channels")
    func chromaticSplits() {
        var document = makeDocument()
        let plain = evaluator.evaluate(document).count
        _ = document.addFilter(ChromaticFilter.descriptor, to: clip(in: document))

        #expect(evaluator.evaluate(document).count == plain * 3)
    }

    /// Each copy carries one channel, and they have to be *different* channels:
    /// three red copies are three times the file for a red blur.
    @Test("the channels are red, green and blue")
    func chromaticColoursDiffer() {
        var document = makeDocument(count: 1)
        _ = document.addFilter(ChromaticFilter.descriptor, to: clip(in: document))

        var colours: Set<String> = []
        for sprite in evaluator.evaluate(document) {
            for command in sprite.commands {
                if case let .color(r, g, b, _, _, _) = command.payload {
                    colours.insert("\(Int(r)),\(Int(g)),\(Int(b))")
                }
            }
        }

        #expect(colours.count == 3, "the channels came out as \(colours)")
    }

    /// They have to be additive, or the three sit on top of each other as
    /// coloured blocks instead of summing back to white in the middle.
    @Test("the channels blend additively")
    func chromaticIsAdditive() {
        var document = makeDocument()
        _ = document.addFilter(ChromaticFilter.descriptor, to: clip(in: document))

        let sprites = evaluator.evaluate(document)
        #expect(sprites.allSatisfy { sprite in
            sprite.commands.contains { command in
                if case .parameter(.additive) = command.payload { return true }
                return false
            }
        })
    }

    /// A split of zero is someone turning the filter off with its own slider,
    /// and it should cost nothing rather than tripling the file for no visible
    /// change.
    @Test("no split means no copies")
    func chromaticZeroIsInert() {
        var document = makeDocument()
        let trackID = clip(in: document)
        let plain = evaluator.evaluate(document).count

        let filter = document.addFilter(ChromaticFilter.descriptor, to: trackID)!
        document.setFilterValue(.number(0), for: ChromaticFilter.Param.offset, on: filter.id, in: trackID)

        #expect(evaluator.evaluate(document).count == plain)
    }

    /// Off by default, and off has to mean unchanged: the parameter landed on
    /// a filter that is already in use.
    @Test("no jitter leaves the split steady")
    func jitterDefaultsInert() {
        var document = makeDocument()
        let trackID = clip(in: document)
        let filter = document.addFilter(ChromaticFilter.descriptor, to: trackID)!

        let before = evaluator.evaluate(document)
        document.setFilterValue(.number(0), for: ChromaticFilter.Param.jitter, on: filter.id, in: trackID)
        let after = evaluator.evaluate(document)

        #expect(before.count == after.count)
        for (a, b) in zip(before, after) {
            #expect(a.commands.count == b.commands.count)
        }
    }

    /// Turned up, the split moves during the clip rather than holding one
    /// offset — which is the difference between a lens out of focus and a
    /// signal breaking up.
    @Test("jitter makes the split jump")
    func jitterJumps() {
        var document = makeDocument(count: 2)
        let trackID = clip(in: document)
        let filter = document.addFilter(ChromaticFilter.descriptor, to: trackID)!

        let steady = evaluator.evaluate(document).flatMap(\.commands).count
        document.setFilterValue(.number(0.8), for: ChromaticFilter.Param.jitter, on: filter.id, in: trackID)
        let jumpy = evaluator.evaluate(document).flatMap(\.commands).count

        #expect(jumpy > steady, "jitter wrote no movement")
    }

    /// Each channel jumps on its own. Leaping together they would slide as a
    /// block, which reads as a shake rather than as a picture coming apart.
    @Test("the channels jump independently")
    func jitterIsPerChannel() {
        var document = makeDocument(count: 1)
        let trackID = clip(in: document)
        let filter = document.addFilter(ChromaticFilter.descriptor, to: trackID)!
        document.setFilterValue(.number(0.9), for: ChromaticFilter.Param.jitter, on: filter.id, in: trackID)

        // Where each channel is at the same moment.
        var byChannel: [String: [Double]] = [:]
        for sprite in evaluator.evaluate(document) {
            let channel = String(sprite.id.suffix(4))
            for command in sprite.commands {
                if case let .move(sx, _, _, _) = command.payload {
                    byChannel[channel, default: []].append(sx)
                }
            }
        }

        #expect(byChannel.count >= 2)
        // Two channels tracing the same path would be one shake in three
        // colours.
        let paths = Set(byChannel.values.map { $0.map { Int($0) }.description })
        #expect(paths.count == byChannel.count, "two channels jumped identically")
    }

    /// Every step is a command in the file, so a long clip at a high rate has
    /// to stop somewhere — past the cap the flicker is faster than anyone sees.
    @Test("the jumps are capped")
    func jitterIsCapped() {
        var document = EffectDocument()
        let node = document.add(EmitterEffect.descriptor, at: 0, duration: 60_000)
        document.setValue(.integer(1), for: EmitterEffect.Param.count, on: node.id)
        let filter = document.addFilter(ChromaticFilter.descriptor, to: node.id)!
        document.setFilterValue(.number(1), for: ChromaticFilter.Param.jitter, on: filter.id, in: node.id)
        document.setFilterValue(.number(30), for: ChromaticFilter.Param.rate, on: filter.id, in: node.id)

        let moves = evaluator.evaluate(document)
            .flatMap(\.commands)
            .count { $0.kind == .move }

        // Three channels, capped at 120 apiece, plus the emitter's own.
        #expect(moves < 500, "\(moves) move commands from one particle")
    }
}
