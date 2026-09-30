import Foundation

/// What the storyboard's camera animates.
///
/// A closed list for the same reason `TransformProperty` is one: the timeline
/// lays these out without asking anything what it has.
///
/// Everything here is something osu! can draw exactly: a lane seen through a
/// perspective camera, as long as it stays parallel to the screen, is still
/// only a scale and a translation — so pan, dolly, focal length and roll all
/// reduce to commands the format already has. Orbiting the camera round a
/// scene is **not** here: it tilts the lanes, a tilted lane is a trapezoid,
/// and osu! has no way to draw one.
public enum CameraProperty: String, CaseIterable, Sendable {
    /// Where the camera looks, in storyboard units. 320 is the stage's centre.
    case x
    case y
    /// How far forward the camera has travelled — the dolly. A lane at Z 0 is
    /// a focal length in front of a camera at rest.
    case z
    /// A flat zoom on top of the perspective: the lens, not the travel.
    case zoom
    /// The roll, in degrees. The camera turning clockwise turns the world the
    /// other way.
    case rotation
    /// How strong the perspective is: a short focal length exaggerates depth,
    /// a long one flattens it. Animated against the dolly, it is the vertigo
    /// shot.
    case focal
    /// How much far lanes fade: 0 is none, 1 fades a lane three focal lengths
    /// back to nothing. The cheapest thing that sells distance.
    case fog

    public var title: String {
        switch self {
        case .x: "Camera X"
        case .y: "Camera Y"
        case .z: "Camera Z"
        case .zoom: "Zoom"
        case .rotation: "Rotation"
        case .focal: "Focal Length"
        case .fog: "Fog"
        }
    }

    public var defaultValue: Double {
        switch self {
        case .x: CameraTransform.centre.x
        case .y: CameraTransform.centre.y
        case .z: 0
        case .zoom: 1
        case .rotation: 0
        case .focal: 1000
        case .fog: 0
        }
    }

    public var unit: String? {
        switch self {
        case .x, .y, .z, .focal: "px"
        case .rotation: "°"
        case .zoom, .fog: nil
        }
    }

    public var range: ClosedRange<Double> {
        switch self {
        case .x: -400 ... 1100
        case .y: -300 ... 800
        case .z: -5000 ... 5000
        // Down to a tenth, not to zero: a zoom of zero collapses every sprite
        // onto one point and divides nothing useful.
        case .zoom: 0.1 ... 20
        case .rotation: -1080 ... 1080
        case .focal: 100 ... 5000
        case .fog: 0 ... 1
        }
    }

    public var step: Double {
        switch self {
        case .x, .y, .rotation: 1
        case .z, .focal: 10
        case .zoom, .fog: 0.05
        }
    }
}

/// The storyboard's camera: a view over the whole scene, keyed in song time.
///
/// **Not** `StageCamera`, which is the editor's magnifying glass and never
/// reaches the file. This one is part of the storyboard: it is baked into the
/// commands of every sprite that follows it, because osu! has no camera — the
/// camera moving right is every sprite moving left.
///
/// Keyed in **song** time, unlike a clip's transform. There is one camera for
/// the whole scene, so its keys belong to the song; keyed per clip, two clips
/// could disagree about where the camera is at the same moment.
///
/// Resting value and animation are kept apart exactly as `Transform` keeps
/// them, for the same reason: collapsed, scrubbing the timeline and typing a
/// number plants keys nobody asked for.
public struct StoryboardCamera: Sendable, Equatable, Codable {
    private var tracks: [String: KeyframeTrack]
    private var values: [String: Double]

    public init() {
        tracks = [:]
        values = [:]
    }

