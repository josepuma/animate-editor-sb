import Foundation
import Testing
@testable import EditorShellFeature
@testable import StoryboardCore

/// Tallies how often each clip is evaluated.
private final class CameraRunCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    func record(_ name: String) {
        lock.lock()
        defer { lock.unlock() }
        counts[name, default: 0] += 1
    }

    var total: Int {
        lock.lock()
        defer { lock.unlock() }
        return counts.values.reduce(0, +)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        counts.removeAll()
    }
}

/// One sprite at the stage's centre for the clip's whole life, counted.
private struct CameraCountedEffect: Effect {
    static let descriptor = EffectDescriptor(
        type: "camera-counted", name: "Counted", category: .generate,
        systemImage: "number", parameters: [],
    )

    let counter: CameraRunCounter

    func evaluate(in context: EffectContext, rng _: inout EffectRandom) -> [StoryboardSprite] {
        counter.record(context.node.id)
        return [StoryboardSprite(
            id: context.node.id, layer: .foreground, origin: .centre, filePath: "counted.png",
            defaultX: 320, defaultY: 240,
            commands: [Command(easing: .linear, startTime: 0, endTime: context.duration,
                               payload: .fade(start: 1, end: 1))],
        )]
    }
}

/// Editing the storyboard camera from the shell.
///
/// The property that matters most here is one the picture cannot show: moving
/// the camera re-runs **no effect**. A clip's sprites are the same whatever the
/// camera does, and a project of fourteen scripts re-running every time a
/// camera key is nudged is the bug the evaluation cache exists to end.
@MainActor
@Suite("Camera editing")
struct CameraEditingTests {
    private func shell(_ counter: CameraRunCounter) -> EditorShellModel {
        EditorShellModel(library: EffectLibrary(effects: [CameraCountedEffect(counter: counter)]))
    }

    private func x(of sprites: [StoryboardSprite], at time: Double) throws -> Double {
        var states: [SpriteRenderState] = []
        StoryboardResolver.resolve(StoryboardResolver.prepare(sprites), at: time, into: &states)
        return try #require(states.first).x
    }

    @Test("moving the camera redraws without re-running any effect")
    func cameraRunsNoEffect() async throws {
        let counter = CameraRunCounter()
        let shell = shell(counter)
        _ = shell.addEffect(CameraCountedEffect.descriptor, at: 0)
        _ = shell.addEffect(CameraCountedEffect.descriptor, at: 0)
        await shell.awaitEvaluation()
        counter.reset()

        shell.setCameraKeyframe(320, for: .x, at: 0)
        await shell.awaitEvaluation()
        shell.setCameraKeyframe(420, for: .x, at: 1000)
        let sprites = await shell.settledSprites()

        #expect(counter.total == 0, "the camera re-ran effects \(counter.total) times")
        #expect(abs(try x(of: sprites, at: 1000) - 220) < 0.01, "the picture did not follow the camera")
    }

    @Test("changing whether a track follows the camera redraws without re-running any effect")
    func followingRunsNoEffect() async throws {
        let counter = CameraRunCounter()
        let shell = shell(counter)
        let node = shell.addEffect(CameraCountedEffect.descriptor, at: 0)
        shell.setCameraValue(420, for: .x)
        await shell.awaitEvaluation()
        counter.reset()

        let track = try #require(shell.effects.trackID(of: node.id))
        shell.setFollowsCamera(false, on: track)
        let sprites = await shell.settledSprites()

        #expect(counter.total == 0, "depth re-ran effects \(counter.total) times")
        #expect(abs(try x(of: sprites, at: 500) - 320) < 0.01, "a fixed track still followed the camera")
    }

