import StoryboardCore
import Testing

@testable import EditorShellFeature

@MainActor
@Suite("Effect tracks")
struct EffectTrackTests {
    private func model() -> EditorShellModel {
        EditorShellModel()
    }

    private var descriptor: EffectDescriptor { EmitterEffect.descriptor }

    /// A parsed storyboard with one sprite on each of two layers.
    private func parsedSprites() -> [PreparedSprite] {
        let sprites = [Layer.background, .foreground].map { layer in
            StoryboardSprite(
                id: "s-\(layer.rawValue)",
                layer: layer,
                origin: .centre,
                filePath: "a.png",
                defaultX: 0,
                defaultY: 0,
                commands: [
                    Command(easing: .linear, startTime: 0, endTime: 1000, payload: .fade(start: 0, end: 1)),
                ],
            )
        }
        return StoryboardResolver.prepare(sprites)
    }

    // ─── Placing ─────────────────────────────────────────────────────────────

    @Test("adding an effect opens a track and selects the effect")
    func addingCreatesATrack() {
        let shell = model()
        let node = shell.addEffect(descriptor, at: 1000, duration: 2000)

        #expect(shell.effects.tracks.count == 1)
        #expect(shell.selectedNodeID == node.id)
        #expect(shell.selectedEffect?.id == node.id)
        #expect(shell.selectedDescriptor?.type == descriptor.type)
    }

    /// The point of the model: several effects share a lane rather than each
    /// taking a row of its own.
    @Test("further effects land on the same track")
    func effectsShareALane() {
        let shell = model()
        shell.addEffect(descriptor, at: 0, duration: 1000)
        shell.addEffect(descriptor, at: 2000, duration: 1000)
        shell.addEffect(descriptor, at: 4000, duration: 1000)

        #expect(shell.effects.tracks.count == 1)
        #expect(shell.effects.tracks[0].nodes.count == 3)
    }

    @Test("a new effect lands on the selected track")
    func placingFollowsSelection() {
        let shell = model()
        shell.addEffect(descriptor, at: 0, duration: 1000)
        let second = shell.addTrack()

        let node = shell.addEffect(descriptor, at: 0, duration: 1000)

        #expect(shell.effects.trackID(of: node.id) == second.id)
    }

    /// The reason the button exists: two effects can only overlap on separate
    /// lanes, so making one and dropping into it has to work in that order.
    @Test("a new track receives the next effect")
    func newTrackTakesTheNextEffect() {
        let shell = model()
        let first = shell.addEffect(descriptor, at: 1000, duration: 3000)

        let lane = shell.addTrack()
        let second = shell.addEffect(descriptor, at: 1000, duration: 3000)

        #expect(shell.effects.trackID(of: second.id) == lane.id)
        #expect(shell.effects.trackID(of: first.id) != lane.id)

        // Overlapping in time, on different lanes — which is the point.
        #expect(shell.effects[first.id]?.timeRange == shell.effects[second.id]?.timeRange)
        #expect(shell.effects.tracks.count == 2)
    }

    /// Layer tracks are gone: they were a reading of a parsed `.osb`, useful
    /// while the app could only play one back. In an editor they are rows
    /// nobody can act on.
    @Test("loading a storyboard adds no tracks of its own")
    func loadingAddsNoLayerTracks() {
        let shell = model()
        let node = shell.addEffect(descriptor, at: 0, duration: 1000)

        shell.load(sprites: parsedSprites(), missingImagePaths: [])

        #expect(shell.effects.tracks.count == 1)
        #expect(shell.effects.tracks[0].nodes.map(\.id) == [node.id])
        // The assets panel still reads the storyboard, which is what it is for.
        #expect(!shell.assets.isEmpty)
    }

    @Test("removing an effect clears it from the selection")
    func removingAnEffect() {
        let shell = model()
        shell.addEffect(descriptor, at: 0, duration: 1000)
        let second = shell.addEffect(descriptor, at: 2000, duration: 1000)

        shell.removeEffect(second.id)

        #expect(shell.effects.nodes.count == 1)
        #expect(shell.selectedNodeID == nil)
    }

    // ─── Selection ───────────────────────────────────────────────────────────

    /// Clicking a row with one clip on it and getting an empty inspector is the
    /// wrong answer to an obvious question: there is exactly one thing there to
    /// edit.
    @Test("selecting a lane with one effect edits that effect")
    func laneWithOneEffectFallsThrough() {
        let shell = model()
        let node = shell.addEffect(descriptor, at: 0, duration: 1000)

        shell.selectedNodeID = nil
        shell.selectedTrackID = shell.effects.tracks[0].id

        #expect(shell.selectedEffect?.id == node.id)
        #expect(shell.selectedDescriptor != nil)
    }

    /// With several, there is no single effect to edit and picking one
    /// arbitrarily would be a guess. The lane itself is the selection.
    @Test("selecting a lane with several effects edits none of them")
    func laneWithManyEffectsShowsTheLane() {
        let shell = model()
        shell.addEffect(descriptor, at: 0, duration: 1000)
        shell.addEffect(descriptor, at: 2000, duration: 1000)

        shell.selectedNodeID = nil
        shell.selectedTrackID = shell.effects.tracks[0].id

        #expect(shell.selectedEffect == nil)
        #expect(shell.selectedTrack?.nodes.count == 2)
    }