    private enum CodingKeys: String, CodingKey { case tracks, values }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tracks = try container.decodeIfPresent([String: KeyframeTrack].self, forKey: .tracks) ?? [:]
        values = try container.decodeIfPresent([String: Double].self, forKey: .values) ?? [:]
    }

    /// The resting value of a property — what it is when nothing animates it.
    public subscript(value property: CameraProperty) -> Double {
        get { values[property.rawValue] ?? property.defaultValue }
        set {
            // The default is the absence of a value, so a camera put back where
            // it started compares equal to one never touched — and is not
            // written to the file.
            if newValue == property.defaultValue {
                values.removeValue(forKey: property.rawValue)
            } else {
                values[property.rawValue] = newValue
            }
        }
    }

    public subscript(property: CameraProperty) -> KeyframeTrack {
        get { tracks[property.rawValue] ?? KeyframeTrack() }
        set {
            if newValue.isEmpty {
                tracks.removeValue(forKey: property.rawValue)
            } else {
                tracks[property.rawValue] = newValue
            }
        }
    }

    /// What a property is worth at a song time.
    public func value(_ property: CameraProperty, at time: Double) -> Double {
        let track = self[property]
        return track.isActive ? track.value(at: time) : self[value: property]
    }

    /// Whether anything moves over time.
    public var isAnimated: Bool {
        CameraProperty.allCases.contains { self[$0].isAnimated }
    }

    /// Whether the camera shows the stage exactly as the game would without it.
    public var isAtRest: Bool {
        CameraProperty.allCases.allSatisfy { property in
            let track = self[property]
            if track.isActive {
                return track.keyframes.allSatisfy { $0.value == property.defaultValue }
            }
            return self[value: property] == property.defaultValue
        }
    }

    /// Every song time a key sits on, for cutting commands where the camera
    /// changes course.
    var keyTimes: [Double] {
        CameraProperty.allCases.flatMap { self[$0].isActive ? self[$0].keyframes.map(\.time) : [] }
    }
}

/// Bakes the storyboard camera into the sprites of one track.
///
/// Runs last, after each clip has been evaluated and shifted into song time:
/// the camera's keys are in song time, so it is the one step of the pipeline
/// that works there. Kept out of `EffectEvaluator.evaluate(_ node:)` on
/// purpose — a clip's cached sprites are the same whatever the camera does,
/// so moving a camera key re-runs no effect, only this pass over the result.
///
/// ## The mapping
///
/// Every lane is a flat plane parallel to the screen, `z` units behind the
/// focal plane. Seen through a perspective camera, such a plane is only
/// scaled and moved — never skewed — which is exactly what a sprite can do:
///
/// ```
/// distance = focal + z − cameraZ
/// scale    = focal / distance · zoom
/// screen   = C + R(−roll) · (point − camera) · scale
/// ```
///
/// One distance gives both the size and the parallax, which is what makes a
/// far lane read as far away rather than merely slow. A lane at Z 0 with the
/// camera at rest is drawn exactly as it was.
public enum CameraTransform {
    /// The stage's centre in storyboard units — what a camera at rest looks at.
    public static let centre = (x: 320.0, y: 240.0)

    /// How many times a stretch may be halved when the result follows no
    /// curve the format can name — an arc of a roll, the `1/distance` of a
    /// dolly, two motions on different curves. Five halvings is 32 pieces at
    /// most, for the steepest dolly; a gentle curve stops at one.
    ///
    /// Adaptive, not a fixed count. Cutting every stretch into eight turned a
    /// field of 1,500 particles from 21,000 commands into 108,000 under a
    /// dolly: a particle with gravity is already eight stretches, so it came
    /// out as sixty-four pieces of a curve that, over thirty milliseconds, is
    /// a straight line. And eight was still not enough for a hard dolly —
    /// measured 1.2% off its curve. Cutting only where the line strays from
    /// the curve fixes both.
    private static let maximumHalvings = 5

    /// How close to the camera a lane may come, as a fraction of the focal
    /// length. Closer than this it is behind the lens, or so near it would be
    /// drawn at an absurd size, and is hidden instead.
    private static let nearPlane = 0.05

    /// How a lane is seen at one moment.
    struct View {
        var x: Double
        var y: Double
        /// Perspective and zoom together.
        var scale: Double
        /// The roll, in radians.
        var angle: Double
        /// Fog, and whether the lane is in front of the camera at all.
        var visibility: Double

        func map(_ px: Double, _ py: Double) -> (x: Double, y: Double) {
            let dx = (px - x) * scale
            let dy = (py - y) * scale
            // Turned the opposite way to the camera.
            let c = cos(-angle), s = sin(-angle)
            return (CameraTransform.centre.x + dx * c - dy * s, CameraTransform.centre.y + dx * s + dy * c)
        }

        /// Where a lane's point sits for the frame drawn on the canvas — the
        /// inverse of `map`.
        func unmap(_ sx: Double, _ sy: Double) -> (x: Double, y: Double) {
            let dx = sx - CameraTransform.centre.x
            let dy = sy - CameraTransform.centre.y
            let c = cos(angle), s = sin(angle)
            return (x + (dx * c - dy * s) / scale, y + (dx * s + dy * c) / scale)
        }
    }

    static func view(of camera: StoryboardCamera, at time: Double, z: Double) -> View {
        view(z: z) { camera.value($0, at: time) }
    }

