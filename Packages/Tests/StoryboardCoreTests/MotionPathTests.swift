import Foundation
import Testing

@testable import StoryboardCore

@Suite("Motion path")
struct MotionPathTests {
    private func line() -> MotionPath {
        MotionPath(points: [
            .init(x: 0, y: 0),
            .init(x: 100, y: 0),
        ])
    }

    @Test("a path runs from its first point to its last")
    func endsAreTheEnds() throws {
        let path = line()
        let start = try #require(path.position(at: 0))
        let end = try #require(path.position(at: 1))

        #expect(abs(start.x - 0) < 0.001)
        #expect(abs(end.x - 100) < 0.001)
    }

    @Test("halfway along a straight line is the middle")
    func straightLineIsEven() throws {
        let middle = try #require(line().position(at: 0.5))
        #expect(abs(middle.x - 50) < 0.5)
    }

    /// Walked by arc length, not by segment.
    ///
    /// Sampling segments evenly is the obvious reading and the wrong one: a
    /// short segment and a long one would take the same time, so anything
    /// following the path would crawl through the tight parts and race down the
    /// straights. A path is a shape; the speed along it is the author's to set.
    @Test("uneven segments are still travelled evenly")
    func arcLengthPacing() throws {
        // One short hop, then a long one.
        let path = MotionPath(points: [
            .init(x: 0, y: 0),
            .init(x: 10, y: 0),
            .init(x: 210, y: 0),
        ])

        // Half the distance is 105, well past the second point. Paced by
        // segment it would sit at 10 — the join — instead.
        let middle = try #require(path.position(at: 0.5))
        #expect(middle.x > 80, "paced by segment, not by length: landed at \(middle.x)")
    }

    @Test("handles bend the line")
    func handlesCurve() throws {
        let curved = MotionPath(points: [
            .init(x: 0, y: 0, outX: 0, outY: 100),
            .init(x: 100, y: 0, inX: 0, inY: 100),
        ])

        let middle = try #require(curved.position(at: 0.5))
        // A straight line would sit at y = 0 the whole way.
        #expect(middle.y > 10, "the handles did not bend anything")
    }

    @Test("a path of one point has nowhere to go")
    func singlePointIsEmpty() {
        let path = MotionPath(points: [.init(x: 5, y: 5)])
        #expect(path.isEmpty)
        #expect(path.position(at: 0.5)?.x == 5)
    }

    @Test("an empty path reports nothing")
    func emptyPath() {
        #expect(MotionPath().isEmpty)
        #expect(MotionPath().position(at: 0.5) == nil)
    }

    @Test("heading follows the direction of travel")
    func headingPointsAhead() {
        // Left to right is zero degrees; downward is ninety.
        #expect(abs(line().heading(at: 0.5)) < 1)

        let down = MotionPath(points: [.init(x: 0, y: 0), .init(x: 0, y: 100)])
        #expect(abs(down.heading(at: 0.5) - 90) < 1)
    }

    /// A path survives a save and reload, since it lives in the project file.
    @Test("a path round-trips through JSON")
    func codable() throws {
        let path = MotionPath(points: [
            .init(x: 1, y: 2, inX: 3, inY: 4, outX: 5, outY: 6),
            .init(x: 7, y: 8),
        ])

        let data = try JSONEncoder().encode(path)
        let back = try JSONDecoder().decode(MotionPath.self, from: data)

        #expect(back == path)
    }
}

@Suite("Motion path filter")
struct PathFilterTests {
    private let evaluator = EffectEvaluator()

    private func makeDocument() -> EffectDocument {
        var document = EffectDocument()
        let node = document.add(EmitterEffect.descriptor, at: 0, duration: 2000)
        document.setValue(.integer(20), for: EmitterEffect.Param.count, on: node.id)
        // Still particles, so any spread that appears came from the path.
        document.setValue(.number(0), for: EmitterEffect.Param.velocity, on: node.id)
        document.setValue(.number(0), for: EmitterEffect.Param.width, on: node.id)
        document.setValue(.number(0), for: EmitterEffect.Param.height, on: node.id)
        return document
    }

    private func clip(in document: EffectDocument) -> EffectNode.ID {
        document.nodes[0].id
    }