    /// An input change and a camera edit waiting on the same pass.
    ///
    /// During a gesture evaluation holds off until the hand settles. An edit
    /// that names no clip — the song loading, a script saved on disk — is the
    /// one that has to drop every entry, because the cache cannot see it: the
    /// nodes compare equal while what they read has changed. A camera edit in
    /// the same pause must not wave that through as camera-only.
    ///
    /// A clip edit would not show this: the cache compares the node whole, so a
    /// resized clip misses by itself whether or not its entry was dropped.
    @Test("a camera edit in the same pause as an input change still re-runs the clips")
    func inputChangeSurvivesCameraEdit() async {
        let counter = CameraRunCounter()
        let shell = shell(counter)
        _ = shell.addEffect(CameraCountedEffect.descriptor, at: 0)
        await shell.awaitEvaluation()
        _ = shell.addEffect(CameraCountedEffect.descriptor, at: 0)
        await shell.awaitEvaluation()
        counter.reset()

        shell.beginGesture()
        shell.inputsChanged()
        shell.setCameraValue(400, for: .x)
        shell.endGesture()
        await shell.awaitEvaluation()

        // Exactly two: each clip once. Its tail is measured off the sprites
        // that same run produced — it used to cost a second run per clip. The
        // camera-only path runs none — so zero is the bug.
        #expect(counter.total == 2, "the input change ran clips \(counter.total) times, expected 2")
    }

    /// A camera edit is an edit: saved, undoable, and it still re-runs clips
    /// when the edit after it names one.
    @Test("a camera edit marks the project changed and undoes")
    func cameraUndoes() async {
        let shell = shell(CameraRunCounter())
        _ = shell.addEffect(CameraCountedEffect.descriptor, at: 0)
        await shell.awaitEvaluation()

        shell.setCameraValue(500, for: .x)
        #expect(shell.hasUnsavedChanges)
        #expect(shell.camera[value: .x] == 500)

        shell.undo()
        #expect(shell.camera == StoryboardCamera())
    }

    /// The first click on a stopwatch holds what the camera already showed.
    @Test("starting to animate plants a key holding the current value")
    func beginAnimatingHoldsValue() {
        let shell = shell(CameraRunCounter())
        shell.setCameraValue(1.5, for: .zoom)
        shell.beginAnimatingCamera(.zoom, at: 2000)
        let keys = shell.camera[.zoom].keyframes
        #expect(keys.count == 1)
        #expect(keys.first?.time == 2000 && keys.first?.value == 1.5)
    }

    /// Delete takes the narrowest thing selected. A camera key is narrower than
    /// any clip, and a selection this method cannot see makes Delete reach
    /// past it for something bigger — the bug this project has had twice.
    @Test("delete with a camera key selected removes the key, not the clip")
    func deleteRemovesCameraKey() throws {
        let shell = shell(CameraRunCounter())
        let node = shell.addEffect(CameraCountedEffect.descriptor, at: 0)
        shell.selectedNodeID = node.id
        shell.setCameraKeyframe(320, for: .x, at: 0)
        shell.setCameraKeyframe(520, for: .x, at: 1000)
        let key = try #require(shell.camera[.x].keyframes.last)

        shell.isEditingCamera = true
        shell.selectedCameraKeyframe = .init(property: .x, keyframeID: key.id)
        shell.deleteSelection()

        #expect(shell.camera[.x].keyframes.count == 1)
        #expect(shell.effects[node.id] != nil, "Delete destroyed the clip")
        #expect(shell.selectedCameraKeyframe == nil, "a deleted key is still selected")

        // And with nothing narrower selected, camera mode deletes nothing: the
        // clip is not what anyone editing the camera is aiming at.
        shell.deleteSelection()
        #expect(shell.effects[node.id] != nil, "Delete in camera mode destroyed the clip")
    }

    /// Camera mode and a clip's keyframe mode both own the timeline, so
    /// opening one closes the other.
    @Test("camera mode and a clip's keyframe mode replace each other")
    func modesAreExclusive() {
        let shell = shell(CameraRunCounter())
        let node = shell.addEffect(CameraCountedEffect.descriptor, at: 0)

        shell.keyframeNodeID = node.id
        shell.isEditingCamera = true
        #expect(shell.keyframeNodeID == nil)

        shell.keyframeNodeID = node.id
        #expect(!shell.isEditingCamera)
    }