    /// The one place the mapping is written, fed by whoever holds the values.
    private static func view(z: Double, value: (CameraProperty) -> Double) -> View {
        let focal = max(value(.focal), 1)
        let distance = focal + z - value(.z)
        let near = focal * nearPlane
        let depth = min(max((distance - focal) / (3 * focal), 0), 1)
        return View(
            x: value(.x),
            y: value(.y),
            scale: focal / max(distance, near) * value(.zoom),
            angle: value(.rotation) * .pi / 180,
            visibility: distance <= near ? 0 : 1 - value(.fog) * depth,
        )
    }

    /// The camera, read fast, for one lane's pass.
    ///
    /// Reading the camera through its own API costs a dictionary lookup on a
    /// string key per property per question, and a lane of 1,500 particles
    /// asks hundreds of thousands of questions — measured, that was most of
    /// the time the bake took, far more than resolving the sprites. The tracks
    /// are taken out once, the key times worked out once, and each view is
    /// remembered for every sprite of the lane: they mostly ask about the same
    /// moments.
    final class Sampler {
        let z: Double
        let keyTimes: [Double]
        private let tracks: [KeyframeTrack?]
        private let resting: [Double]
        private var memo: [Double: View] = [:]

        init(camera: StoryboardCamera, z: Double) {
            self.z = z
            tracks = CameraProperty.allCases.map { camera[$0].isActive ? camera[$0] : nil }
            resting = CameraProperty.allCases.map { camera[value: $0] }
            keyTimes = Set(camera.keyTimes).sorted()
        }

        private static let index = Dictionary(
            uniqueKeysWithValues: CameraProperty.allCases.enumerated().map { ($1, $0) },
        )

        func value(_ property: CameraProperty, at time: Double) -> Double {
            let slot = Self.index[property]!
            return tracks[slot]?.value(at: time) ?? resting[slot]
        }

        func easing(of property: CameraProperty, at time: Double) -> Easing {
            tracks[Self.index[property]!]?.keyframes.last { $0.time <= time + 0.5 }?.easing ?? .linear
        }

        func view(at time: Double) -> View {
            if let known = memo[time] { return known }
            let made = CameraTransform.view(z: z) { value($0, at: time) }
            memo[time] = made
            return made
        }
    }

    /// The sprites of one lane, as the camera sees them.
    ///
    /// - Parameters:
    ///   - z: how far behind the focal plane the lane sits.
    ///   - followsCamera: `false` for a lane fixed to the screen — lyrics, a
    ///     HUD — which the camera leaves exactly as it is.
    /// - Returns: the sprites untouched when nothing would change them — a
    ///   camera nobody touched over a lane nobody moved has to cost exactly
    ///   nothing, or every existing project changes under it.
    public static func apply(
        _ camera: StoryboardCamera,
        to sprites: [StoryboardSprite],
        z: Double = 0,
        followsCamera: Bool = true,
    ) -> [StoryboardSprite] {
        guard followsCamera, !(camera.isAtRest && z == 0) else { return sprites }

        guard camera.isAnimated else {
            let still = view(of: camera, at: 0, z: z)
            // A still view without a roll is affine per axis, so every command
            // maps exactly and keeps its own curve. A roll mixes the axes, and
            // an `_MX` can no longer say where the sprite goes — the general
            // path works that out from the sprite as drawn.
            if still.angle == 0 {
                return sprites.map { placed($0, through: still) }
            }
            let sampler = Sampler(camera: camera, z: z)
            return sprites.map { followed($0, sampler: sampler) }
        }
        let sampler = Sampler(camera: camera, z: z)
        return sprites.map { followed($0, sampler: sampler) }
    }

    // ─── A still, unrolled camera ────────────────────────────────────────────

    private static func placed(_ sprite: StoryboardSprite, through view: View) -> StoryboardSprite {
        var result = sprite
        let origin = view.map(sprite.defaultX, sprite.defaultY)
        result.defaultX = origin.x
        result.defaultY = origin.y
        result.commands = sprite.commands.map { mapped($0, through: view) }
        // Exact for a loop too: its body is relative in time, not in space.
        result.loops = sprite.loops.map { loop in
            var moved = loop
            moved.commands = loop.commands.map { mapped($0, through: view) }
            return moved
        }
        let life = life(of: sprite) ?? 0 ... 0
        if view.scale != 1, !has(sprite, where: isScale) {
            result.commands.append(Command(
                easing: .linear, startTime: life.lowerBound, endTime: life.lowerBound,
                payload: .scale(start: view.scale, end: view.scale),
            ))
        }
        if view.visibility != 1, !has(sprite, where: { $0.kind == .fade }) {
            result.commands.append(Command(
                easing: .linear, startTime: life.lowerBound, endTime: life.upperBound,
                payload: .fade(start: view.visibility, end: view.visibility),
            ))
        }
        return result
    }

