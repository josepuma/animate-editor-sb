import Foundation
import Testing

@testable import StoryboardCore

/// The emitter's spawn shape.
///
/// Geometry is the one part of a particle system a test can actually judge:
/// whether a ring is round is arithmetic, while whether fire looks like fire
/// is not.
@Suite("Emitter shape")
struct EmitterShapeTests {
    private func offsets(
        _ shape: EmitterEffect.Shape,
        halfWidth: Double = 100,
        halfHeight: Double = 100,
        count: Int = 400,
    ) -> [(x: Double, y: Double, phase: Double, tilt: Double)] {
        var rng = EffectRandom(seed: 7)
        return (0 ..< count).map { _ in
            EmitterEffect.spawnOffset(
                shape: shape, halfWidth: halfWidth, halfHeight: halfHeight, rng: &rng,
            )
        }
    }

    @Test("a point emitter puts everything in one place")
    func pointIsAPoint() {
        #expect(offsets(.point).allSatisfy { $0.x == 0 && $0.y == 0 })
    }

    /// The whole reason the shape exists: on a ring every particle is on the
    /// edge, which is what a rectangle can never be made to do.
    @Test("a ring puts every particle on the edge")
    func ringIsHollow() {
        for offset in offsets(.ring) {
            let radius = (offset.x * offset.x + offset.y * offset.y).squareRoot()
            #expect(abs(radius - 100) < 0.001)
        }
    }

    /// A stretched ring is an ellipse, not a circle: both extents are used.
    @Test("a ring follows both extents")
    func ringStretches() {
        let points = offsets(.ring, halfWidth: 200, halfHeight: 50)

        for offset in points {
            let normalised = (offset.x / 200) * (offset.x / 200) + (offset.y / 50) * (offset.y / 50)
            #expect(abs(normalised - 1) < 0.001)
        }
        #expect(points.contains { abs($0.x) > 150 })
        #expect(points.allSatisfy { abs($0.y) <= 50.001 })
    }

    @Test("an ellipse stays inside its extents")
    func ellipseIsContained() {
        for offset in offsets(.ellipse) {
            let radius = (offset.x * offset.x + offset.y * offset.y).squareRoot()
            #expect(radius <= 100.001)
        }
    }

    /// Sampled by area, not by radius.
    ///
    /// A uniform radius crowds the centre: half the particles land inside the
    /// inner half, which holds a quarter of the space. The outer ring should
    /// get roughly three quarters of them.
    @Test("an ellipse fills evenly rather than crowding the centre")
    func ellipseIsUniform() {
        let points = offsets(.ellipse, count: 4000)
        let inner = points.filter {
            ($0.x * $0.x + $0.y * $0.y).squareRoot() < 50
        }.count

        let share = Double(inner) / Double(points.count)
        #expect(abs(share - 0.25) < 0.04, "inner quarter held \(share) of the particles")
    }

    /// A rectangle uses its corners — the check that the default did not
    /// quietly become a shape with rounded edges.
    @Test("a rectangle reaches its corners")
    func rectangleFillsTheBox() {
        let points = offsets(.rectangle, count: 2000)
        #expect(points.contains { abs($0.x) > 90 && abs($0.y) > 90 })
        #expect(points.allSatisfy { abs($0.x) <= 100 && abs($0.y) <= 100 })
    }

    // ─── Radial direction ────────────────────────────────────────────────────

    /// Reported in **Direction** degrees, not mathematical ones.
    ///
    /// The emitter's `Direction: 270` means up, where `cos`/`sin` call up −90:
    /// the two conventions sit a quarter turn apart. Returning a raw `atan2`
    /// here and adding it to a Direction crossed them, and every ring using
    /// Radial threw its particles along the rim while the parameter said
    /// outward — a bug that stood until Swirl came to sit on the same angle.
    @Test(
        "outward points away from the centre on a circle",
        arguments: [(100.0, 0.0, 90.0), (0.0, 100.0, 180.0), (-100.0, 0.0, 270.0), (0.0, -100.0, 0.0)],
    )
    func outwardOnACircle(x: Double, y: Double, expected: Double) {
        guard let angle = EmitterEffect.outwardAngle(
            (x: x, y: y, phase: 0, tilt: 0), halfWidth: 100, halfHeight: 100,
        ) else {
            Issue.record("a point off the centre has an outward direction")
            return
        }
        // Compared around the circle: 270 and −90 are the same heading.
        let difference = abs((angle - expected).truncatingRemainder(dividingBy: 360))
        #expect(min(difference, 360 - difference) < 0.001)
    }