    /// Switching animation off keeps where the camera was at that moment.
    @Test("switching animation off keeps the value at the playhead")
    func disableKeepsValue() {
        let shell = shell(CameraRunCounter())
        shell.setCameraKeyframe(320, for: .x, at: 0)
        shell.setCameraKeyframe(520, for: .x, at: 1000)
        shell.setCameraAnimationEnabled(false, for: .x, keeping: 500)
        #expect(!shell.camera[.x].isActive)
        #expect(shell.camera[.x].keyframes.count == 2, "the keys were thrown away")
        #expect(abs(shell.camera[value: .x] - 420) < 0.001)
    }
    // ─── The camera tool on the canvas ───────────────────────────────────────

    /// In camera mode the canvas shows the world, unmoved, with the camera's
    /// frame drawn over it — so the canvas must get the sprites *before* the
    /// camera. What is exported must not: the file is what the game shows.
    @Test("camera mode shows the canvas the world, and exports still carry the camera")
    func worldInCameraMode() async throws {
        let shell = shell(CameraRunCounter())
        _ = shell.addEffect(CameraCountedEffect.descriptor, at: 0)
        shell.setCameraValue(420, for: .x)
        await shell.awaitEvaluation()
        #expect(abs(try x(of: shell.evaluateEffects(), at: 500) - 220) < 0.01)

        var pushed: [StoryboardSprite] = []
        shell.onSpritesChanged = { pushed = $0 }
        shell.isEditingCamera = true
        await shell.awaitEvaluation()

        #expect(abs(try x(of: pushed, at: 500) - 320) < 0.01, "the canvas was not given the world")
        #expect(abs(try x(of: shell.evaluateEffects(), at: 500) - 320) < 0.01)
        #expect(abs(try x(of: await shell.settledSprites(), at: 500) - 220) < 0.01,
                "the export lost the camera")