    /// One command through a still view. A roll is applied to a full move;
    /// `_MX`/`_MY` are mapped per axis, which is exact only unrolled — the
    /// caller sends rolled sprites down the general path for that reason, and
    /// only a loop body, which cannot follow anything, lands here rolled.
    private static func mapped(_ command: Command, through view: View) -> Command {
        switch command.payload {
        case let .move(sx, sy, ex, ey):
            let a = view.map(sx, sy), b = view.map(ex, ey)
            return Command(timing: command.timing, payload: .move(startX: a.x, startY: a.y, endX: b.x, endY: b.y))
        case let .moveX(start, end):
            return Command(timing: command.timing, payload: .moveX(
                start: centre.x + (start - view.x) * view.scale, end: centre.x + (end - view.x) * view.scale,
            ))
        case let .moveY(start, end):
            return Command(timing: command.timing, payload: .moveY(
                start: centre.y + (start - view.y) * view.scale, end: centre.y + (end - view.y) * view.scale,
            ))
        case let .scale(start, end):
            return Command(timing: command.timing, payload: .scale(start: start * view.scale, end: end * view.scale))
        case let .vectorScale(sx, sy, ex, ey):
            return Command(timing: command.timing, payload: .vectorScale(
                startX: sx * view.scale, startY: sy * view.scale, endX: ex * view.scale, endY: ey * view.scale,
            ))
        case let .rotate(start, end):
            return Command(timing: command.timing, payload: .rotate(start: start - view.angle, end: end - view.angle))
        case let .fade(start, end):
            return view.visibility == 1 ? command
                : Command(timing: command.timing, payload: .fade(start: start * view.visibility, end: end * view.visibility))
        default:
            return command
        }
    }

    // ─── A camera on the move, or rolled ─────────────────────────────────────

