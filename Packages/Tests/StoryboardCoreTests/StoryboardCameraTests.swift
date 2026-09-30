import Foundation
import Testing

@testable import StoryboardCore

/// The storyboard's camera: a view baked into every sprite that follows it.
///
/// osu! has no camera, so the camera moving right is every sprite moving left
/// in its own commands. Every check here reads the picture through the
/// resolver — where a sprite *is* at a moment — rather than the numbers the
/// camera wrote, because a camera that writes plausible commands and puts the
/// sprite in the wrong place is the failure that matters.
@Suite("Storyboard camera")
struct StoryboardCameraTests {
    // ─── Helpers ─────────────────────────────────────────────────────────────

    /// A sprite resting at a point, alive over `life`, doing nothing else.
    private func still(
        at x: Double, _ y: Double,
        life: ClosedRange<Double> = 0 ... 2000,
        id: String = "s",
    ) -> StoryboardSprite {
        StoryboardSprite(
            id: id, layer: .foreground, origin: .centre, filePath: "sb/dot.png",
            defaultX: x, defaultY: y,
            commands: [Command(easing: .linear, startTime: life.lowerBound, endTime: life.upperBound,
                               payload: .fade(start: 1, end: 1))],
        )
    }

    private func state(_ sprites: [StoryboardSprite], at time: Double, id: String = "s") throws -> SpriteRenderState {
        var states: [SpriteRenderState] = []
        StoryboardResolver.resolve(StoryboardResolver.prepare(sprites), at: time, into: &states)
        return try #require(states.first { $0.spriteId == id }, "nothing drawn for \(id) at \(time)")
    }

    private func camera(
        x: [(Double, Double)] = [], y: [(Double, Double)] = [], zoom: [(Double, Double)] = [],
        z: [(Double, Double)] = [], rotation: [(Double, Double)] = [],
        easing: Easing = .linear,
    ) -> StoryboardCamera {
        var camera = StoryboardCamera()
        camera[.z] = KeyframeTrack(z.map { Keyframe(time: $0.0, value: $0.1, easing: easing) })
        camera[.rotation] = KeyframeTrack(rotation.map { Keyframe(time: $0.0, value: $0.1, easing: easing) })
        camera[.x] = KeyframeTrack(x.map { Keyframe(time: $0.0, value: $0.1, easing: easing) })
        camera[.y] = KeyframeTrack(y.map { Keyframe(time: $0.0, value: $0.1, easing: easing) })
        camera[.zoom] = KeyframeTrack(zoom.map { Keyframe(time: $0.0, value: $0.1, easing: easing) })
        return camera
    }

    // ─── At rest ─────────────────────────────────────────────────────────────

    /// The promise every existing project rests on: a camera nobody touched
    /// changes nothing, sprite for sprite and command for command.
    @Test("a camera at rest leaves the sprites exactly as they were")
    func restIsIdentity() {
        let sprites = [still(at: 100, 50), still(at: 400, 300, id: "t")]
        let out = CameraTransform.apply(StoryboardCamera(), to: sprites)
        #expect(String(describing: out) == String(describing: sprites))
    }

    /// A lane that does not follow the camera is fixed to the screen: lyrics
    /// and a HUD stay put whatever the camera does.
    @Test("a track that does not follow the camera ignores it")
    func notFollowingIsFixed() {
        let sprites = [still(at: 100, 50)]
        var moved = StoryboardCamera()
        moved[value: .x] = 500
        moved[value: .zoom] = 3
        moved[value: .rotation] = 30
        let out = CameraTransform.apply(moved, to: sprites, z: 800, followsCamera: false)
        #expect(String(describing: out) == String(describing: sprites))
    }

    // ─── Holding still ───────────────────────────────────────────────────────

    /// Looking right moves the world left.
    @Test("a camera looking right moves a sprite left")
    func staticPan() throws {
        var camera = StoryboardCamera()
        camera[value: .x] = 420
        let out = CameraTransform.apply(camera, to: [still(at: 320, 240)])
        #expect(abs(try state(out, at: 1000).x - 220) < 0.001)
    }

    /// Zooming in doubles distances from the centre and the sprite's size.
    @Test("zooming in pushes a sprite away from the centre and grows it")
    func staticZoom() throws {
        var camera = StoryboardCamera()
        camera[value: .zoom] = 2
        let out = CameraTransform.apply(camera, to: [still(at: 420, 240)])
        let now = try state(out, at: 1000)
        #expect(abs(now.x - 520) < 0.001)
        #expect(abs(now.scaleX - 2) < 0.001 && abs(now.scaleY - 2) < 0.001)
    }