        shell.isEditingCamera = false
        await shell.awaitEvaluation()
        #expect(abs(try x(of: pushed, at: 500) - 220) < 0.01, "leaving the mode kept the world on screen")
    }

    /// Dragging the frame with animation off moves where the camera rests.
    @Test("a frame drag with no animation sets the resting camera")
    func frameDragRests() {
        let shell = shell(CameraRunCounter())
        shell.applyCameraFrame(x: 400, y: 260, zoom: 1.5, at: 2000)
        #expect(shell.camera[value: .x] == 400)
        #expect(shell.camera[value: .y] == 260)
        #expect(shell.camera[value: .zoom] == 1.5)
        #expect(shell.camera[.x].isEmpty, "a key appeared on a property nobody animates")
    }

    /// Auto-key: with a stopwatch on, the drag plants a key at the playhead —
    /// and only on what changed, so panning does not put a zoom key down.
    @Test("a frame drag keys what is animated and changed, and nothing else")
    func frameDragKeys() {
        let shell = shell(CameraRunCounter())
        shell.setCameraKeyframe(320, for: .x, at: 0)
        shell.setCameraKeyframe(1, for: .zoom, at: 0)

        shell.applyCameraFrame(x: 500, y: 240, zoom: 1, at: 1500)

        #expect(shell.camera[.x].keyframes.map(\.time) == [0, 1500])
        #expect(shell.camera[.x].keyframes.last?.value == 500)
        #expect(shell.camera[.zoom].keyframes.count == 1, "an unchanged zoom was keyed")
        #expect(shell.camera[.y].isEmpty)
    }

    /// One drag, one undo step: all three properties land in a single edit.
    @Test("a frame drag is one undo step")
    func frameDragUndoes() {
        let shell = shell(CameraRunCounter())
        shell.applyCameraFrame(x: 400, y: 300, zoom: 2, at: 0)
        shell.undo()
        #expect(shell.camera == StoryboardCamera())
    }

    /// Dragging a point of the camera's path moves the keys at that moment.
    @Test("moving a path point moves the position keys at its time")
    func pathPointMoves() {
        let shell = shell(CameraRunCounter())
        shell.setCameraKeyframe(320, for: .x, at: 0)
        shell.setCameraKeyframe(520, for: .x, at: 1000)
        shell.setCameraKeyframe(240, for: .y, at: 1000)

        shell.moveCameraPathPoint(at: 1000, x: 600, y: 180)

        #expect(shell.camera[.x].keyframes.map(\.value) == [320, 600])
        #expect(shell.camera[.y].keyframes.map(\.value) == [180])
        #expect(shell.camera[.x].keyframes.map(\.time) == [0, 1000], "a key moved in time")
    }
    /// "View through camera" swaps the canvas to the finished picture without
    /// leaving camera mode — and without running a single effect, since both
    /// pictures are already in hand. Leaving the mode puts it back.
    @Test("viewing through the camera shows the finished picture and runs nothing")
    func viewThroughCamera() async throws {
        let counter = CameraRunCounter()
        let shell = shell(counter)
        _ = shell.addEffect(CameraCountedEffect.descriptor, at: 0)
        shell.setCameraValue(420, for: .x)
        shell.isEditingCamera = true
        await shell.awaitEvaluation()

        var pushed: [StoryboardSprite] = []
        shell.onSpritesChanged = { pushed = $0 }
        counter.reset()

        shell.isViewingThroughCamera = true
        #expect(abs(try x(of: pushed, at: 500) - 220) < 0.01, "the canvas did not switch to the camera's view")
        #expect(counter.total == 0, "switching views ran effects \(counter.total) times")

        shell.isViewingThroughCamera = false
        #expect(abs(try x(of: pushed, at: 500) - 320) < 0.01, "the canvas did not switch back to the world")

        shell.isViewingThroughCamera = true
        shell.isEditingCamera = false
        #expect(!shell.isViewingThroughCamera, "the view outlived the mode")
    }

    /// Turning the frame's handle keys the roll like any other property.
    @Test("a frame drag with a turn keys the rotation when it is animated")
    func frameDragRotates() {
        let shell = shell(CameraRunCounter())
        shell.setCameraKeyframe(0, for: .rotation, at: 0)
        shell.applyCameraFrame(x: 320, y: 240, zoom: 1, rotation: 30, at: 800)
        #expect(shell.camera[.rotation].keyframes.map(\.value) == [0, 30])
        #expect(shell.camera[.x].isEmpty && shell.camera[value: .x] == 320, "an unmoved pan was written")
    }

    /// A lane's depth is a camera edit: no clip re-runs for it.
    @Test("setting a track's depth redraws without re-running any effect")
    func depthRunsNoEffect() async throws {
        let counter = CameraRunCounter()
        let shell = shell(counter)
        let node = shell.addEffect(CameraCountedEffect.descriptor, at: 0)
        await shell.awaitEvaluation()
        counter.reset()

        let track = try #require(shell.effects.trackID(of: node.id))
        shell.setDepth(1000, on: track)
        let sprites = await shell.settledSprites()

        #expect(counter.total == 0, "depth re-ran effects \(counter.total) times")
        var states: [SpriteRenderState] = []
        StoryboardResolver.resolve(StoryboardResolver.prepare(sprites), at: 500, into: &states)
        #expect(abs((states.first?.scaleX ?? 0) - 0.5) < 0.001, "a lane one focal length back is not half size")
    }

    /// A camera edit re-runs no clip, so no clip shows a spinner — which left
    /// nothing at all saying the picture was still catching up. The camera
    /// says so itself, and stops saying so when the pass lands.
    @Test("a camera edit says it is being applied until the pass lands")
    func cameraShowsProgress() async {
        let shell = shell(CameraRunCounter())
        _ = shell.addEffect(CameraCountedEffect.descriptor, at: 0)
        await shell.awaitEvaluation()

        shell.setCameraValue(400, for: .x)
        #expect(shell.isApplyingCamera, "nothing said the camera was being applied")
        #expect(shell.evaluatingNodes.isEmpty, "a camera edit put spinners on clips it did not run")

        await shell.awaitEvaluation()
        #expect(!shell.isApplyingCamera, "the camera still says it is being applied")
    }
}