    /// A sprite carried through the camera, channel by channel.
    ///
    /// Each channel — position, size, turn, opacity — is the sprite's own
    /// value combined with the camera's. Cut at every place either changes
    /// course, most stretches have only one of them moving, and then the
    /// result is that one curve, exactly, with its own easing. Only a stretch
    /// where the result follows no curve the format can name is sampled.
    ///
    /// Loops are carried with the view at the moment each loop starts: a
    /// loop's body repeats identically, so it cannot follow a camera that
    /// keeps moving — a limit of the format, not an approximation chosen here.
    private static func followed(_ sprite: StoryboardSprite, sampler: Sampler) -> StoryboardSprite {
        guard let life = life(of: sprite) else {
            return placed(sprite, through: sampler.view(at: 0))
        }

        // Read off the sprite as the resolver draws it, loops left out: they
        // are carried separately and would otherwise be baked into the very
        // path they override.
        var bare = sprite
        bare.loops = []
        let prepared = StoryboardResolver.prepare([bare]).first

        // Remembered per instant. Every stretch asks about its ends, its
        // middle and its quarters, in every channel, and each component of a
        // position asks again — measured, that was most of a second for a
        // field of 1,500 particles in a debug build, spent resolving the same
        // moments over and over.
        var ownMemo: [Double: SpriteRenderState] = [:]
        func own(_ time: Double) -> SpriteRenderState? {
            if let known = ownMemo[time] { return known }
            guard let prepared else { return nil }
            let state = StoryboardResolver.state(of: prepared, at: time)
            ownMemo[time] = state
            return state
        }
        func lens(_ time: Double) -> View { sampler.view(at: time) }

        /// Whether the camera changes one aspect of the view over this
        /// sprite's life — checked at its ends, at every camera key inside it
        /// and between them, which is everywhere a keyframed value can turn.
        func cameraVaries(_ aspect: (View) -> Double) -> Bool {
            let keys = sampler.keyTimes.filter { life.contains($0) }
            let marks = Set([life.lowerBound, life.upperBound] + keys).sorted()
            let reference = aspect(lens(life.lowerBound))
            var checks = marks
            for (a, b) in zip(marks, marks.dropFirst()) { checks.append((a + b) / 2) }
            return checks.contains { abs(aspect(lens($0)) - reference) > 1e-9 }
        }
        let still = lens(life.lowerBound)

        let cameraCuts = Set(sampler.keyTimes.filter { life.contains($0) })
        var result = sprite

        // ── Position ──
        func position(_ time: Double) -> (x: Double, y: Double) {
            own(time).map { ($0.x, $0.y) } ?? (sprite.defaultX, sprite.defaultY)
        }
        func screen(_ time: Double) -> (x: Double, y: Double) {
            let where_ = position(time)
            return lens(time).map(where_.x, where_.y)
        }
        let start = screen(life.lowerBound)
        result.defaultX = start.x
        result.defaultY = start.y

        let ownMoves = sprite.commands.filter { [.move, .moveX, .moveY].contains($0.kind) }
        let moves = channel(
            life: life,
            cuts: cameraCuts.union(ownMoves.flatMap { [$0.startTime, $0.endTime] }),
            ownMoving: { a, b in varies({ position($0).x }, a, b) || varies({ position($0).y }, a, b) },
            cameraMoving: { a, b in
                varies({ lens($0).x }, a, b) || varies({ lens($0).y }, a, b)
                    || varies({ lens($0).scale }, a, b) || varies({ lens($0).angle }, a, b)
            },
            curve: { a, b, ownMoving, cameraMoving in
                let lensStill = !varies({ lens($0).scale }, a, b) && !varies({ lens($0).angle }, a, b)
                if lensStill {
                    // Linear in the point and in the pan: two moves sharing a
                    // curve add up to one move with it.
                    var curves: [Easing?] = []
                    if ownMoving { curves.append(easing(of: ownMoves, across: a ... b)) }
                    if cameraMoving { curves.append(panEasing(sampler, from: a, to: b)) }
                    guard let first = curves.first, let curve = first, curves.allSatisfy({ $0 == curve })
                    else { return nil }
                    return curve
                }
                // Only the zoom moving, over a still sprite and pan: linear in
                // the zoom, so the zoom's own curve.
                let panStill = !varies({ lens($0).x }, a, b) && !varies({ lens($0).y }, a, b)
                if !ownMoving, panStill, !varies({ lens($0).angle }, a, b), onlyZoomScales(sampler, a, b) {
                    return sampler.easing(of: .zoom, at: a)
                }
                return nil
            },
            make: { easing, a, b in
                let from = screen(a), to = screen(b)
                return Command(easing: easing, startTime: a, endTime: b,
                               payload: .move(startX: from.x, startY: from.y, endX: to.x, endY: to.y))
            },
            sample: { let at = screen($0); return [at.x, at.y] },
            // Half a storyboard pixel: under what the eye can place.
            tolerance: 0.5,
        )
        result.commands.removeAll { [.move, .moveX, .moveY].contains($0.kind) }
        result.commands += moves

        // ── Size ──
        //
        // Only rebuilt when the camera changes the scale over this life. A
        // pan leaves it alone, and a still factor multiplies the sprite's own
        // commands exactly — no resolving, no new commands.
        if !cameraVaries(\.scale) {
            let factor = View(x: 0, y: 0, scale: still.scale, angle: 0, visibility: 1)
            result.commands = result.commands.map { isScale($0) ? mapped($0, through: factor) : $0 }
            if still.scale != 1, !sprite.commands.contains(where: isScale) {
                result.commands.append(Command(
                    easing: .linear, startTime: life.lowerBound, endTime: life.lowerBound,
                    payload: .scale(start: still.scale, end: still.scale),
                ))
            }
        } else {
        let ownScales = sprite.commands.filter(isScale)
        func size(_ time: Double) -> (x: Double, y: Double) {
            own(time).map { ($0.scaleX, $0.scaleY) } ?? (1, 1)
        }
        let scales = channel(
            life: life,
            cuts: cameraCuts.union(ownScales.flatMap { [$0.startTime, $0.endTime] }),
            ownMoving: { a, b in varies({ size($0).x }, a, b) || varies({ size($0).y }, a, b) },
            cameraMoving: { a, b in varies({ lens($0).scale }, a, b) },
            curve: { a, b, ownMoving, cameraMoving in
                switch (ownMoving, cameraMoving) {
                case (true, false): easing(of: ownScales, across: a ... b)
                case (false, true): onlyZoomScales(sampler, a, b) ? sampler.easing(of: .zoom, at: a) : nil
                default: nil
                }
            },
            make: { easing, a, b in
                let from = size(a), to = size(b)
                let fa = lens(a).scale, fb = lens(b).scale
                // `_S` while the sprite's own scale is uniform, `_V` once it is
                // not: a vector says two numbers where one would do.
                let uniform = abs(from.x - from.y) < 1e-9 && abs(to.x - to.y) < 1e-9
                return Command(easing: easing, startTime: a, endTime: b, payload: uniform
                    ? .scale(start: from.x * fa, end: to.x * fb)
                    : .vectorScale(startX: from.x * fa, startY: from.y * fa, endX: to.x * fb, endY: to.y * fb))
            },
            sample: { let value = size($0), factor = lens($0).scale; return [value.x * factor, value.y * factor] },
            // Half a percent of a sprite drawn at its own size.
            tolerance: 0.005,
            hold: { at in
                let value = size(at), factor = lens(at).scale
                guard abs(value.x * factor - 1) > 1e-9 || abs(value.y * factor - 1) > 1e-9 else { return nil }
                return Command(easing: .linear, startTime: at, endTime: at, payload: abs(value.x - value.y) < 1e-9
                    ? .scale(start: value.x * factor, end: value.x * factor)
                    : .vectorScale(startX: value.x * factor, startY: value.y * factor,
                                   endX: value.x * factor, endY: value.y * factor))
            },
        )
        result.commands.removeAll(where: isScale)
        result.commands += scales
        }

        // ── Turn ──
        //
        // A roll that holds still is an offset on every turn the sprite makes.
        if !cameraVaries(\.angle) {
            let offset = View(x: 0, y: 0, scale: 1, angle: still.angle, visibility: 1)
            result.commands = result.commands.map { $0.kind == .rotate ? mapped($0, through: offset) : $0 }
            if still.angle != 0, !sprite.commands.contains(where: { $0.kind == .rotate }) {
                result.commands.append(Command(
                    easing: .linear, startTime: life.lowerBound, endTime: life.lowerBound,
                    payload: .rotate(start: -still.angle, end: -still.angle),
                ))
            }
        } else {
        let ownTurns = sprite.commands.filter { $0.kind == .rotate }
        func turn(_ time: Double) -> Double { own(time)?.rotation ?? 0 }
        let turns = channel(
            life: life,
            cuts: cameraCuts.union(ownTurns.flatMap { [$0.startTime, $0.endTime] }),
            ownMoving: { a, b in varies(turn, a, b) },
            cameraMoving: { a, b in varies({ lens($0).angle }, a, b) },
            curve: { a, b, ownMoving, cameraMoving in
                switch (ownMoving, cameraMoving) {
                case (true, false): easing(of: ownTurns, across: a ... b)
                // Linear in the roll, so a roll's own curve is exact here —
                // unlike the path, which a roll bends into an arc.
                case (false, true): sampler.easing(of: .rotation, at: a)
                default: nil
                }
            },
            make: { easing, a, b in
                Command(easing: easing, startTime: a, endTime: b,
                        payload: .rotate(start: turn(a) - lens(a).angle, end: turn(b) - lens(b).angle))
            },
            sample: { [turn($0) - lens($0).angle] },
            // A third of a degree.
            tolerance: 0.006,
            hold: { at in
                let value = turn(at) - lens(at).angle
                guard abs(value) > 1e-12 else { return nil }
                return Command(easing: .linear, startTime: at, endTime: at, payload: .rotate(start: value, end: value))
            },
        )
        result.commands.removeAll { $0.kind == .rotate }
        result.commands += turns
        }

        // ── Opacity ──
        //
        // With no fog moving and nothing crossing the lens, the visibility is
        // one factor — usually exactly 1, which leaves the fades untouched.
        if !cameraVaries(\.visibility) {
            let dimmed = View(x: 0, y: 0, scale: 1, angle: 0, visibility: still.visibility)
            result.commands = result.commands.map { $0.kind == .fade ? mapped($0, through: dimmed) : $0 }
            if still.visibility != 1, !sprite.commands.contains(where: { $0.kind == .fade }) {
                result.commands.append(Command(
                    easing: .linear, startTime: life.lowerBound, endTime: life.upperBound,
                    payload: .fade(start: still.visibility, end: still.visibility),
                ))
            }
        } else {
        let ownFades = sprite.commands.filter { $0.kind == .fade }
        func opacity(_ time: Double) -> Double { own(time)?.opacity ?? 1 }
        let fades = channel(
            life: life,
            cuts: cameraCuts.union(ownFades.flatMap { [$0.startTime, $0.endTime] }),
            ownMoving: { a, b in varies(opacity, a, b) },
            cameraMoving: { a, b in varies({ lens($0).visibility }, a, b) },
            curve: { a, b, ownMoving, cameraMoving in
                ownMoving && !cameraMoving ? easing(of: ownFades, across: a ... b) : nil
            },
            make: { easing, a, b in
                Command(easing: easing, startTime: a, endTime: b, payload: .fade(
                    start: opacity(a) * lens(a).visibility, end: opacity(b) * lens(b).visibility,
                ))
            },
            sample: { [opacity($0) * lens($0).visibility] },
            tolerance: 0.01,
            // Every stretch held, not only the moving ones: a sprite's life is
            // read from its commands, and the fade is very often the one that
            // spans it — skip a still stretch and the sprite dies early.
            holdsStill: true,
        )
        result.commands.removeAll { $0.kind == .fade }
        result.commands += fades
        }

        result.loops = sprite.loops.map { loop in
            var moved = loop
            let framing = lens(loop.startTime)
            moved.commands = loop.commands.map { mapped($0, through: framing) }
            return moved
        }
        return result
    }