    /// On a flattened ring the outward direction is the surface normal, not the
    /// line back to the centre. Use the latter and a wide, shallow ring sprays
    /// along its own edge instead of away from it.
    @Test("outward follows the normal on a stretched ring")
    func outwardUsesTheNormal() throws {
        // A point most of the way along a wide, shallow ellipse.
        var rng = EffectRandom(seed: 1)
        _ = rng.unit()

        let halfWidth = 200.0
        let halfHeight = 40.0
        let t = Double.pi / 4
        let point = (x: cos(t) * halfWidth, y: sin(t) * halfHeight, phase: t, tilt: 0.0)

        let normal = try #require(
            EmitterEffect.outwardAngle(point, halfWidth: halfWidth, halfHeight: halfHeight),
        )
        let toCentre = atan2(point.y, point.x) * 180 / .pi

        // On a stretched ellipse the two genuinely differ, and the normal is
        // the steeper of the pair: the flattened axis pushes outward harder.
        #expect(abs(normal - toCentre) > 5)
        #expect(normal > toCentre)
    }

    /// **This test used to pass with the bug in it.** It asserted `isFinite`,
    /// and the old code returned `0` — finite, and the reason a radial `Point`
    /// emitter fired every particle along `Direction` as a single jet. A test
    /// that cannot fail is worse than no test: it reports the parameter works.
    ///
    /// Every way is equally away from the centre, so the honest answer is that
    /// there is no one direction — the caller picks from the particle's own
    /// stream, which is the only place a repeatable choice can come from.
    @Test("a particle at the centre has no outward direction of its own")
    func centreHasNoDirection() {
        #expect(
            EmitterEffect.outwardAngle(
                (x: 0.0, y: 0.0, phase: 0.0, tilt: 0.0), halfWidth: 100, halfHeight: 100,
            ) == nil,
        )
    }

    /// The bug this pins: `Point` + `Radial` is the most natural way to ask for
    /// a burst, and it was the one combination that did not work — every
    /// particle spawns at the centre, so every outward angle came back `0` and
    /// the fan collapsed onto `Direction`. Measured on the `warp` preset: all
    /// twenty-four particles between −93° and −87°, which is `Spread` alone.
    @Test("a radial point emitter fires in every direction")
    func radialFromAPointSpreadsAround() {
        let sprites = EffectEvaluator().evaluate(EffectNode(
            id: "fx", type: "emitter", name: "Emitter",
            startTime: 0, duration: 2000, seed: 7,
            values: [
                EmitterEffect.Param.count: .integer(80),
                EmitterEffect.Param.shape: .choice(EmitterEffect.Shape.point.rawValue),
                EmitterEffect.Param.radial: .toggle(true),
                EmitterEffect.Param.spread: .number(0),
                EmitterEffect.Param.velocity: .number(200),
                EmitterEffect.Param.lifeRandom: .number(0),
            ],
        ))

        // Which quadrants the particles actually travelled into. A single jet
        // reaches one; a burst reaches all four.
        var quadrants: Set<Int> = []
        for sprite in sprites {
            guard case let .move(_, _, endX, endY) = sprite.commands
                .last(where: { $0.kind == .move })?.payload else { continue }
            let dx = endX - sprite.defaultX
            let dy = endY - sprite.defaultY
            guard abs(dx) + abs(dy) > 1 else { continue }
            quadrants.insert((dx > 0 ? 1 : 0) + (dy > 0 ? 2 : 0))
        }

        #expect(quadrants.count == 4, "a radial burst reached only \(quadrants.count) quadrants")
    }

    // ─── Tilt: 2D standing in for depth ──────────────────────────────────────

    /// No tilt, no perspective — and that has to be exactly neutral, or every
    /// existing preset shifts the day the parameter is added.
    @Test("a flat ring is untouched")
    func flatRingIsNeutral() {
        for phase in stride(from: 0.0, to: 2 * .pi, by: 0.3) {
            let view = EmitterEffect.perspective(phase: phase, tilt: 0)
            #expect(view.stretch == 1)
            #expect(view.scale == 1)
            #expect(view.brightness == 1)
        }
    }

    /// The heart of the illusion: on a leaning ring, a particle's own facing
    /// depends on where it sits. A squashed ellipse alone is what a *flat* ring
    /// makes — it is the per-particle difference that reads as a turn in space.
    @Test("a tilted ring flattens its top and bottom, not its sides")
    func tiltFlattensByPosition() {
        let tilt = 60.0

        // Right and left: edge-on to the tilt, so height is kept.
        let right = EmitterEffect.perspective(phase: 0, tilt: tilt)
        let left = EmitterEffect.perspective(phase: .pi, tilt: tilt)
        #expect(abs(right.stretch - 1) < 0.001)
        #expect(abs(left.stretch - 1) < 0.001)

        // Top and bottom: flat-on, so height is lost.
        let bottom = EmitterEffect.perspective(phase: .pi / 2, tilt: tilt)
        let top = EmitterEffect.perspective(phase: -.pi / 2, tilt: tilt)
        #expect(bottom.stretch < 0.6)
        #expect(top.stretch < 0.6)
    }

    /// A steeper lean flattens harder, all the way to nearly edge-on.
    @Test("more tilt flattens more")
    func tiltIsProgressive() {
        let gentle = EmitterEffect.perspective(phase: .pi / 2, tilt: 20).stretch
        let steep = EmitterEffect.perspective(phase: .pi / 2, tilt: 75).stretch

        #expect(steep < gentle)
        #expect(gentle < 1)
        #expect(steep > 0)
    }

    /// The far side of a leaning ring is smaller and dimmer than the near side.
    /// Without this the two halves read as one flat band whatever the stretch
    /// says.
    @Test("the far side is smaller and dimmer")
    func depthReadsAsSizeAndBrightness() {
        let tilt = 55.0
        let far = EmitterEffect.perspective(phase: -.pi / 2, tilt: tilt)
        let near = EmitterEffect.perspective(phase: .pi / 2, tilt: tilt)

        #expect(far.scale < near.scale)
        #expect(far.brightness < near.brightness)

        // Both stay in a band a viewer reads as depth: scaled far enough, a
        // distant particle stops reading as distant and just reads as small.
        #expect(far.scale > 0.5)
        #expect(near.scale < 1.5)
    }

    /// A particle that stays lit: opacity is multiplied by brightness, so a
    /// value over 1 on the near side is fine, but zero on the far side would
    /// mean half the ring never draws.
    @Test("brightness never puts a particle out")
    func brightnessStaysPositive() {
        for tilt in stride(from: 0.0, through: 85, by: 5) {
            for phase in stride(from: 0.0, to: 2 * .pi, by: 0.2) {
                let view = EmitterEffect.perspective(phase: phase, tilt: tilt)
                #expect(view.brightness > 0.4)
                #expect(view.stretch > 0)
                #expect(view.scale > 0)
            }
        }
    }

    /// Tilt is clamped short of fully edge-on. A ring at exactly 90° is a line,
    /// and every particle in it would have zero height — an effect that draws
    /// nothing is worse than one that draws a very flat ring.
    @Test("an extreme tilt still draws something")
    func extremeTiltStillDraws() {
        let view = EmitterEffect.perspective(phase: .pi / 2, tilt: 85)
        #expect(view.stretch > 0.001)
    }

    /// Tilt has to shorten the ring on screen, not only turn the particles
    /// standing on it.
    ///
    /// Half a perspective is worse than none: the first version leaned every
    /// particle and left the outline as round as it started, so the pieces
    /// faced away while the circle they sat on did not. That reads as a bug.
    @Test("a tilted ring is shorter on screen")
    func tiltShortensTheRing() {
        func silhouette(tilt: Double) -> (width: Double, height: Double) {
            var values = EmitterEffect.descriptor.defaultValues
            values[EmitterEffect.Param.shape] = .choice(EmitterEffect.Shape.ring.rawValue)
            values[EmitterEffect.Param.width] = .number(200)
            values[EmitterEffect.Param.height] = .number(200)
            values[EmitterEffect.Param.tilt] = .number(tilt)
            values[EmitterEffect.Param.count] = .integer(300)
            values[EmitterEffect.Param.velocity] = .number(0)
            values[EmitterEffect.Param.gravity] = .number(0)

            let sprites = EffectEvaluator().evaluate(EffectNode(
                id: "ring", type: "emitter", name: "Ring",
                startTime: 0, duration: 2000, seed: 5, values: values,
            ))
            let xs = sprites.map(\.defaultX)
            let ys = sprites.map(\.defaultY)
            return (xs.max()! - xs.min()!, ys.max()! - ys.min()!)
        }

        let flat = silhouette(tilt: 0)
        #expect(abs(flat.width - flat.height) < 12, "a flat ring should be round")

        let leaning = silhouette(tilt: 60)
        // Width is untouched — the lean is about one axis.
        #expect(abs(leaning.width - flat.width) < 12)
        // Height follows the cosine: 60° leaves about half.
        #expect(leaning.height < flat.height * 0.65)
        #expect(leaning.height > flat.height * 0.35)
    }

    // ─── Sphere ──────────────────────────────────────────────────────────────

    private func sphere(
        bands: Int = 7,
        tilt: Double = 55,
        radius: Double = 100,
        count: Int = 4000,
    ) -> [(x: Double, y: Double, phase: Double, tilt: Double)] {
        var rng = EffectRandom(seed: 11)
        return (0 ..< count).map { _ in
            EmitterEffect.spawnOffset(
                shape: .sphere,
                halfWidth: radius, halfHeight: radius,
                bands: bands, tilt: tilt, rng: &rng,
            )
        }
    }

    /// A sphere is as tall as it is wide, however it is turned.
    ///
    /// The trap: squashing the height by the lean is right for a single ring
    /// and collapses a sphere into the disc it exists not to be. Normalising
    /// band by band overcorrects the other way and flattens it.
    @Test("a sphere is round")
    func sphereIsRound() {
        let points = sphere()
        let width = points.map(\.x).max()! - points.map(\.x).min()!
        let height = points.map(\.y).max()! - points.map(\.y).min()!

        #expect(abs(width - height) < width * 0.1, "\(Int(width))×\(Int(height)) is not round")
        #expect(width > 180, "the sphere does not fill its extents")
    }

    @Test("a sphere stays inside its extents", arguments: [1, 3, 7, 12, 16])
    func sphereIsContained(bands: Int) {
        for point in sphere(bands: bands) {
            #expect(abs(point.x) <= 100.001)
            #expect(abs(point.y) <= 100.001)
        }
    }

    /// Bands, not a cloud. A sphere drawn as scattered points is a ball of
    /// dots; it is the rings that let the eye trace a surface curving away.
    @Test("a sphere is made of distinguishable bands")
    func sphereHasBands() {
        let points = sphere(bands: 7)
        let tilts = Set(points.map { Int($0.tilt.rounded()) })

        // Latitude is mirrored north and south, so seven bands share four
        // openings — the pairs are at the same angle by construction.
        #expect(tilts.count >= 4, "the bands are not distinct: \(tilts.sorted())")
    }

    /// Bands near a pole open widest and bands at the equator close to a line,
    /// which is what makes a wireframe globe read as a globe.
    @Test("bands near the poles are narrower and more open")
    func bandsVaryByLatitude() {
        let points = sphere(bands: 9)

        func width(atTilt tilt: Int) -> Double {
            let band = points.filter { Int($0.tilt.rounded()) == tilt }
            guard !band.isEmpty else { return 0 }
            return band.map(\.x).max()! - band.map(\.x).min()!
        }

        let tilts = Set(points.map { Int($0.tilt.rounded()) }).sorted()
        let flattest = tilts.first!
        let mostOpen = tilts.last!

        // The most open band is the equator, and the equator is the widest.
        #expect(width(atTilt: mostOpen) > width(atTilt: flattest))
    }

    /// One band is a ring, and has to behave like one rather than crashing on
    /// a division or collapsing to a point.
    @Test("a single band is still a circle")
    func singleBandIsARing() {
        let points = sphere(bands: 1)
        let width = points.map(\.x).max()! - points.map(\.x).min()!

        #expect(width > 180)
        #expect(points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }

    // ─── Swirl ───────────────────────────────────────────────────────────────

    /// Where a particle at the right of a ring is heading, in degrees.
    private func heading(swirl: Double, radial: Bool = true) -> Double {
        var values = EmitterEffect.descriptor.defaultValues
        values[EmitterEffect.Param.shape] = .choice(EmitterEffect.Shape.ring.rawValue)
        values[EmitterEffect.Param.width] = .number(200)
        values[EmitterEffect.Param.height] = .number(200)
        values[EmitterEffect.Param.radial] = .toggle(radial)
        values[EmitterEffect.Param.swirl] = .number(swirl)
        values[EmitterEffect.Param.spread] = .number(0)
        values[EmitterEffect.Param.velocity] = .number(100)
        values[EmitterEffect.Param.drag] = .number(0)
        values[EmitterEffect.Param.gravity] = .number(0)
        values[EmitterEffect.Param.count] = .integer(200)

        let sprites = EffectEvaluator().evaluate(EffectNode(
            id: "swirl", type: "emitter", name: "Swirl",
            startTime: 0, duration: 2000, seed: 3, values: values,
        ))

        // The particle nearest the ring's right-hand side, and which way it goes.
        let centreX = TransformProperty.x.defaultValue
        let centreY = TransformProperty.y.defaultValue

        var best: (offset: Double, angle: Double)?
        for sprite in sprites {
            let dx = sprite.defaultX - centreX
            let dy = sprite.defaultY - centreY
            // Right-hand side: dx large and positive, dy near zero.
            guard dx > 80, abs(dy) < 12 else { continue }

            for command in sprite.commands {
                guard case let .move(sx, sy, ex, ey) = command.payload else { continue }
                let travel = atan2(ey - sy, ex - sx) * 180 / .pi
                if best == nil || abs(dy) < best!.offset {
                    best = (abs(dy), travel)
                }
                break
            }
        }
        return best?.angle ?? .nan
    }

    /// With no swirl, a radial emitter throws straight out — the behaviour
    /// every existing preset relies on, so it has to stay exactly as it was.
    @Test("no swirl is still straight outward")
    func zeroSwirlIsRadial() {
        let angle = heading(swirl: 0)
        #expect(!angle.isNaN)
        // Straight out at the right-hand side is 0°.
        #expect(abs(angle) < 12, "went \(angle)° instead of outward")
    }

    /// The point of the parameter: at 90 the particle runs **along** the rim
    /// rather than away from it, which is the only way energy circles a ring
    /// when the ring itself cannot rotate.
    @Test("full swirl runs along the rim", arguments: [90.0, -90.0])
    func fullSwirlIsTangential(swirl: Double) {
        let angle = heading(swirl: swirl)
        #expect(!angle.isNaN)

        // At the right-hand side, tangential is straight up or straight down.
        let fromVertical = min(abs(abs(angle) - 90), abs(abs(angle) - 90))
        #expect(fromVertical < 12, "went \(angle)°, which is not along the rim")
    }

    /// Opposite signs run opposite ways around, so a preset can have two rings
    /// counter-rotating.
    @Test("the sign picks the direction of travel")
    func swirlSignReverses() {
        let clockwise = heading(swirl: 90)
        let anticlockwise = heading(swirl: -90)

        #expect(!clockwise.isNaN && !anticlockwise.isNaN)
        #expect(clockwise * anticlockwise < 0, "both went the same way")
    }

    /// Halfway is a spiral: neither straight out nor straight along.
    @Test("part swirl spirals")
    func partSwirlSpirals() {
        let angle = heading(swirl: 45)
        #expect(!angle.isNaN)
        #expect(abs(angle) > 20, "still going straight out")
        #expect(abs(abs(angle) - 90) > 20, "already running along the rim")
    }

    /// Swirl is defined against the outward angle, so with Radial off there is
    /// no centre to be a quarter turn from and it has nothing to act on.
    @Test("swirl needs a radial emitter")
    func swirlNeedsRadial() {
        let withRadial = heading(swirl: 90, radial: false)
        let without = heading(swirl: 0, radial: false)
        #expect(withRadial == without || (withRadial.isNaN && without.isNaN))
    }
}
