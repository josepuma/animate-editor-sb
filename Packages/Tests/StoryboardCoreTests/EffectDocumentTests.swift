import Testing

@testable import StoryboardCore

@Suite("EffectDocument")
struct EffectDocumentTests {
    private let descriptor = EmitterEffect.descriptor

    /// One track holding `count` effects, spaced a second apart.
    private func document(count: Int) -> EffectDocument {
        var document = EffectDocument()
        for index in 0..<count {
            _ = document.add(descriptor, at: Double(index) * 1000, duration: 500)
        }
        return document
    }

    // ─── Placing ─────────────────────────────────────────────────────────────

    /// Tracks appear as they are needed: making an empty lane before anything
    /// can go in it is friction in the way of what was actually asked for.
    @Test("the first effect opens a track to hold it")
    func firstEffectOpensATrack() {
        var document = EffectDocument()
        #expect(document.tracks.isEmpty)

        let node = document.add(descriptor, at: 0, duration: 1000)

        #expect(document.tracks.count == 1)
        #expect(document.tracks[0].nodes.map(\.id) == [node.id])
    }

    /// The point of the whole model: a lane holds many effects rather than
    /// being one.
    @Test("effects stack onto the same track")
    func effectsShareATrack() {
        let document = document(count: 4)

        #expect(document.tracks.count == 1)
        #expect(document.tracks[0].nodes.count == 4)
        #expect(document.nodes.count == 4)
    }

    @Test("an effect can be placed on a named track")
    func placingOnATrack() {
        var document = EffectDocument()
        let first = document.addTrack(named: "Intro")
        let second = document.addTrack(named: "Chorus")

        let node = document.add(descriptor, at: 0, duration: 500, on: first.id)

        #expect(document.trackID(of: node.id) == first.id)
        #expect(document.track(id: second.id)?.nodes.isEmpty == true)
    }