    /// Rebuilds one channel over a sprite's life.
    ///
    /// - Parameters:
    ///   - curve: the one curve a stretch follows, or `nil` to sample it.
    ///   - hold: what to write when nothing moved at all but the value is
    ///     not the default — a sprite with no command for a channel draws it
    ///     at its default, so a still camera that changes it has to say so.
    ///   - holdsStill: write still stretches too, for a channel whose commands
    ///     are what keeps the sprite alive.
    ///   - sample: the channel's value at a moment, as numbers, and
    ///   - tolerance: how far a straight piece may stray from them before the
    ///     stretch is halved again — in the channel's own units.
    private static func channel(
        life: ClosedRange<Double>,
        cuts: Set<Double>,
        ownMoving: (Double, Double) -> Bool,
        cameraMoving: (Double, Double) -> Bool,
        curve: (Double, Double, Bool, Bool) -> Easing?,
        make: (Easing, Double, Double) -> Command,
        sample: (Double) -> [Double],
        tolerance: Double,
        hold: ((Double) -> Command?)? = nil,
        holdsStill: Bool = false,
    ) -> [Command] {
        let bounds = cuts.union([life.lowerBound, life.upperBound]).filter { life.contains($0) }.sorted()
        var commands: [Command] = []

        for (from, to) in zip(bounds, bounds.dropFirst()) where to > from {
            let isOwn = ownMoving(from, to)
            let isCamera = cameraMoving(from, to)

            // Nothing moves: a command holds its end value after it and the
            // first one's start value before it, so a still stretch needs
            // nothing written — unless the channel keeps the sprite alive.
            guard isOwn || isCamera else {
                if holdsStill { commands.append(make(.linear, from, to)) }
                continue
            }

            if let exact = curve(from, to, isOwn, isCamera) {
                commands.append(make(exact, from, to))
                continue
            }
            pieces(from, to, halvings: 0, into: &commands)
        }

        /// Straight pieces through the real values, halving a stretch only
        /// while the line through its ends strays from the curve.
        func pieces(_ a: Double, _ b: Double, halvings: Int, into commands: inout [Command]) {
            if halvings < maximumHalvings, strays(a, b) {
                let middle = (a + b) / 2
                pieces(a, middle, halvings: halvings + 1, into: &commands)
                pieces(middle, b, halvings: halvings + 1, into: &commands)
            } else {
                commands.append(make(.linear, a, b))
            }
        }

        /// Checked at three points, not one: an S-shaped stretch can cross its
        /// own chord exactly in the middle and still be far from it elsewhere.
        func strays(_ a: Double, _ b: Double) -> Bool {
            let start = sample(a), end = sample(b)
            for fraction in [0.25, 0.5, 0.75] {
                let actual = sample(a + (b - a) * fraction)
                for index in actual.indices where index < start.count && index < end.count {
                    let line = start[index] + (end[index] - start[index]) * fraction
                    if abs(actual[index] - line) > tolerance { return true }
                }
            }
            return false
        }

        // A sprite with a life of a single instant, or one that never moves.
        if commands.isEmpty {
            if holdsStill {
                commands.append(make(.linear, life.lowerBound, life.upperBound))
            } else if let hold, let command = hold(life.lowerBound) {
                commands.append(command)
            }
        }
        return commands
    }