    private func straightPath() -> EffectValue {
        .path(MotionPath(points: [
            .init(x: 100, y: 240),
            .init(x: 540, y: 240),
        ]))
    }

    /// An empty path is the default, and the default has to change nothing.
    @Test("no path leaves the sprites alone")
    func emptyPathIsInert() {
        var document = makeDocument()
        let before = evaluator.evaluate(document)
        _ = document.addFilter(PathFilter.descriptor, to: clip(in: document))
        let after = evaluator.evaluate(document)

        #expect(before.count == after.count)
        for (a, b) in zip(before, after) {
            #expect(a.defaultX == b.defaultX)
            #expect(a.defaultY == b.defaultY)
        }
    }

    /// The point of the filter: sprites born later come out further along.
    ///
    /// This is what a transform cannot do — it carries the finished result, so
    /// every particle moves together and the arrangement never changes. Here
    /// only the birthplace moves, and the trail forms behind the source.
    @Test("later sprites are born further along the path")
    func birthplaceTravels() {
        var document = makeDocument()
        let trackID = clip(in: document)
        let filter = document.addFilter(PathFilter.descriptor, to: trackID)!
        document.setFilterValue(straightPath(), for: PathFilter.Param.path, on: filter.id, in: trackID)

        let sprites = evaluator.evaluate(document)
            .sorted { ($0.commands.map(\.startTime).min() ?? 0) < ($1.commands.map(\.startTime).min() ?? 0) }

        let firstX = sprites.first!.defaultX
        let lastX = sprites.last!.defaultX

        #expect(lastX > firstX + 200, "the source did not travel: \(firstX) to \(lastX)")
    }

    /// And they stay where they were born — that is what makes it a trail
    /// rather than a cloud being dragged.
    @Test("the spread comes from the path, not from the particles")
    func trailIsSpread() {
        var document = makeDocument()
        let trackID = clip(in: document)
        let filter = document.addFilter(PathFilter.descriptor, to: trackID)!
        document.setFilterValue(straightPath(), for: PathFilter.Param.path, on: filter.id, in: trackID)

        let xs = evaluator.evaluate(document).map(\.defaultX)
        let spread = xs.max()! - xs.min()!

        // The path is 440 wide and the particles do not move at all, so
        // anything close to that came from the path.
        #expect(spread > 300, "the sprites bunched up: \(spread)px across")
    }

    @Test("the path costs no sprites")
    func pathIsFree() {
        var document = makeDocument()
        let plain = evaluator.evaluate(document).count
        let trackID = clip(in: document)
        let filter = document.addFilter(PathFilter.descriptor, to: trackID)!
        document.setFilterValue(straightPath(), for: PathFilter.Param.path, on: filter.id, in: trackID)

        #expect(evaluator.evaluate(document).count == plain)
    }

    /// Pacing changes where the source is partway through, without changing
    /// where it starts or ends.
    @Test("pacing changes the spacing, not the ends")
    func pacingReshapes() {
        func positions(_ pacing: PathFilter.Pacing) -> [Double] {
            var document = makeDocument()
            let trackID = clip(in: document)
            let filter = document.addFilter(PathFilter.descriptor, to: trackID)!
            document.setFilterValue(straightPath(), for: PathFilter.Param.path, on: filter.id, in: trackID)
            document.setFilterValue(
                .choice(pacing.rawValue), for: PathFilter.Param.ease, on: filter.id, in: trackID,
            )
            return evaluator.evaluate(document).map(\.defaultX).sorted()
        }

        let steady = positions(.steady)
        let accelerating = positions(.accelerate)

        #expect(steady.count == accelerating.count)
        // Accelerating, the source lingers near the start, so the middle of the
        // run sits further back than it does at a steady pace.
        let middle = steady.count / 2
        #expect(accelerating[middle] < steady[middle])
    }

