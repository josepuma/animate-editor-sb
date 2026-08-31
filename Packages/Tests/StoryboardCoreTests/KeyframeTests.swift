import Foundation
import Testing

@testable import StoryboardCore

/// A property's value over time.
///
/// Keyframes replace the `start`/`end` pairs an effect would otherwise declare.
/// Those are keyframes with the count fixed at two — they cannot say "here,
/// then there, then back", which is most of what animating something means.
@Suite("Keyframe tracks")
struct KeyframeTrackTests {
    private func track(_ pairs: [(Double, Double)]) -> KeyframeTrack {
        KeyframeTrack(pairs.map { Keyframe(time: $0.0, value: $0.1) })
    }

    @Test("keys are kept in time order however they arrive")
    func sorted() {
        let sorted = track([(2000, 3), (0, 1), (1000, 2)])
        #expect(sorted.keyframes.map(\.value) == [1, 2, 3])
    }

    @Test("a value between two keys is interpolated")
    func interpolates() {
        let moving = track([(0, 100), (1000, 200)])

        #expect(moving.value(at: 0) == 100)
        #expect(moving.value(at: 500) == 150)
        #expect(moving.value(at: 1000) == 200)
    }

    /// A property does not fade in from nothing because its animation has not
    /// started yet.
    @Test("the ends are held")
    func holdsTheEnds() {
        let moving = track([(500, 10), (1500, 20)])

        #expect(moving.value(at: 0) == 10)
        #expect(moving.value(at: 5000) == 20)
    }

    @Test("a single key is a constant")
    func singleKey() {
        let constant = KeyframeTrack(constant: 42)

        #expect(!constant.isAnimated)
        #expect(constant.value(at: 0) == 42)
        #expect(constant.value(at: 9999) == 42)
    }

    /// Two keys at one time is a state with no meaning — the value would be
    /// whichever the sort happened to put second.
    @Test("setting a key replaces one at the same time")
    func replacesAtTheSameTime() {
        var editing = track([(0, 1), (1000, 2)])
        editing.set(99, at: 1000)

        #expect(editing.keyframes.count == 2)
        #expect(editing.value(at: 1000) == 99)
    }

    @Test("a key can be moved, and the order follows")
    func moving() {
        var editing = track([(0, 1), (1000, 2), (2000, 3)])
        let middle = editing.keyframes[1].id
        editing.move(middle, to: 3000)

        #expect(editing.keyframes.map(\.value) == [1, 3, 2])
    }

    @Test("a key can be removed")
    func removing() {
        var editing = track([(0, 1), (1000, 2)])
        editing.remove(editing.keyframes[0].id)

        #expect(editing.keyframes.count == 1)
        #expect(!editing.isAnimated)
    }

    /// The easing belongs to the key it leaves *from*, which is how a
    /// storyboard command carries its own curve.
    @Test("easing comes from the key a segment starts at")
    func easingBelongsToTheStart() {
        var eased = KeyframeTrack([
            Keyframe(time: 0, value: 0, easing: .out),
            Keyframe(time: 1000, value: 100, easing: .linear),
        ])

        let midpoint = eased.value(at: 500)
        // An ease-out is ahead of linear at the halfway mark.
        #expect(midpoint > 50)

        eased.setEasing(.linear, for: eased.keyframes[0].id)
        #expect(abs(eased.value(at: 500) - 50) < 1e-9)
    }

    // ─── Values and animation ────────────────────────────────────────────────
    //
    // A property is a *value* until someone turns animation on for it. Merging
    // the two was a real bug: with the displayed value read from the playhead,
    // moving along the timeline and typing a number planted keys nobody asked
    // for, on properties nobody was animating.

    @Test("a property has a resting value before it is animated")
    func restingValue() {
        var transform = Transform()
        transform[value: .scale] = 2

        #expect(!transform.isAnimated(.scale))
        #expect(transform.value(.scale, at: 0) == 2)
        #expect(transform.value(.scale, at: 5000) == 2)
    }

    @Test("an unset property reads the system default")
    func unsetProperty() {
        let transform = Transform()

        #expect(transform.value(.scale, at: 0) == 1)
        #expect(transform.value(.x, at: 0) == 320)
        #expect(!transform.isSet(.scale))
    }

    /// Animation wins while it exists; the resting value waits underneath.
    @Test("keyframes override the resting value")
    func animationWins() {
        var transform = Transform()
        transform[value: .opacity] = 0.5
        transform[.opacity] = KeyframeTrack([
            Keyframe(time: 0, value: 0),
            Keyframe(time: 1000, value: 1),
        ])

        #expect(transform.value(.opacity, at: 0) == 0)
        #expect(transform.value(.opacity, at: 1000) == 1)
    }