    // ─── Reading ─────────────────────────────────────────────────────────────

    /// Whether a value changes across a stretch — checked at both ends and in
    /// the middle, so something that leaves and comes back is not missed.
    private static func varies(_ value: (Double) -> Double, _ from: Double, _ to: Double) -> Bool {
        let a = value(from)
        return abs(value(to) - a) > 1e-9 || abs(value((from + to) / 2) - a) > 1e-9
    }

    /// Whether the lens's scale moves only because the zoom does — the one
    /// case it follows a curve the format has. Perspective is `1/distance`,
    /// which no easing draws.
    private static func onlyZoomScales(_ camera: Sampler, _ from: Double, _ to: Double) -> Bool {
        !varies({ camera.value(.z, at: $0) }, from, to) && !varies({ camera.value(.focal, at: $0) }, from, to)
    }

    /// The span a sprite exists over, its loops included.
    private static func life(of sprite: StoryboardSprite) -> ClosedRange<Double>? {
        var starts = sprite.commands.map(\.startTime)
        var ends = sprite.commands.map(\.endTime)
        for loop in sprite.loops {
            let body = loop.commands.map(\.endTime).max() ?? 0
            starts.append(loop.startTime)
            ends.append(loop.startTime + body * Double(max(1, loop.loopCount)))
        }
        guard let start = starts.min(), let end = ends.max() else { return nil }
        return start ... max(start, end)
    }