    /// The path is where the source **goes**, not how far it moves.
    ///
    /// A filter runs after the clip's transform, so an effect placed away from
    /// the middle arrives already there. Working the displacement out from the
    /// stage centre then added it on top: a Magic sitting at y 360 landed twice
    /// as far from the middle as its path said, drifting off below and to the
    /// right of the curve it was supposed to follow.
    @Test("an offset effect still lands on its path")
    func pathIsAbsolute() {
        var document = EffectDocument()
        var node = document.add(EmitterEffect.descriptor, at: 0, duration: 2000)
        document.setValue(.integer(6), for: EmitterEffect.Param.count, on: node.id)
        document.setValue(.number(0), for: EmitterEffect.Param.velocity, on: node.id)
        document.setValue(.number(0), for: EmitterEffect.Param.width, on: node.id)
        document.setValue(.number(0), for: EmitterEffect.Param.height, on: node.id)

        // Placed well away from the centre, the way a preset does.
        node = document[node.id]!
        node.transform[value: .x] = 200
        node.transform[value: .y] = 400
        document[node.id] = node

        let filter = document.addFilter(PathFilter.descriptor, to: node.id)!
        document.setFilterValue(
            .path(MotionPath(points: [.init(x: 100, y: 100), .init(x: 500, y: 100)])),
            for: PathFilter.Param.path, on: filter.id, in: node.id,
        )

        for sprite in evaluator.evaluate(document) {
            #expect(abs(sprite.defaultY - 100) < 1, "landed at y \(sprite.defaultY), not on the path")
            #expect(sprite.defaultX >= 99 && sprite.defaultX <= 501)
        }
    }

    /// A burst has nothing to spread by time, so it spreads by index instead.
    ///
    /// Everything leaves at once, so every sprite asked the path for the same
    /// point and landed in a heap — the filter looked broken on half the
    /// presets in the library. Spread by index the same burst becomes a row of
    /// sparks laid along the curve, which was not obtainable any other way.
    @Test("a burst is laid along the path rather than heaped")
    func burstSpreadsByIndex() {
        var document = EffectDocument()
        let node = document.add(EmitterEffect.descriptor, at: 0, duration: 2000)
        document.setValue(.integer(20), for: EmitterEffect.Param.count, on: node.id)
        document.setValue(.choice("Burst"), for: EmitterEffect.Param.emission, on: node.id)
        document.setValue(.number(0), for: EmitterEffect.Param.velocity, on: node.id)
        document.setValue(.number(0), for: EmitterEffect.Param.width, on: node.id)
        document.setValue(.number(0), for: EmitterEffect.Param.height, on: node.id)

        let filter = document.addFilter(PathFilter.descriptor, to: node.id)!
        document.setFilterValue(
            .path(MotionPath(points: [.init(x: 100, y: 240), .init(x: 500, y: 240)])),
            for: PathFilter.Param.path, on: filter.id, in: node.id,
        )

        let xs = evaluator.evaluate(document).map(\.defaultX).sorted()
        #expect(xs.last! - xs.first! > 350, "the burst heaped up: \(xs.last! - xs.first!)px across")
    }

    /// And a continuous emitter still spreads by time, which is what makes the
    /// source read as travelling rather than as a shape being drawn all at once.
    @Test("a continuous emitter still spreads by time")
    func continuousStillUsesTime() {
        var document = EffectDocument()
        let node = document.add(EmitterEffect.descriptor, at: 0, duration: 2000)
        document.setValue(.integer(20), for: EmitterEffect.Param.count, on: node.id)
        document.setValue(.number(0), for: EmitterEffect.Param.velocity, on: node.id)
        document.setValue(.number(0), for: EmitterEffect.Param.width, on: node.id)
        document.setValue(.number(0), for: EmitterEffect.Param.height, on: node.id)

        let filter = document.addFilter(PathFilter.descriptor, to: node.id)!
        document.setFilterValue(
            .path(MotionPath(points: [.init(x: 100, y: 240), .init(x: 500, y: 240)])),
            for: PathFilter.Param.path, on: filter.id, in: node.id,
        )

        // Sorted by birth, the positions have to climb: later means further on.
        let byBirth = evaluator.evaluate(document)
            .sorted { ($0.commands.map(\.startTime).min() ?? 0) < ($1.commands.map(\.startTime).min() ?? 0) }

        #expect(byBirth.last!.defaultX > byBirth.first!.defaultX + 300)
    }
}