    @Test("an empty track is not animation of nothing")
    func emptyTrack() {
        var transform = Transform()
        transform[.x] = KeyframeTrack()

        #expect(transform.isEmpty)
        #expect(!transform.isAnimated(.x))
        // An unanimated property reads as its default.
        #expect(transform.value(.scale, at: 0) == 1)
    }

    @Test("animated properties come out in declaration order")
    func animatedProperties() {
        var transform = Transform()
        transform[.opacity] = KeyframeTrack(constant: 1)
        transform[.x] = KeyframeTrack(constant: 0)

        #expect(transform.animatedProperties == [.x, .opacity])
    }
}

/// Turning keyframes into the commands a `.osb` holds.
///
/// The two models line up almost exactly — a command interpolates one property
/// between two values with its own easing, which is a segment between two keys
/// — so a track of *n* keys becomes *n−1* commands and nothing is approximated.
@Suite("Transform commands")
struct TransformCommandTests {
    private func transform(_ build: (inout Transform) -> Void) -> Transform {
        var transform = Transform()
        build(&transform)
        return transform
    }

    @Test("each segment becomes one command")
    func segmentsBecomeCommands() {
        let moving = transform {
            $0[.scale] = KeyframeTrack([
                Keyframe(time: 0, value: 1),
                Keyframe(time: 500, value: 2),
                Keyframe(time: 1000, value: 0.5),
            ])
        }

        let commands = TransformCommands.build(from: moving, duration: 1000)
            .filter { $0.kind == .scale }

        #expect(commands.count == 2)
        #expect(commands[0].startTime == 0)
        #expect(commands[0].endTime == 500)
        #expect(commands[1].startTime == 500)
    }

    /// `_MX` and `_MY` exist for exactly this, and cost half of what an `_M`
    /// repeating a constant would.
    @Test("one animated axis writes a single-axis move")
    func singleAxisMoves() {
        let horizontal = transform {
            $0[.x] = KeyframeTrack([Keyframe(time: 0, value: 0), Keyframe(time: 1000, value: 100)])
        }
        let vertical = transform {
            $0[.y] = KeyframeTrack([Keyframe(time: 0, value: 0), Keyframe(time: 1000, value: 100)])
        }

        #expect(TransformCommands.build(from: horizontal, duration: 1000).contains { $0.kind == .moveX })
        #expect(TransformCommands.build(from: vertical, duration: 1000).contains { $0.kind == .moveY })
    }

    /// A key on one axis has to become a command boundary, or its curve is lost
    /// inside a segment the other axis defined.
    @Test("both axes cut at every key of either")
    func bothAxesShareBoundaries() {
        let diagonal = transform {
            $0[.x] = KeyframeTrack([Keyframe(time: 0, value: 0), Keyframe(time: 1000, value: 100)])
            $0[.y] = KeyframeTrack([
                Keyframe(time: 0, value: 0),
                Keyframe(time: 400, value: 50),
                Keyframe(time: 1000, value: 0),
            ])
        }

        let moves = TransformCommands.build(from: diagonal, duration: 1000)
            .filter { $0.kind == .move }

        // Boundaries at 0, 400 and 1000 — two segments.
        #expect(moves.count == 2)
        #expect(moves[0].endTime == 400)
    }

    @Test("rotation is written in radians")
    func rotationIsRadians() {
        let turning = transform {
            $0[.rotation] = KeyframeTrack([
                Keyframe(time: 0, value: 0),
                Keyframe(time: 1000, value: 180),
            ])
        }

        guard case let .rotate(_, end) = TransformCommands
            .build(from: turning, duration: 1000)
            .first(where: { $0.kind == .rotate })?.payload
        else {
            Issue.record("expected a rotate command")
            return
        }
        #expect(abs(end - .pi) < 1e-9)
    }

    /// A still sprite should cost a handful of lines, not a full set of
    /// commands that move from a place to the same place.
    @Test("a property at its default writes nothing")
    func defaultsAreSilent() {
        let still = transform {
            $0[.scale] = KeyframeTrack(constant: 1)
            $0[.rotation] = KeyframeTrack(constant: 0)
        }

        #expect(TransformCommands.build(from: still, duration: 1000).isEmpty)
    }