    @Test("a new node starts at the effect's declared defaults")
    func newNodeUsesDefaults() {
        var document = EffectDocument()
        let node = document.add(descriptor, at: 0, duration: 1000)

        #expect(node.values.count == descriptor.parameters.count)
        #expect(
            node.values[EmitterEffect.Param.count]
                == descriptor.parameter(EmitterEffect.Param.count)?.defaultValue,
        )
    }

    /// Two emitters dropped with the same settings should read as two fields,
    /// not as one drawn twice.
    @Test("effects get different seeds")
    func seedsDiffer() {
        let document = document(count: 3)
        #expect(Set(document.nodes.map(\.seed)).count == 3)
    }

    @Test("names are numbered per effect type")
    func namesAreNumbered() {
        let document = document(count: 3)
        #expect(document.nodes.map(\.name) == ["Emitter", "Emitter 2", "Emitter 3"])
    }

    /// The layer belongs to the lane, so an effect placed on one takes it on.
    @Test("an effect adopts its track's layer")
    func effectsInheritTheTrackLayer() {
        var document = EffectDocument()
        let track = document.addTrack(named: "Behind", layer: .background)
        let node = document.add(descriptor, at: 0, duration: 500, on: track.id)

        #expect(node.layer == .background)
    }

    // ─── Editing effects ─────────────────────────────────────────────────────

    @Test("moving an effect keeps its duration")
    func moveKeepsDuration() {
        var document = document(count: 1)
        let id = document.nodes[0].id
        document.move(id, to: 4000)

        #expect(document[id]?.startTime == 4000)
        #expect(document[id]?.duration == 500)
    }

    /// A clip dragged past the left edge would otherwise sit at a negative
    /// start with no way to grab it back.
    @Test("an effect cannot be moved before zero")
    func moveClampsAtZero() {
        var document = document(count: 1)
        let id = document.nodes[0].id
        document.move(id, to: -5000)

        #expect(document[id]?.startTime == 0)
    }

    @Test("an effect cannot be resized below its minimum")
    func resizeHasAFloor() {
        var document = document(count: 1)
        let id = document.nodes[0].id
        document.resize(id, startTime: 0, duration: 1, minimumDuration: 100)

        #expect(document[id]?.duration == 100)
    }

    @Test("setting a value leaves the other parameters alone")
    func setValueIsTargeted() {
        var document = document(count: 1)
        let id = document.nodes[0].id
        let before = document[id]!.values.count

        document.setValue(.integer(7), for: EmitterEffect.Param.count, on: id)

        #expect(document[id]?.values[EmitterEffect.Param.count] == .integer(7))
        #expect(document[id]?.values.count == before)
    }

    @Test("removing an effect leaves the rest in place")
    func removal() {
        var document = document(count: 3)
        let id = document.nodes[1].id
        document.remove(id)

        #expect(document.nodes.count == 2)
        #expect(document[id] == nil)
    }

    // ─── Duplicating ─────────────────────────────────────────────────────────

    @Test("a duplicate carries everything but its identity")
    func duplicateCarriesSettings() {
        var document = document(count: 1)
        let original = document.nodes[0]
        document.setValue(.integer(42), for: EmitterEffect.Param.count, on: original.id)
        document.setKeyframe(2, for: .scaleX, at: 100, on: original.id)

        let copy = document.duplicate(original.id)!

        #expect(copy.id != original.id)
        #expect(copy.values[EmitterEffect.Param.count] == .integer(42))
        #expect(copy.transform[.scaleX].keyframes.count == 1)
        #expect(copy.duration == original.duration)
    }

    /// Two clips at the same moment look like one, and the copy would be
    /// invisible.
    @Test("a duplicate lands after the original")
    func duplicateFollowsIt() {
        var document = document(count: 1)
        let original = document.nodes[0]

        let copy = document.duplicate(original.id)!

        #expect(copy.startTime == original.endTime)
        #expect(document.tracks[0].nodes.map(\.id) == [original.id, copy.id])
    }

    /// A duplicated emitter with the same seed is the same field drawn twice,
    /// which is not what anyone means by "duplicate".
    @Test("a duplicate gets its own seed")
    func duplicateReseeds() {
        var document = document(count: 1)
        let original = document.nodes[0]

        let copy = document.duplicate(original.id)!

        #expect(copy.seed != original.seed)

        // Compared by trajectory, not by birthplace: a default emitter has no
        // size, so every particle starts at the same point whatever the seed —
        // the difference is in where they go.
        let evaluator = EffectEvaluator()
        let a = evaluator.evaluate(original).flatMap { $0.commands.map(\.endTime) }
        let b = evaluator.evaluate(copy).flatMap { $0.commands.map(\.endTime) }
        #expect(a != b)
    }

    @Test("duplicating something that is not there does nothing")
    func duplicatingNothing() {
        var document = document(count: 1)
        #expect(document.duplicate("missing") == nil)
        #expect(document.nodes.count == 1)
    }

    // ─── Moving between tracks ───────────────────────────────────────────────

    @Test("an effect can be moved to another track, keeping its timing")
    func movingBetweenTracks() {
        var document = EffectDocument()
        let source = document.addTrack(named: "A")
        let destination = document.addTrack(named: "B")
        let node = document.add(descriptor, at: 2500, duration: 800, on: source.id)

        document.move(node.id, toTrack: destination.id)

        #expect(document.trackID(of: node.id) == destination.id)
        #expect(document[node.id]?.startTime == 2500)
        #expect(document[node.id]?.duration == 800)
        #expect(document.track(id: source.id)?.nodes.isEmpty == true)
    }

    /// A node carrying its old layer would draw somewhere its own row does not
    /// claim.
    @Test("a moved effect takes on its new track's layer")
    func movingAdoptsTheLayer() {
        var document = EffectDocument()
        let source = document.addTrack(named: "Front", layer: .foreground)
        let destination = document.addTrack(named: "Back", layer: .background)
        let node = document.add(descriptor, at: 0, duration: 500, on: source.id)

        document.move(node.id, toTrack: destination.id)

        #expect(document[node.id]?.layer == .background)
    }

    // ─── Tracks ──────────────────────────────────────────────────────────────

    @Test("raising a track moves it one step later")
    func raising() {
        var document = EffectDocument()
        let ids = (0..<3).map { _ in document.addTrack().id }

        document.raiseTrack(ids[1])
        #expect(document.tracks.map(\.id)[2] == ids[1])
    }

    @Test("lowering a track moves it one step earlier")
    func lowering() {
        var document = EffectDocument()
        let ids = (0..<3).map { _ in document.addTrack().id }

        document.lowerTrack(ids[1])
        #expect(document.tracks.map(\.id)[0] == ids[1])
    }

    @Test("the ends cannot be moved past themselves")
    func clampedAtTheEnds() {
        var document = EffectDocument()
        let ids = (0..<3).map { _ in document.addTrack().id }

        document.raiseTrack(ids[2])
        document.lowerTrack(ids[0])

        #expect(document.tracks.map(\.id) == ids)
        #expect(!document.canRaiseTrack(ids[2]))
        #expect(!document.canLowerTrack(ids[0]))
    }

    /// Track order is draw order within a layer, since the renderer keeps array
    /// order to break ties. Reordering has to reach the sprites.
    @Test("reordering tracks changes the order sprites come out in")
    func reorderingReachesTheOutput() {
        var document = EffectDocument()
        let first = document.addTrack(named: "A")
        let second = document.addTrack(named: "B")
        let a = document.add(descriptor, at: 0, duration: 1000, on: first.id)
        _ = document.add(descriptor, at: 0, duration: 1000, on: second.id)

        let evaluator = EffectEvaluator()
        #expect(evaluator.evaluate(document).first?.id.hasPrefix(a.id) == true)

        document.raiseTrack(first.id)
        #expect(evaluator.evaluate(document).last?.id.hasPrefix(a.id) == true)
    }

    /// Hiding a lane has to hide what is on it — the only reading of the
    /// control that makes sense.
    @Test("a hidden track contributes nothing")
    func hiddenTracksAreSkipped() {
        var document = document(count: 2)
        let trackID = document.tracks[0].id

        #expect(!EffectEvaluator().evaluate(document).isEmpty)

        document.toggleVisibility(of: trackID)
        #expect(EffectEvaluator().evaluate(document).isEmpty)
    }

    @Test("removing a track removes what was on it")
    func removingATrack() {
        var document = document(count: 2)
        let trackID = document.tracks[0].id

        document.removeTrack(trackID)

        #expect(document.tracks.isEmpty)
        #expect(document.nodes.isEmpty)
    }

    /// A blank name would leave a row that cannot be clicked to rename again,
    /// since there is nothing left to click.
    @Test("a track cannot be renamed to nothing")
    func renamingRejectsBlanks() {
        var document = EffectDocument()
        let track = document.addTrack(named: "Intro")

        document.rename(track.id, to: "   ")
        #expect(document.track(id: track.id)?.name == "Intro")

        document.rename(track.id, to: "  Chorus  ")
        #expect(document.track(id: track.id)?.name == "Chorus")
    }

    // ─── Ranges ──────────────────────────────────────────────────────────────

    @Test("the document's range covers every placed effect")
    func timeRangeSpansEverything() {
        // Effects at 0, 1000 and 2000, each 500 long.
        #expect(document(count: 3).timeRange == 0...2500)
    }

    @Test("an empty document has no range")
    func emptyRange() {
        #expect(EffectDocument().timeRange == nil)
    }

    @Test("an empty track has no range")
    func emptyTrackRange() {
        var document = EffectDocument()
        let track = document.addTrack()

        #expect(document.track(id: track.id)?.timeRange == nil)
    }
}

