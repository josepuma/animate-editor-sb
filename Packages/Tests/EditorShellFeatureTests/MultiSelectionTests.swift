import StoryboardCore
import Testing

@testable import EditorShellFeature

/// Twenty lyric clips moved one at a time are twenty drags, and twenty chances
/// for one of them to land a beat off the rest.
@MainActor
@Suite("Multi-selection")
struct MultiSelectionTests {
    /// Three clips at 0, 2000 and 5000 ms, a second long each.
    private func shellWithClips() throws -> (EditorShellModel, [EffectNode.ID]) {
        let shell = EditorShellModel()
        let ids = try [0.0, 2000, 5000].map { start in
            try #require(shell.addEffect(ShapeEffect.descriptor, at: start, duration: 1000).id)
        }
        return (shell, ids)
    }

    // ─── Selecting ───────────────────────────────────────────────────────────

    /// Every place that selects one clip still does: a plain click, a paste,
    /// an arrow key. A plain selection replacing the set is what keeps them
    /// from leaving a stale group behind.
    @Test("selecting one clip replaces the set")
    func singleSelectionReplaces() throws {
        let (shell, ids) = try shellWithClips()
        shell.toggleNodeSelection(ids[0])
        shell.toggleNodeSelection(ids[1])

        shell.selectedNodeID = ids[2]

        #expect(shell.selectedNodeIDs == [ids[2]])
    }

    @Test("toggling adds a clip and makes it the one the inspector shows")
    func toggleAdds() throws {
        let (shell, ids) = try shellWithClips()
        shell.selectedNodeID = ids[0]

        shell.toggleNodeSelection(ids[1])

        #expect(shell.selectedNodeIDs == [ids[0], ids[1]])
        #expect(shell.selectedNodeID == ids[1])
    }

    /// Taking the inspected clip out of the group cannot leave the inspector
    /// describing something no longer selected.
    @Test("toggling the inspected clip off hands the inspector to another")
    func toggleRemovesPrimary() throws {
        let (shell, ids) = try shellWithClips()
        shell.selectedNodeID = ids[0]
        shell.toggleNodeSelection(ids[1])

        shell.toggleNodeSelection(ids[1])

        #expect(shell.selectedNodeIDs == [ids[0]])
        #expect(shell.selectedNodeID == ids[0])
    }

    @Test("toggling the last clip off clears the selection")
    func toggleToEmpty() throws {
        let (shell, ids) = try shellWithClips()
        shell.selectedNodeID = ids[0]

        shell.toggleNodeSelection(ids[0])

        #expect(shell.selectedNodeIDs.isEmpty)
        #expect(shell.selectedNodeID == nil)
    }

    @Test("select all takes every clip, on every lane")
    func selectAll() throws {
        let (shell, ids) = try shellWithClips()
        let lane = shell.addTrack()
        let other = shell.addEffect(ShapeEffect.descriptor, at: 0, on: lane.id)

        shell.selectAllClips()

        #expect(shell.selectedNodeIDs == Set(ids + [other.id]))
        #expect(shell.selectedNodeID != nil)
    }

    /// The canvas measures and previews whatever this reports, so it has to
    /// hear about the whole group, not just the clip the inspector shows.
    @Test("the canvas is told the whole set")
    func callbackGetsTheSet() throws {
        let (shell, ids) = try shellWithClips()
        var reported: Set<EffectNode.ID> = []
        shell.onSelectionChanged = { reported = $0 }

        shell.selectedNodeID = ids[0]
        shell.toggleNodeSelection(ids[1])

        #expect(reported == [ids[0], ids[1]])
    }

    @Test("a removed clip leaves the selection")
    func removalPrunes() throws {
        let (shell, ids) = try shellWithClips()
        shell.selectedNodeID = ids[0]
        shell.toggleNodeSelection(ids[1])

        shell.removeEffect(ids[1])

        #expect(shell.selectedNodeIDs == [ids[0]])
    }

    // ─── Editing the group ───────────────────────────────────────────────────

    @Test("delete removes the whole group, and one undo brings it back")
    func deleteGroup() throws {
        let (shell, ids) = try shellWithClips()
        shell.selectedNodeID = ids[0]
        shell.toggleNodeSelection(ids[1])

        shell.deleteSelection()

        #expect(shell.effects[ids[0]] == nil)
        #expect(shell.effects[ids[1]] == nil)
        #expect(shell.effects[ids[2]] != nil)
        #expect(shell.selectedNodeIDs.isEmpty)

        shell.undo()
        #expect(shell.effects[ids[0]] != nil)
        #expect(shell.effects[ids[1]] != nil)
    }

    @Test("duplicate copies the whole group and selects the copies")
    func duplicateGroup() throws {
        let (shell, ids) = try shellWithClips()
        shell.selectedNodeID = ids[0]
        shell.toggleNodeSelection(ids[1])
        let before = shell.effects.nodes.count

        shell.duplicateSelection()

        #expect(shell.effects.nodes.count == before + 2)
        #expect(shell.selectedNodeIDs.count == 2)
        #expect(shell.selectedNodeIDs.isDisjoint(with: ids))
    }