    @Test("a held value that is not the default is written once")
    func heldValuesAreWritten() {
        let scaled = transform { $0[.scale] = KeyframeTrack(constant: 2) }
        let commands = TransformCommands.build(from: scaled, duration: 1000)

        #expect(commands.count == 1)
        #expect(commands[0].startTime == commands[0].endTime)
    }

    /// The values a command carries have to match what the track says, or the
    /// preview and the file disagree.
    @Test("command values match the track they came from")
    func commandsMatchTheTrack() {
        let fading = transform {
            $0[.opacity] = KeyframeTrack([
                Keyframe(time: 0, value: 0),
                Keyframe(time: 800, value: 1),
            ])
        }

        guard case let .fade(start, end) = TransformCommands
            .build(from: fading, duration: 800)
            .first(where: { $0.kind == .fade })?.payload
        else {
            Issue.record("expected a fade")
            return
        }
        #expect(start == fading[.opacity].value(at: 0))
        #expect(end == fading[.opacity].value(at: 800))
    }
}


/// Turning animation off is a decision about *how* a property behaves, not
/// about what it is.
@Suite("Animation toggling")
struct AnimationTogglingTests {
    private let descriptor = EmitterEffect.descriptor

    private func document() -> (EffectDocument, EffectNode.ID) {
        var document = EffectDocument()
        let node = document.add(descriptor, at: 0, duration: 2000)
        return (document, node.id)
    }

    @Test("editing an unanimated property sets its value, not a keyframe")
    func editingSetsTheValue() {
        var (document, nodeID) = document()
        document.setTransformValue(3, for: .scale, on: nodeID)

        #expect(document[nodeID]?.transform.isAnimated(.scale) == false)
        #expect(document[nodeID]?.transform.value(.scale, at: 0) == 3)
    }

    /// The bug this pins: with editing always keyframing, moving the playhead
    /// and typing a number left keys behind on properties nobody was animating.
    @Test("setting a value never plants a keyframe")
    func valuesDoNotAnimate() {
        var (document, nodeID) = document()

        document.setTransformValue(2, for: .scale, on: nodeID)
        document.setTransformValue(5, for: .scale, on: nodeID)

        #expect(document[nodeID]?.transform[.scale].isEmpty == true)
        #expect(document[nodeID]?.transform.value(.scale, at: 0) == 5)
    }

    /// Switching animation off should not also change what is on screen.
    @Test("turning animation off keeps the value it had")
    func clearingKeepsTheValue() {
        var (document, nodeID) = document()
        document.setKeyframe(0, for: .opacity, at: 0, on: nodeID)
        document.setKeyframe(1, for: .opacity, at: 1000, on: nodeID)

        document.clearKeyframes(for: .opacity, on: nodeID, keeping: 1000)

        #expect(document[nodeID]?.transform.isAnimated(.opacity) == false)
        #expect(document[nodeID]?.transform.value(.opacity, at: 0) == 1)
    }

    /// The stopwatch switches animation off; it does not destroy it.
    ///
    /// Deleting a stopwatch's worth of work on one click — with no undo — is a
    /// trap: the click that turns animation on and the click that would destroy
    /// it are the same click, and the second is indistinguishable from the
    /// first until it is too late. Deleting is its own, deliberate action.
    @Test("switching animation off keeps the keyframes")
    func disablingKeepsKeys() {
        var (document, nodeID) = document()
        document.setKeyframe(0, for: .opacity, at: 0, on: nodeID)
        document.setKeyframe(1, for: .opacity, at: 1000, on: nodeID)

        document.setAnimationEnabled(false, for: .opacity, on: nodeID, keeping: 1000)

        let transform = document[nodeID]!.transform
        #expect(transform[.opacity].keyframes.count == 2)
        #expect(!transform[.opacity].isActive)
        // And the sprite does not jump: it holds what the animation had.
        #expect(transform.value(.opacity, at: 0) == 1)
    }

    @Test("switching animation back on restores it")
    func reenabling() {
        var (document, nodeID) = document()
        document.setKeyframe(0, for: .opacity, at: 0, on: nodeID)
        document.setKeyframe(1, for: .opacity, at: 1000, on: nodeID)

        document.setAnimationEnabled(false, for: .opacity, on: nodeID)
        document.setAnimationEnabled(true, for: .opacity, on: nodeID)

        #expect(document[nodeID]?.transform.value(.opacity, at: 0) == 0)
        #expect(document[nodeID]?.transform.value(.opacity, at: 1000) == 1)
    }