    /// A sprite's own motion is carried, not replaced.
    @Test("under a still camera a moving sprite keeps its path and curve")
    func staticCarriesMotion() throws {
        var sprite = still(at: 0, 0)
        sprite.commands.append(Command(easing: .quadOut, startTime: 0, endTime: 1000,
                                       payload: .move(startX: 320, startY: 240, endX: 420, endY: 240)))
        var camera = StoryboardCamera()
        camera[value: .zoom] = 2
        let out = CameraTransform.apply(camera, to: [sprite])
        let moves = out[0].commands.filter { $0.kind == .move }
        #expect(moves.count == 1)
        #expect(moves.first?.easing == .quadOut)
        #expect(abs(try state(out, at: 1000).x - 520) < 0.001)
    }

    // ─── Moving ──────────────────────────────────────────────────────────────

    /// The camera's keys are in song time, and a sprite held still is carried
    /// through them — including after the last key, where the view holds.
    @Test("an animated pan carries a still sprite through song time")
    func animatedPan() throws {
        let cam = camera(x: [(0, 320), (1000, 520)])
        let out = CameraTransform.apply(cam, to: [still(at: 320, 240)])
        #expect(abs(try state(out, at: 500).x - 220) < 0.01)
        #expect(abs(try state(out, at: 1000).x - 120) < 0.01)
        #expect(abs(try state(out, at: 1500).x - 120) < 0.01)
    }

    /// One key span, one command, with the key's own curve. Sampling a curve
    /// and writing it as linear pieces throws the curve away and costs eight
    /// commands where one would do.
    @Test("a pan over a still sprite is one command carrying the key's curve")
    func panKeepsEasing() {
        let cam = camera(x: [(0, 320), (1000, 520)], easing: .quadOut)
        let out = CameraTransform.apply(cam, to: [still(at: 320, 240)])
        let moves = out[0].commands.filter { $0.kind == .move }
        #expect(moves.count == 1, "\(moves.count) moves")
        #expect(moves.first?.easing == .quadOut)
    }

    @Test("an animated zoom grows the sprite and carries it outward")
    func animatedZoom() throws {
        let cam = camera(zoom: [(0, 1), (1000, 2)])
        let out = CameraTransform.apply(cam, to: [still(at: 420, 240)])
        let now = try state(out, at: 500)
        #expect(abs(now.scaleX - 1.5) < 0.01, "scale \(now.scaleX)")
        #expect(abs(now.x - 470) < 0.01, "x \(now.x)")
    }

    /// A sprite following the camera exactly stays where it was on screen —
    /// the two motions compose rather than one replacing the other.
    @Test("a sprite moving with the camera holds still on screen")
    func motionComposes() throws {
        var sprite = still(at: 0, 0)
        sprite.commands.append(Command(easing: .linear, startTime: 0, endTime: 1000,
                                       payload: .move(startX: 320, startY: 240, endX: 420, endY: 240)))
        let cam = camera(x: [(0, 320), (1000, 420)])
        let out = CameraTransform.apply(cam, to: [sprite])
        for time in [250.0, 500, 750, 1000] {
            #expect(abs(try state(out, at: time).x - 320) < 0.5, "drifted at \(time)")
        }
    }

    /// A sprite's own scale is a size; the zoom is a factor on it.
    @Test("an animated zoom multiplies the scale a sprite already has")
    func zoomMultipliesScale() throws {
        var sprite = still(at: 320, 240)
        sprite.commands.append(Command(easing: .linear, startTime: 0, endTime: 0,
                                       payload: .vectorScale(startX: 4, startY: 0.5, endX: 4, endY: 0.5)))
        let cam = camera(zoom: [(0, 1), (1000, 2)])
        let out = CameraTransform.apply(cam, to: [sprite])
        let now = try state(out, at: 1000)
        #expect(abs(now.scaleX - 8) < 0.01 && abs(now.scaleY - 1) < 0.01, "\(now.scaleX)×\(now.scaleY)")
    }

    // ─── Depth ───────────────────────────────────────────────────────────────