    @Test("selecting a clip edits that clip, whatever else is on its lane")
    func selectingAClipWins() {
        let shell = model()
        shell.addEffect(descriptor, at: 0, duration: 1000)
        let second = shell.addEffect(descriptor, at: 2000, duration: 1000)

        shell.selectedNodeID = second.id

        #expect(shell.selectedEffect?.id == second.id)
    }

    // ─── Editing ─────────────────────────────────────────────────────────────

    @Test("changing a parameter re-evaluates the output")
    func parameterChangeUpdatesOutput() {
        let shell = model()
        let node = shell.addEffect(descriptor, at: 0, duration: 2000)

        shell.setValue(.integer(8), for: EmitterEffect.Param.count, on: node.id)
        #expect(shell.evaluateEffects().count == 8)

        shell.setValue(.integer(30), for: EmitterEffect.Param.count, on: node.id)
        #expect(shell.evaluateEffects().count == 30)
    }

    @Test("moving an effect keeps its length")
    func movingKeepsLength() {
        let shell = model()
        let node = shell.addEffect(descriptor, at: 1000, duration: 2000)

        shell.moveEffect(node.id, to: 5000)

        #expect(shell.effects[node.id]?.timeRange == 5000...7000)
    }

    @Test("an effect can be moved to another track")
    func movingBetweenTracks() {
        let shell = model()
        let node = shell.addEffect(descriptor, at: 0, duration: 1000)
        let destination = shell.addTrack()

        shell.moveEffect(node.id, toTrack: destination.id)

        #expect(shell.effects.trackID(of: node.id) == destination.id)
    }

    /// Hiding a lane hides what is on it — the only reading of the control that
    /// makes sense.
    @Test("hiding a track removes its effects from the output")
    func hidingATrack() {
        let shell = model()
        let node = shell.addEffect(descriptor, at: 0, duration: 2000)
        shell.setValue(.integer(10), for: EmitterEffect.Param.count, on: node.id)
        let trackID = shell.effects.tracks[0].id

        #expect(shell.evaluateEffects().count == 10)

        shell.toggleVisibility(of: trackID)
        #expect(shell.evaluateEffects().isEmpty)
    }

    @Test("removing a track removes what was on it")
    func removingATrack() {
        let shell = model()
        shell.addEffect(descriptor, at: 0, duration: 1000)
        let trackID = shell.effects.tracks[0].id

        shell.removeTrack(trackID)

        #expect(shell.effects.tracks.isEmpty)
        #expect(shell.evaluateEffects().isEmpty)
        #expect(shell.selectedNodeID == nil)
    }

    // ─── Draw order ──────────────────────────────────────────────────────────

    @Test("raising a track reorders the evaluated sprites")
    func reorderingReachesTheCanvas() {
        let shell = model()
        let first = shell.addEffect(descriptor, at: 0, duration: 2000)
        shell.addTrack()
        shell.addEffect(descriptor, at: 0, duration: 2000)

        #expect(shell.evaluateEffects().first?.id.hasPrefix(first.id) == true)

        shell.raiseTrack(shell.effects.tracks[0].id)
        #expect(shell.evaluateEffects().last?.id.hasPrefix(first.id) == true)
    }

    /// The bug this pins: the renderer keeps its own copy of the sprites on the
    /// GPU, uploaded once. Any change to the effects has to be observable, or
    /// the canvas cannot know to upload again.
    @Test("every change to the effects is observable")
    func everyChangeIsObservable() {
        let shell = model()
        var seen: Set<Int> = [shell.effectsRevision]

        let node = shell.addEffect(descriptor, at: 0, duration: 1000)
        seen.insert(shell.effectsRevision)

        shell.setValue(.integer(5), for: EmitterEffect.Param.count, on: node.id)
        seen.insert(shell.effectsRevision)

        shell.moveEffect(node.id, to: 2000)
        seen.insert(shell.effectsRevision)

        shell.resizeEffect(node.id, startTime: 2000, duration: 3000)
        seen.insert(shell.effectsRevision)

        shell.toggleVisibility(of: shell.effects.tracks[0].id)
        seen.insert(shell.effectsRevision)

        #expect(seen.count == 6)
    }

    /// The property the timeline drag relies on: moving a clip shifts the same
    /// particles rather than drawing new ones.
    @Test("dragging a clip shifts its sprites without changing them")
    func draggingShiftsOutput() {
        let shell = model()
        let node = shell.addEffect(descriptor, at: 0, duration: 2000)
        shell.setValue(.integer(6), for: EmitterEffect.Param.count, on: node.id)

        let before = shell.evaluateEffects()
        shell.moveEffect(node.id, to: 3000)
        let after = shell.evaluateEffects()

        #expect(before.count == after.count)
        for (original, moved) in zip(before, after) {
            #expect(original.defaultX == moved.defaultX)
            #expect(original.defaultY == moved.defaultY)
            for (a, b) in zip(original.commands, moved.commands) {
                #expect(b.startTime == a.startTime + 3000)
            }
        }
    }

    /// The timeline window has to cover effects placed past the storyboard, or
    /// the row drops them for being off screen — a clip vanishing mid-drag.
    @Test("the document range covers effects placed beyond the storyboard")
    func rangeGrowsWithPlacedEffects() {
        let shell = model()
        shell.load(sprites: parsedSprites(), missingImagePaths: [])
        let node = shell.addEffect(descriptor, at: 30_000, duration: 5000)

        #expect(shell.effects.timeRange?.upperBound == 35_000)
        #expect(shell.effects.timeRange?.contains(node.startTime) == true)
    }
}