    /// Putting a key down is a request to animate; leaving it inert would look
    /// like the click did nothing.
    @Test("adding a key to a switched-off property switches it back on")
    func addingReenables() {
        var (document, nodeID) = document()
        document.setKeyframe(0.5, for: .scale, at: 0, on: nodeID)
        document.setAnimationEnabled(false, for: .scale, on: nodeID)

        document.setKeyframe(2, for: .scale, at: 500, on: nodeID)

        #expect(document[nodeID]?.transform[.scale].isActive == true)
    }

    /// Deleting is still available — as its own action.
    @Test("clearing removes the keys and keeps the value")
    func clearingIsDeliberate() {
        var (document, nodeID) = document()
        document.setKeyframe(0.2, for: .scale, at: 0, on: nodeID)
        document.setKeyframe(1.5, for: .scale, at: 1000, on: nodeID)

        document.clearKeyframes(for: .scale, on: nodeID, keeping: 1000)

        #expect(document[nodeID]?.transform[.scale].isEmpty == true)
        #expect(document[nodeID]?.transform.value(.scale, at: 0) == 1.5)
    }

    /// A switched-off track must not reach the file.
    @Test("disabled animation writes no commands")
    func disabledWritesNothing() {
        var transform = Transform()
        var track = KeyframeTrack()
        track.set(0, at: 0)
        track.set(1, at: 1000)
        track.isEnabled = false
        transform[.opacity] = track

        #expect(TransformCommands.build(from: transform, duration: 1000).isEmpty)
    }

    /// An unanimated property still has to reach the file when it differs from
    /// the default — a sprite set to half scale has to say so somewhere.
    @Test("a resting value that is not the default is written out")
    func restingValuesAreExported() {
        var transform = Transform()
        transform[value: .scale] = 0.5

        let commands = TransformCommands.build(from: transform, duration: 1000)
        #expect(commands.count == 1)
        #expect(commands[0].kind == .scale)
    }

    @Test("a resting value equal to the default writes nothing")
    func defaultsStaySilent() {
        var transform = Transform()
        transform[value: .scale] = 1

        #expect(TransformCommands.build(from: transform, duration: 1000).isEmpty)
    }
}


/// Resizing a clip has to carry its animation with it.
@Suite("Resizing with keyframes")
struct KeyframeResizeTests {
    /// An image with a fade of its own, which is what resizing has to carry.
    private func document(duration: Double) -> (EffectDocument, EffectNode.ID) {
        var document = EffectDocument()
        var node = document.add(ImageEffect.descriptor, at: 0, duration: duration)
        node.values[ImageEffect.Param.sprite] = .text("sb/a.png")

        var opacity = KeyframeTrack()
        let fade = min(300, duration * 0.2)
        opacity.set(0, at: 0)
        opacity.set(1, at: fade)
        opacity.set(1, at: max(fade, duration - fade))
        opacity.set(0, at: duration)
        node.transform[.opacity] = opacity

        document[node.id] = node
        return (document, node.id)
    }

    /// The bug this pins: keys left where they were describe a moment that is
    /// now a fraction of the way in. A four-second clip stretched to
    /// twenty-six faded out at second four and spent the next twenty-two
    /// invisible — the sprite simply vanished a sixth of the way through.
    @Test("stretching a clip stretches its keyframes")
    func stretching() {
        var (document, nodeID) = document(duration: 4000)
        let before = document[nodeID]!.transform[.opacity].keyframes.map(\.time)

        document.resize(nodeID, startTime: 0, duration: 26_337)
        let after = document[nodeID]!.transform[.opacity].keyframes.map(\.time)

        #expect(before.last == 4000)
        #expect(after.last == 26_337)
        // The shape is kept: proportions along the clip are unchanged.
        for (old, new) in zip(before, after) {
            #expect(abs(new / 26_337 - old / 4000) < 1e-9)
        }
    }

    @Test("a stretched clip stays visible for its whole length")
    func staysVisible() {
        var (document, nodeID) = document(duration: 4000)
        document.resize(nodeID, startTime: 0, duration: 20_000)

        let prepared = StoryboardResolver.prepare(EffectEvaluator().evaluate(document))

        for time in [2000.0, 10_000.0, 18_000.0] {
            var states: [SpriteRenderState] = []
            StoryboardResolver.resolve(prepared, at: time, into: &states)
            #expect(states.first?.opacity ?? 0 > 0.1, "invisible at \(Int(time))ms")
        }
    }

