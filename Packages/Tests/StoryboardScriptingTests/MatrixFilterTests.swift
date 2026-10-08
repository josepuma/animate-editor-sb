import Foundation
import Testing

@testable import StoryboardCore
import StoryboardTestSupport

/// The clips the matrix stands on have to be what it says they are.
///
/// Every guard below compares a filtered clip against the same clip
/// unfiltered, so a clip that draws nothing — a script whose runtime never
/// arrived, a compound whose layers were dropped — would make every one of
/// them pass while measuring nothing.
@Suite("Clip matrix premises")
struct ClipMatrixPremiseTests {
    @Test("one clip of every kind the editor places")
    func everyKind() {
        #expect(ClipMatrix.clips.map(\.name) == ["emitter", "script", "text", "shape", "compound"])
    }

    @Test("every clip draws, and draws something that moves", arguments: ClipMatrix.clips)
    func drawsAndMoves(_ clip: ClipMatrix.Clip) {
        let sprites = ClipMatrix.evaluate(clip)
        #expect(!sprites.isEmpty, "\(clip.name) drew nothing")
        // A filter that rewrites movement passes vacuously on a still clip.
        let moves = sprites.contains { sprite in
            sprite.commands.contains { [.move, .moveX, .moveY].contains($0.kind) }
        }
        #expect(moves, "\(clip.name) has no movement for a filter to act on")
    }

    @Test("the script clip is drawn by the real runtime")
    func scriptRuns() throws {
        let script = try #require(ClipMatrix.clips.first { $0.name == "script" })
        #expect(ClipMatrix.evaluate(script).count == 12)
    }

    @Test("the compound keeps its layers, one of them waiting")
    func compoundHasLayers() throws {
        let compound = try #require(ClipMatrix.clips.first { $0.name == "compound" })
        #expect(compound.node.layers.count >= 2)
        #expect(compound.node.layers.contains { ($0.delay ?? 0) > 0 })
        let ids = Set(ClipMatrix.evaluate(compound).map(\.id))
        // Layer sprites are named under `parent/L#`, so each layer drew.
        for index in compound.node.layers.indices {
            #expect(ids.contains { $0.contains("/L\(index)") }, "layer \(index) drew nothing")
        }
    }

    /// Unfiltered, nothing overlaps — so whatever the overlap guard finds
    /// later was written by the filter, not inherited from the clip.
    @Test("an unfiltered clip writes no overlapping commands", arguments: ClipMatrix.clips)
    func baselineIsClean(_ clip: ClipMatrix.Clip) {
        let found = ClipMatrix.evaluate(clip).flatMap(CommandOverlapGuard.violations)
        #expect(found.isEmpty, "\(found.prefix(3))")
    }
}

/// Every filter, against every kind of clip.
///
/// A filter receives finished sprites and cannot tell where they came from,
/// which is what lets it go on anything — and also why a filter written
/// against one kind can quietly fail on another. These guards are the
/// standing contract a new filter joins by being in `FilterLibrary.standard`.
@Suite("Filters across the clip matrix")
struct MatrixFilterTests {
    /// Filters that draw exactly what they were given until someone turns a
    /// number. Each with the reason it is inert, because a list without
    /// reasons is one nobody can check:
    ///
    /// - Time, Fade, Audio Drive: their defaults are 1×, zero-length ramps and
    ///   zero drive — they wait to be asked.
    /// - Motion Path: an empty path has nowhere to take anything.
    ///
    /// Ease is not here: dropping it on a clip is asking for a curve, and its
    /// default is one. Every other filter changes the look by default — that
    /// is its job — and the second half of the guard holds them to it, so an
    /// entry here that stops being true fails either way.
    static let inertAtDefaults: Set<String> = ["time", "fade", "audio-drive", "path"]

    /// By type, not descriptor: a descriptor prints every parameter it has, and
    /// a failure named by five screens of them names nothing.
    static let filters: [String] = FilterLibrary.standard.descriptors.map(\.type)

    static func descriptor(_ type: String) -> FilterDescriptor {
        FilterLibrary.standard.descriptors.first { $0.type == type }!
    }

    @Test("the inert list names only filters that exist")
    func inertListIsReal() {
        let types = Set(Self.filters)
        #expect(Self.inertAtDefaults.isSubset(of: types))
    }

    @Test("an inert filter changes nothing on any clip", arguments: ClipMatrix.clips, filters)
    func inertIsInert(_ clip: ClipMatrix.Clip, _ type: String) {
        let filter = Self.descriptor(type)
        guard Self.inertAtDefaults.contains(filter.type) else { return }
        let plain = ClipMatrix.signature(ClipMatrix.evaluate(clip))
        let filtered = ClipMatrix.signature(ClipMatrix.evaluate(clip, with: ClipMatrix.filterNode(filter)))
        #expect(plain == filtered, "\(filter.name) changed \(clip.name) at its defaults")
    }