    /// Parallax: the same camera moves a far track by less.
    /// Perspective: a lane one focal length back is half the size and moves
    /// half as far when the camera pans — both from one distance, which is
    /// what makes it read as far away rather than just slow.
    @Test("a lane one focal length back is half size and moves half as far")
    func perspectiveParallax() throws {
        let cam = camera(x: [(0, 320), (1000, 520)])
        let near = CameraTransform.apply(cam, to: [still(at: 320, 240)])
        let far = CameraTransform.apply(cam, to: [still(at: 320, 240)], z: 1000)
        let nearShift = try state(near, at: 1000).x - 320
        let farShift = try state(far, at: 1000).x - 320
        #expect(abs(farShift - nearShift / 2) < 0.01, "\(farShift) against \(nearShift)")
        #expect(abs(try state(far, at: 1000).scaleX - 0.5) < 0.001)
    }

    /// A dolly: moving the camera forward grows a near lane faster than a far
    /// one — the thing a flat zoom cannot do, and what reads as travelling
    /// through the layers.
    @Test("dollying in grows near lanes faster than far ones")
    func dolly() throws {
        let cam = camera(z: [(0, 0), (1000, 500)])
        let near = CameraTransform.apply(cam, to: [still(at: 320, 240)])
        let far = CameraTransform.apply(cam, to: [still(at: 320, 240)], z: 3000)
        let nearGrowth = try state(near, at: 1000).scaleX / state(near, at: 0).scaleX
        let farGrowth = try state(far, at: 1000).scaleX / state(far, at: 0).scaleX
        #expect(abs(nearGrowth - 2) < 0.01, "near grew \(nearGrowth)×")
        #expect(abs(farGrowth - 4000.0 / 3500) < 0.01, "far grew \(farGrowth)×")
        // Through the middle too, not just at the keys: the curve is 1/d, which
        // no easing draws, so the path is cut into pieces that follow it.
        let expected = 1000.0 / (1000 - 250)
        #expect(abs(try state(near, at: 500).scaleX - expected) < 0.02, "mid-dolly scale")
    }

    /// A lane the camera has passed is not drawn at all — past the lens it
    /// would come back mirrored and enormous.
    @Test("a lane behind the camera is hidden")
    func behindCamera() throws {
        var camera = StoryboardCamera()
        camera[value: .z] = 1500
        let out = CameraTransform.apply(camera, to: [still(at: 320, 240)])
        var states: [SpriteRenderState] = []
        StoryboardResolver.resolve(StoryboardResolver.prepare(out), at: 500, into: &states)
        #expect(states.allSatisfy { $0.opacity < 0.001 }, "a lane behind the camera still drew")
    }

    /// Roll: the camera turning clockwise turns the world the other way, both
    /// where each sprite is and which way it faces.
    @Test("rolling the camera turns the world the other way")
    func roll() throws {
        var camera = StoryboardCamera()
        camera[value: .rotation] = 90
        let out = CameraTransform.apply(camera, to: [still(at: 420, 240)])
        let now = try state(out, at: 500)
        #expect(abs(now.x - 320) < 0.001 && abs(now.y - 140) < 0.001, "(\(now.x), \(now.y))")
        #expect(abs(now.rotation - -Double.pi / 2) < 0.001, "faces \(now.rotation)")
    }

    /// An animated roll carries a sprite round an arc, not along the chord —
    /// the middle of a quarter turn is on the circle.
    @Test("an animated roll carries a sprite along the arc")
    func animatedRoll() throws {
        let cam = camera(rotation: [(0, 0), (1000, 90)])
        let out = CameraTransform.apply(cam, to: [still(at: 420, 240)])
        let middle = try state(out, at: 500)
        let radius = hypot(middle.x - 320, middle.y - 240)
        #expect(abs(radius - 100) < 1.5, "the path cut the corner: radius \(radius)")
        #expect(abs(middle.rotation - -Double.pi / 4) < 0.01)
    }