    @Test("moving the group shifts every clip by the same amount, in one undo")
    func moveGroup() throws {
        let (shell, ids) = try shellWithClips()
        shell.selectedNodeID = ids[1]
        shell.toggleNodeSelection(ids[2])

        shell.moveSelection(by: 250)

        #expect(shell.effects[ids[0]]?.startTime == 0)
        #expect(shell.effects[ids[1]]?.startTime == 2250)
        #expect(shell.effects[ids[2]]?.startTime == 5250)

        shell.undo()
        #expect(shell.effects[ids[1]]?.startTime == 2000)
        #expect(shell.effects[ids[2]]?.startTime == 5000)
    }

    /// Clamping each clip on its own would squash the group together against
    /// zero — the spacing between them is the point of moving them as one.
    @Test("a group stops as a whole at zero, keeping its spacing")
    func moveGroupClampsAsOne() throws {
        let (shell, ids) = try shellWithClips()
        shell.selectedNodeID = ids[1]
        shell.toggleNodeSelection(ids[2])

        shell.moveSelection(by: -9000)

        #expect(shell.effects[ids[1]]?.startTime == 0)
        #expect(shell.effects[ids[2]]?.startTime == 3000)
    }

    @Test("a locked clip in the group stays put")
    func lockedStays() throws {
        let (shell, ids) = try shellWithClips()
        let lane = shell.addTrack()
        let locked = shell.addEffect(ShapeEffect.descriptor, at: 7000, on: lane.id)
        shell.toggleLock(of: lane.id)

        shell.selectedNodeID = ids[0]
        shell.toggleNodeSelection(locked.id)
        shell.moveSelection(by: 500)

        #expect(shell.effects[ids[0]]?.startTime == 500)
        #expect(shell.effects[locked.id]?.startTime == 7000)
    }

    // ─── On the canvas ───────────────────────────────────────────────────────

    private func placedPair() throws -> (EditorShellModel, EffectNode.ID, EffectNode.ID) {
        let shell = EditorShellModel()
        let a = try #require(shell.addImage(at: "a.png", time: 0))
        let b = try #require(shell.addImage(at: "b.png", time: 0))
        shell.setTransformValue(100, for: .x, on: a.id)
        shell.setTransformValue(300, for: .x, on: b.id)
        shell.setTransformValue(240, for: .y, on: a.id)
        shell.setTransformValue(240, for: .y, on: b.id)
        // The box around both, centred on x 200.
        shell.selectionBounds = { ClipBounds(minX: 50, minY: 190, maxX: 350, maxY: 290) }
        shell.selectedNodeID = a.id
        shell.toggleNodeSelection(b.id)
        return (shell, a.id, b.id)
    }

    @Test("a canvas drag moves every selected clip")
    func canvasMovesGroup() throws {
        let (shell, a, b) = try placedPair()

        shell.applyCanvasDrag(dx: 40, dy: -10, scaleX: 1, scaleY: 1, isFinished: true, at: 0)

        #expect(shell.effects[a]?.transform[value: .x] == 140)
        #expect(shell.effects[b]?.transform[value: .x] == 340)
        #expect(shell.effects[a]?.transform[value: .y] == 230)
        #expect(shell.effects[b]?.transform[value: .y] == 230)
    }

    /// Scaled each about its own position, two clips grow into each other;
    /// about the group's centre they spread apart, which is what the frame
    /// around both showed while the hand was down.
    @Test("a canvas scale grows the group about its centre")
    func canvasScalesAboutGroupCentre() throws {
        let (shell, a, b) = try placedPair()

        shell.applyCanvasDrag(dx: 0, dy: 0, scaleX: 2, scaleY: 2, isFinished: true, at: 0)

        #expect(shell.effects[a]?.transform[value: .x] == 0)
        #expect(shell.effects[b]?.transform[value: .x] == 400)
        #expect(shell.effects[a]?.transform[value: .scaleX] == 2)
        #expect(shell.effects[b]?.transform[value: .scaleX] == 2)
    }

    @Test("a canvas turn swings the group about its centre")
    func canvasRotatesAboutGroupCentre() throws {
        let (shell, a, b) = try placedPair()

        shell.applyCanvasDrag(dx: 0, dy: 0, scaleX: 1, scaleY: 1, rotation: 90, isFinished: true, at: 0)

        // Clockwise on screen, y down: (−100, 0) from the centre turns to (0, −100).
        let ax = try #require(shell.effects[a]?.transform[value: .x])
        let ay = try #require(shell.effects[a]?.transform[value: .y])
        #expect(abs(ax - 200) < 1e-9)
        #expect(abs(ay - 140) < 1e-9)
        let by = try #require(shell.effects[b]?.transform[value: .y])
        #expect(abs(by - 340) < 1e-9)
        #expect(shell.effects[a]?.transform[value: .rotation] == 90)
    }

    /// The grip marks one clip's position. With a group there is no one
    /// position to mark, so the canvas falls back to the box's centre.
    @Test("a group has no single origin")
    func noOriginForGroup() throws {
        let (shell, _, _) = try placedPair()
        #expect(shell.clipOrigin == nil)
    }

    @Test("aligning moves the group as one")
    func alignGroup() throws {
        let (shell, a, b) = try placedPair()

        shell.align(.left)

        // The box's left edge (50) goes to the stage's (−107).
        #expect(shell.effects[a]?.transform[value: .x] == -57)
        #expect(shell.effects[b]?.transform[value: .x] == 143)
    }
}