    /// The other side: a filter left off the list has to do something
    /// somewhere, or the list is hiding a filter that broke.
    @Test("every other filter changes at least one clip", arguments: filters)
    func activeIsActive(_ type: String) {
        let filter = Self.descriptor(type)
        guard !Self.inertAtDefaults.contains(filter.type) else { return }
        let changed = ClipMatrix.clips.contains { clip in
            ClipMatrix.signature(ClipMatrix.evaluate(clip))
                != ClipMatrix.signature(ClipMatrix.evaluate(clip, with: ClipMatrix.filterNode(filter)))
        }
        #expect(changed, "\(filter.name) changed nothing on any clip")
    }

    /// Filters that move a sprite's life on purpose, each with its reason:
    ///
    /// - Time, Stagger: changing when things happen is the job.
    /// - Loop: its body repeats past the original span by design.
    /// - Shatter: the pieces fly on past the sprite's own end.
    static let movesLife: Set<String> = ["time", "stagger", "loop", "shatter"]

    /// A filter must not make a sprite alive before it was born, or keep it
    /// after it died. osu! draws a sprite across its whole command span and,
    /// before its first command, with that command's opening values — so an
    /// earlier start is a sprite showing up where nothing put it. Beat Pulse
    /// wrote clip-wide beats on every sprite, and a spark born at second 3
    /// was drawn from second 0 as a full-size blob; this guard is what would
    /// have caught it, because no single-filter check was looking at life.
    @Test("no filter stretches a sprite's life", arguments: ClipMatrix.clips, filters)
    func keepsLives(_ clip: ClipMatrix.Clip, _ type: String) {
        guard !Self.movesLife.contains(type) else { return }
        let filter = Self.descriptor(type)
        let before = Dictionary(
            ClipMatrix.evaluate(clip).map { ($0.id, Self.life($0)) }, uniquingKeysWith: { a, _ in a },
        )
        for node in [ClipMatrix.filterNode(filter), ClipMatrix.exercised(filter)] {
            for sprite in ClipMatrix.evaluate(clip, with: node) {
                guard let was = before[sprite.id] else { continue }
                let now = Self.life(sprite)
                #expect(now.start >= was.start - 1e-6 && now.end <= was.end + 1e-6,
                        "\(filter.name) on \(clip.name): \(sprite.id) \(was) → \(now)")
            }
        }
    }

    private static func life(_ sprite: StoryboardSprite) -> (start: Double, end: Double) {
        let prepared = StoryboardResolver.prepare([sprite])[0]
        return (prepared.activeStart, prepared.activeEnd)
    }

    /// Two filters together, in the order the report had them: one that adds
    /// short-lived sprites, then each other filter over the result. A filter
    /// that is fine alone can still mishandle sprites another one made.
    static let adders: [String] = ["spark-trail", "disintegrate", "echo"]

    @Test("a filter after one that adds sprites keeps their lives too", arguments: adders, filters)
    func keepsAddedLives(_ adder: String, _ type: String) {
        guard !Self.movesLife.contains(type), adder != type,
              let clip = ClipMatrix.clips.first(where: { $0.name == "text" })
        else { return }
        let first = ClipMatrix.filterNode(Self.descriptor(adder))
        let alone = ClipMatrix.evaluate(clip, with: [first])
        let before = Dictionary(alone.map { ($0.id, Self.life($0)) }, uniquingKeysWith: { a, _ in a })
        let together = ClipMatrix.evaluate(clip, with: [first, ClipMatrix.filterNode(Self.descriptor(type))])
        for sprite in together {
            guard let was = before[sprite.id] else { continue }
            let now = Self.life(sprite)
            #expect(now.start >= was.start - 1e-6 && now.end <= was.end + 1e-6,
                    "\(adder) then \(type): \(sprite.id) \(was) → \(now)")
        }
        #expect(together.flatMap(CommandOverlapGuard.violations).isEmpty, "\(adder) then \(type)")
    }

    /// osu! does not add two commands on one property: the last one written
    /// wins, so a filter that writes its movement beside the clip's own makes
    /// the sprite tug between two paths. Checked with the numbers turned up,
    /// since a guard at the defaults audits filters that are not doing
    /// anything yet.
    @Test("no filter leaves two commands fighting over a property", arguments: ClipMatrix.clips, filters)
    func noOverlap(_ clip: ClipMatrix.Clip, _ type: String) {
        let filter = Self.descriptor(type)
        for node in [ClipMatrix.filterNode(filter), ClipMatrix.exercised(filter)] {
            let found = ClipMatrix.evaluate(clip, with: node).flatMap(CommandOverlapGuard.violations)
            #expect(found.isEmpty, "\(filter.name) on \(clip.name): \(found.prefix(3))")
        }
    }
}