    /// A property held at a value, with no keys, must not be lost when the clip
    /// is resized — it is not animation, so there is nothing to rescale.
    @Test("resizing leaves resting values alone")
    func restingValuesSurvive() {
        var (document, nodeID) = document(duration: 4000)
        document.setTransformValue(0.3, for: .scale, on: nodeID)

        document.resize(nodeID, startTime: 0, duration: 26_337)

        #expect(document[nodeID]?.transform.value(.scale, at: 0) == 0.3)
        #expect(document[nodeID]?.transform.value(.scale, at: 26_000) == 0.3)
    }

    /// The case the user hit: scale set, nothing animated, clip stretched.
    @Test("an unanimated property holds for the whole clip")
    func heldForTheWholeClip() {
        var (document, nodeID) = document(duration: 26_337)
        document.setTransformValue(0.3, for: .scale, on: nodeID)

        let prepared = StoryboardResolver.prepare(EffectEvaluator().evaluate(document))

        for time in [100.0, 13_000.0, 26_000.0] {
            var states: [SpriteRenderState] = []
            StoryboardResolver.resolve(prepared, at: time, into: &states)
            #expect(states.first?.scaleX == 0.3, "wrong scale at \(Int(time))ms")
        }
    }

    @Test("shrinking a clip pulls its keyframes in")
    func shrinking() {
        var (document, nodeID) = document(duration: 8000)
        document.resize(nodeID, startTime: 0, duration: 2000)

        let keys = document[nodeID]!.transform[.opacity].keyframes
        #expect(keys.allSatisfy { $0.time <= 2000 })
        #expect(keys.last?.time == 2000)
    }
}


/// A sprite's life is read from its commands, so every route that places one
/// has to leave it with a command that spans its clip.
@Suite("Placed effects have a life")
struct PlacedEffectLifeTests {
    /// A freshly placed effect animates nothing.
    ///
    /// An automatic fade was added at one point so the keyframe row had
    /// something to show — decorating a panel at the cost of animation nobody
    /// asked for. A placed image should hold still until told otherwise.
    @Test("a placed effect starts with nothing animated")
    func placedFromTheLibrary() {
        var document = EffectDocument()
        let node = document.add(ImageEffect.descriptor, at: 0, duration: 2000)

        #expect(document[node.id]?.transform.isEmpty == true)
    }


    @Test("a placed image lives for its whole clip, at any scale")
    func livesForTheWholeClip() {
        for scale in [1.0, 0.3, 4.0] {
            var document = EffectDocument()
            var node = document.add(ImageEffect.descriptor, at: 0, duration: 2000)
            node.values[ImageEffect.Param.sprite] = .text("bg.jpg")
            document[node.id] = node

            document.resize(node.id, startTime: 0, duration: 32_983)
            document.setTransformValue(scale, for: .scale, on: node.id)

            let prepared = StoryboardResolver.prepare(EffectEvaluator().evaluate(document))
            let sprite = prepared.first

            #expect(sprite != nil, "no sprite at scale \(scale)")
            #expect(
                (sprite?.activeEnd ?? 0) - (sprite?.activeStart ?? 0) > 30_000,
                "sprite lives \(Int((sprite?.activeEnd ?? 0) - (sprite?.activeStart ?? 0)))ms at scale \(scale)",
            )
        }
    }

    /// Even with nothing animated at all, an image has to be on screen.
    @Test("an image with no animation still spans its clip")
    func unanimatedImageSpansItsClip() {
        var document = EffectDocument()
        var node = document.add(ImageEffect.descriptor, at: 0, duration: 5000)
        node.values[ImageEffect.Param.sprite] = .text("bg.jpg")
        node.transform = Transform()
        document[node.id] = node

        let prepared = StoryboardResolver.prepare(EffectEvaluator().evaluate(document))

        #expect(prepared.first?.activeStart == 0)
        #expect(prepared.first?.activeEnd == 5000)
    }

    /// Every effect in the library, however it is placed.
    @Test("no library effect produces a zero-length sprite", arguments: EffectLibrary.standard.descriptors)
    func noZeroLengthSprites(descriptor: EffectDescriptor) {
        var document = EffectDocument()
        var node = document.add(descriptor, at: 0, duration: 4000)
        // Give the image one, since an effect with no file draws nothing at all
        // — which is correct, and a different case.
        if descriptor.type == ImageEffect.descriptor.type {
            node.values[ImageEffect.Param.sprite] = .text("bg.jpg")
            document[node.id] = node
        }

        for sprite in StoryboardResolver.prepare(EffectEvaluator().evaluate(document)) {
            #expect(
                sprite.activeEnd > sprite.activeStart,
                "\(descriptor.type) produced a sprite with no life",
            )
        }
    }
}