    /// A pan and a roll together: each is linear in its own terms, but the
    /// sprite is carried round a turning, travelling centre — neither the
    /// pan's curve nor a straight line. The middle of the move is off the
    /// chord by tens of pixels.
    @Test("a pan and a roll together are followed, not flattened into a line")
    func panWithRoll() throws {
        let cam = camera(x: [(0, 320), (1000, 420)], rotation: [(0, 0), (1000, 90)])
        let out = CameraTransform.apply(cam, to: [still(at: 420, 240)])
        let middle = try state(out, at: 500)
        let expected = (x: 320 + 50 * cos(Double.pi / 4), y: 240 - 50 * sin(Double.pi / 4))
        #expect(abs(middle.x - expected.x) < 1 && abs(middle.y - expected.y) < 1,
                "(\(middle.x), \(middle.y)) against (\(expected.x), \(expected.y))")
    }

    /// Fog dims a lane by how far it is, and not at all at the focal plane.
    @Test("fog dims far lanes and leaves the near one alone")
    func fog() throws {
        var camera = StoryboardCamera()
        camera[value: .fog] = 0.8
        let near = try state(CameraTransform.apply(camera, to: [still(at: 320, 240)]), at: 500)
        let far = try state(CameraTransform.apply(camera, to: [still(at: 320, 240)], z: 3000), at: 500)
        #expect(abs(near.opacity - 1) < 0.001)
        #expect(abs(far.opacity - 0.2) < 0.001, "far opacity \(far.opacity)")
    }

    // ─── The document ────────────────────────────────────────────────────────

    /// Evaluating a document runs its tracks through the camera, each at its
    /// own depth — and a clip placed later in the song meets the camera where
    /// the song is, not where its own clip starts.
    @Test("a document is seen through its camera, each track at its depth")
    func documentUsesCamera() throws {
        func image(_ id: String, at start: Double) -> EffectNode {
            EffectNode(id: id, type: ImageEffect.descriptor.type, name: id,
                       startTime: start, duration: 2000, seed: 1,
                       values: ImageEffect.descriptor.defaultValues.merging(
                           [ImageEffect.Param.sprite: .text("sb/bg.png")],
                       ) { $1 })
        }
        var document = EffectDocument(tracks: [
            EffectTrack(id: "near", name: "Near", nodes: [image("a", at: 0)]),
            EffectTrack(id: "hud", name: "HUD", nodes: [image("b", at: 1000)], followsCamera: false),
        ])
        document.camera = camera(x: [(0, 320), (1000, 420)])

        let sprites = EffectEvaluator().evaluate(document)
        let near = try #require(sprites.first { $0.id.hasPrefix("a") }?.id)
        let hud = try #require(sprites.first { $0.id.hasPrefix("b") }?.id)
        #expect(abs(try state(sprites, at: 1500, id: near).x - 220) < 0.01)
        #expect(abs(try state(sprites, at: 1500, id: hud).x - 320) < 0.01)
    }

    /// A project written before the camera opens with the camera at rest and
    /// every track at Z 0, following it — and one written after keeps both.
    @Test("the camera and depth survive a save, and old files open without them")
    func codable() throws {
        let old = #"{"tracks":[{"id":"t","name":"T","layer":"Foreground","nodes":[],"isVisible":true,"isLocked":false}]}"#
        let opened = try JSONDecoder().decode(EffectDocument.self, from: Data(old.utf8))
        #expect(opened.camera == StoryboardCamera())
        #expect(opened.tracks.first?.z == 0)
        #expect(opened.tracks.first?.followsCamera == true)

        var document = opened
        document.camera = camera(x: [(0, 320), (1000, 520)], zoom: [(500, 1.5)])
        document.tracks[0].z = 400
        document.tracks[0].followsCamera = false
        let reopened = try JSONDecoder().decode(EffectDocument.self, from: JSONEncoder().encode(document))
        #expect(reopened.camera == document.camera)
        #expect(reopened.tracks.first?.z == 400)
        #expect(reopened.tracks.first?.followsCamera == false)
    }

    /// Nothing to write for a camera nobody touched: an unchanged project must
    /// save to the same bytes it did before the camera existed.
    @Test("a camera at rest, Z 0 and following are not written")
    func restIsNotWritten() throws {
        let document = EffectDocument(tracks: [EffectTrack(id: "t", name: "T")])
        let text = String(decoding: try JSONEncoder().encode(document), as: UTF8.self)
        #expect(!text.contains("camera"))
        #expect(!text.contains("\"z\""))
        #expect(!text.contains("followsCamera"))
    }
    // ─── The frame drawn on the canvas ───────────────────────────────────────

    /// What the camera sees, in stage units: the stage shrunk by the zoom and
    /// centred where the camera looks. This is the rectangle the canvas draws
    /// over the unmoved world, so it has to be exactly what ends up on screen.
    @Test("the frame is the stage divided by the zoom, centred on the camera")
    func frameRect() {
        var camera = StoryboardCamera()
        camera[value: .zoom] = 2
        let frame = camera.frame(at: 0, stage: 0 ... 640)
        #expect(frame.minX == 160 && frame.maxX == 480)
        #expect(frame.minY == 120 && frame.maxY == 360)

        // A widescreen stage starts left of zero.
        var panned = StoryboardCamera()
        panned[value: .x] = 420
        let wide = panned.frame(at: 0, stage: -107 ... 747)
        #expect(abs(wide.minX - -7) < 1e-9 && abs(wide.maxX - 847) < 1e-9)
    }

    /// The frame and the picture agree: a sprite at a frame corner lands at
    /// the stage corner once the camera is baked in.
    @Test("a sprite at a frame corner lands at the stage corner")
    func frameMatchesPicture() throws {
        var camera = StoryboardCamera()
        camera[value: .x] = 400
        camera[value: .y] = 200
        camera[value: .zoom] = 1.6
        let frame = camera.frame(at: 0, stage: -107 ... 747)
        let out = CameraTransform.apply(camera, to: [still(at: frame.minX, frame.minY)])
        let now = try state(out, at: 500)
        #expect(abs(now.x - -107) < 1e-6 && abs(now.y) < 1e-6, "(\(now.x), \(now.y))")
    }

    /// Where the camera stands at each of its position keys, for drawing its
    /// path on the canvas. Keys on either axis count — a key on X alone is
    /// still a moment the camera is somewhere.
    @Test("the path points are the camera's place at every position key")
    func pathPoints() throws {
        let cam = camera(x: [(0, 320), (1000, 520)], y: [(500, 240), (1000, 300)])
        let points = cam.pathPoints
        // Required first, so a missing point fails here rather than killing
        // the runner on an index below — a suite that dies leaves nothing to
        // read.
        try #require(points.count == 3, "\(points.count) points")
        #expect(points.map(\.time) == [0, 500, 1000])
        #expect(points[1].x == 420 && points[1].y == 240)
        #expect(points[2].x == 520 && points[2].y == 300)
    }

    /// A rolled camera's frame is rolled with it, and still lands exactly on
    /// the stage's corners once baked.
    @Test("a rolled frame's corner lands on the stage's corner")
    func rolledFrame() throws {
        var camera = StoryboardCamera()
        camera[value: .rotation] = 25
        camera[value: .zoom] = 1.4
        camera[value: .x] = 360
        let frame = camera.frame(at: 0, stage: -107 ... 747)
        let corner = frame.corners[2]
        let out = CameraTransform.apply(camera, to: [still(at: corner.x, corner.y)])
        let now = try state(out, at: 500)
        #expect(abs(now.x - 747) < 1e-6 && abs(now.y - 480) < 1e-6, "(\(now.x), \(now.y))")
    }

    /// Stepping back from a legacy file: a parallax factor becomes the Z that
    /// pans the same, and 0 — "fixed to the screen" — becomes not following.
    @Test("a track saved with a parallax depth opens at the equivalent Z")
    func legacyDepth() throws {
        let saved = #"{"id":"t","name":"T","layer":"Foreground","nodes":[],"isVisible":true,"isLocked":false,"depth":0.5}"#
        let track = try JSONDecoder().decode(EffectTrack.self, from: Data(saved.utf8))
        #expect(abs(track.z - 1000) < 1e-9)
        let hud = #"{"id":"t","name":"T","layer":"Foreground","nodes":[],"isVisible":true,"isLocked":false,"depth":0}"#
        #expect(try JSONDecoder().decode(EffectTrack.self, from: Data(hud.utf8)).followsCamera == false)
    }

    /// A dolly's curve is `1/distance`, which no easing draws, so it is cut
    /// into straight pieces — but only as many as the curve needs. A short
    /// stretch of a gentle curve is one piece; cutting every stretch into
    /// eight multiplied a particle field's file five times over.
    @Test("a dolly is cut only where the curve needs it, and still lands on it")
    func adaptiveSampling() throws {
        // Gentle: a small dolly over a long clip.
        let gentle = camera(z: [(0, 0), (8000, 100)])
        let short = still(at: 420, 240, life: 1000 ... 1200)
        let out = CameraTransform.apply(gentle, to: [short])
        let moves = out[0].commands.filter { $0.kind == .move }
        let scales = out[0].commands.filter { $0.kind == .scale || $0.kind == .vectorScale }
        #expect(moves.count <= 1 && scales.count <= 1, "\(moves.count) moves, \(scales.count) scales for 200ms of a gentle dolly")

        // Steep: a hard dolly still follows its curve closely.
        let steep = camera(z: [(0, 0), (1000, 800)])
        let long = CameraTransform.apply(steep, to: [still(at: 420, 240)])
        for time in stride(from: 50.0, through: 950, by: 50) {
            let expected = 1000 / (1000 - 800 * time / 1000)
            let drawn = try state(long, at: time).scaleX
            #expect(abs(drawn - expected) / expected < 0.01, "scale off the curve at \(time): \(drawn) vs \(expected)")
        }
    }
}