/// Moving a lane across the stack, in one edit.
///
/// Sending a track from one end of six to the other used to be five swaps, and
/// every swap is an edit the rest of the app answers — five evaluations of the
/// whole document to reach one arrangement nobody wanted to stop at.
@Suite("Track reordering")
struct TrackReorderTests {
    /// Six lanes, named so an assertion can read like the list looks.
    private func document() -> EffectDocument {
        var document = EffectDocument()
        for name in ["A", "B", "C", "D", "E", "F"] {
            let track = document.addTrack()
            document.rename(track.id, to: name)
        }
        return document
    }

    private func order(_ document: EffectDocument) -> [String] {
        document.tracks.map(\.name)
    }

    @Test("a track moves the whole way in one call")
    func movesAcrossTheStack() {
        var document = document()
        let front = document.tracks.last!.id

        document.moveTrack(front, toIndex: 0)

        #expect(order(document) == ["F", "A", "B", "C", "D", "E"])
    }

    @Test("moving to a middle position lands exactly there")
    func movesToTheMiddle() {
        var document = document()
        let first = document.tracks[0].id

        document.moveTrack(first, toIndex: 3)

        #expect(order(document) == ["B", "C", "D", "A", "E", "F"])
    }

    /// Clamped, so a caller can say "all the way up" without checking the count
    /// first — and an index past the end is a request to go as far as possible,
    /// not a mistake worth refusing.
    @Test("an index past either end clamps", arguments: [-5, 99])
    func clampsOutOfRange(index: Int) {
        var document = document()
        let middle = document.tracks[2].id

        document.moveTrack(middle, toIndex: index)

        #expect(document.tracks.count == 6, "no track was lost")
        let landed = document.tracks.firstIndex { $0.id == middle }
        #expect(landed == (index < 0 ? 0 : 5))
    }

    /// A move to where it already is must not disturb the list — a drag that
    /// returns to its starting row is a drag that did nothing.
    @Test("moving a track onto itself changes nothing")
    func movingInPlaceIsInert() {
        var document = document()
        let before = order(document)

        document.moveTrack(document.tracks[2].id, toIndex: 2)

        #expect(order(document) == before)
    }

    /// Asking from a row is asking for a lane *there*.
    ///
    /// One that appears at the far end ignores the gesture that summoned it,
    /// and leaves the author dragging it back to where they asked.
    @Test("a track added at an index lands there")
    func addsAtAPosition() {
        var document = document()

        let added = document.addTrack(named: "New", at: 2)

        #expect(order(document) == ["A", "B", "New", "C", "D", "E", "F"])
        #expect(document.tracks[2].id == added.id)
    }

    /// The default has to stay put: every caller that does not say where is
    /// asking for the behaviour that existed before an index was an option.
    @Test("adding without an index still appends")
    func addsOnTopByDefault() {
        var document = document()

        _ = document.addTrack(named: "New")

        #expect(order(document).last == "New")
    }

    /// The same result either way, so a drag and a menu command cannot disagree
    /// about what "send to back" means.
    @Test("one move matches the swaps it replaces")
    func matchesRepeatedSwaps() {
        var stepped = document()
        var moved = document()
        let id = stepped.tracks[4].id

        // Four steps down, the long way.
        for _ in 0 ..< 4 { stepped.lowerTrack(id) }
        moved.moveTrack(moved.tracks[4].id, toIndex: 0)

        #expect(order(stepped) == order(moved))
    }
}