    private static func isScale(_ command: Command) -> Bool {
        command.kind == .scale || command.kind == .vectorScale
    }

    private static func has(_ sprite: StoryboardSprite, where test: (Command) -> Bool) -> Bool {
        sprite.commands.contains(where: test) || sprite.loops.contains { $0.commands.contains(where: test) }
    }

    /// The single curve the sprite's own commands follow across a stretch, or
    /// `nil` when two with different curves share it.
    private static func easing(of commands: [Command], across span: ClosedRange<Double>) -> Easing? {
        let covering = commands.filter {
            $0.startTime <= span.lowerBound + 1e-6 && $0.endTime >= span.upperBound - 1e-6 && $0.endTime > $0.startTime
        }
        guard let first = covering.first else { return nil }
        return covering.allSatisfy { $0.easing == first.easing } ? first.easing : nil
    }

    /// The pan's curve across a stretch: whichever axis moves, or `nil` when
    /// both move on different curves.
    private static func panEasing(_ camera: Sampler, from: Double, to: Double) -> Easing? {
        let moving = [CameraProperty.x, .y].filter { camera.value($0, at: from) != camera.value($0, at: to) }
        let curves = Set(moving.map { camera.easing(of: $0, at: from) })
        return curves.count == 1 ? curves.first : nil
    }
}

extension StoryboardCamera {
    /// What the camera sees of the lane at Z 0, as four corners in its world
    /// — the shape the canvas draws over the unmoved scene. Clockwise from the
    /// top left; a rolled camera gives a turned rectangle.
    public struct Frame: Sendable, Equatable {
        public var corners: [(x: Double, y: Double)]

        public var minX: Double { corners.map(\.x).min() ?? 0 }
        public var maxX: Double { corners.map(\.x).max() ?? 0 }
        public var minY: Double { corners.map(\.y).min() ?? 0 }
        public var maxY: Double { corners.map(\.y).max() ?? 0 }

        public static func == (lhs: Frame, rhs: Frame) -> Bool {
            lhs.corners.count == rhs.corners.count
                && zip(lhs.corners, rhs.corners).allSatisfy { $0.x == $1.x && $0.y == $1.y }
        }
    }

    /// The frame at a moment, for the lane at Z 0.
    ///
    /// The mapping `CameraTransform` bakes in, run backwards from the stage's
    /// corners — the same `View`, not a second description of it, so the
    /// frame and the picture cannot disagree.
    ///
    /// - Parameter stage: the stage's horizontal extent — `−107...747` on a
    ///   widescreen storyboard, `0...640` on a 4:3 one. The height is 480.
    public func frame(at time: Double, stage: ClosedRange<Double>) -> Frame {
        let view = CameraTransform.view(of: self, at: time, z: 0)
        return Frame(corners: [
            view.unmap(stage.lowerBound, 0),
            view.unmap(stage.upperBound, 0),
            view.unmap(stage.upperBound, 480),
            view.unmap(stage.lowerBound, 480),
        ])
    }

    /// Where the camera stands at each of its position keys, in time order.
    ///
    /// A key on either axis counts: a key on X alone is still a moment the
    /// camera is somewhere, and dragging that point is how its place changes.
    public var pathPoints: [(time: Double, x: Double, y: Double)] {
        var times = Set<Double>()
        for property in [CameraProperty.x, .y] where self[property].isActive {
            times.formUnion(self[property].keyframes.map(\.time))
        }
        return times.sorted().map { ($0, value(.x, at: $0), value(.y, at: $0)) }
    }

    /// The curve leaving the key that governs `time`.
    func easing(of property: CameraProperty, at time: Double) -> Easing {
        self[property].keyframes.last { $0.time <= time + 0.5 }?.easing ?? .linear
    }
}
