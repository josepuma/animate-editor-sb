import Foundation
import Testing

@testable import StoryboardCore

/// A compound preset fails differently from a plain one: the parent can be
/// perfectly visible while a layer contributes nothing, and nobody notices
/// because the effect still looks like something. So every layer is checked on
/// its own, not just the whole.
@Suite("Compound presets")
struct CompoundPresetTests {
    private let evaluator = EffectEvaluator()

    /// Placed the way the app places it, layers and all.
    private func node(_ preset: EffectPreset) -> EffectNode {
        var placed = EffectNode(
            id: preset.id,
            type: preset.effectType,
            name: preset.name,
            startTime: 0,
            duration: preset.duration,
            seed: 12,
            values: preset.values,
        )
        placed.layers = preset.layers.enumerated().map { index, layer in
            var child = EffectNode(
                id: "\(preset.id)/L\(index)",
                type: layer.effectType,
                name: layer.name,
                startTime: 0,
                duration: preset.duration,
                seed: EffectNode.layerSeed(from: 12, index: index),
                values: layer.values,
            )
            // Exactly as `EditorShellModel.addPreset` places one.
            //
            // Skipping this is what let a layer sit 155px above the stage
            // centre while every probe reported it dead centre: the emitter
            // never reads `x`/`y` at all — the editor lifts them onto the
            // transform, where they are absolute stage positions. A test that
            // evaluates a layer the app would never build tests nothing.
            if case let .number(x) = layer.values[EmitterEffect.Param.x] {
                child.transform[value: .x] = x
            }
            if case let .number(y) = layer.values[EmitterEffect.Param.y] {
                child.transform[value: .y] = y
            }
            return child
        }
        return placed
    }

    private func isVisible(_ sprites: [StoryboardSprite], within duration: Double) -> Bool {
        let prepared = StoryboardResolver.prepare(sprites)
        for fraction in [0.1, 0.3, 0.5, 0.8] {
            var states: [SpriteRenderState] = []
            StoryboardResolver.resolve(prepared, at: duration * fraction, into: &states)
            if states.contains(where: { $0.visible && $0.opacity > 0.02 }) { return true }
        }
        return false
    }

    @Test("a compound preset carries layers", arguments: EmitterEffect.compoundPresets)
    func compoundsHaveLayers(preset: EffectPreset) {
        #expect(!preset.layers.isEmpty, "\(preset.id) is compound in name only")
    }

    /// Every layer carries every parameter its effect declares, so nothing
    /// falls back silently to a default nobody chose.
    @Test("every layer is complete", arguments: EmitterEffect.compoundPresets)
    func layersAreComplete(preset: EffectPreset) {
        let declared = Set(EmitterEffect.descriptor.parameters.map(\.id))

        for layer in preset.layers {
            #expect(layer.effectType == EmitterEffect.descriptor.type)
            #expect(!layer.name.isEmpty, "\(preset.id) has an unnamed layer")
            #expect(
                declared.isSubset(of: Set(layer.values.keys)),
                "\(preset.id)/\(layer.name) is missing parameters",
            )
        }
    }

    /// Every layer draws a shape the renderer can supply. A layer naming a
    /// missing file draws flat quads, which reads as the compound being broken
    /// rather than as one asset going astray.
    @Test("every layer names a real sprite", arguments: EmitterEffect.compoundPresets)
    func layersUseKnownSprites(preset: EffectPreset) {
        for layer in preset.layers {
            guard case let .text(path) = layer.values[EmitterEffect.Param.sprite] else {
                Issue.record("\(preset.id)/\(layer.name) has no sprite")
                continue
            }
            #expect(
                BuiltInSprite.all.contains(path),
                "\(preset.id)/\(layer.name) uses an unknown sprite: \(path)",
            )
        }
    }

    /// The check that matters, applied per layer. A layer whose numbers cancel
    /// out costs sprites in the file and shows nothing — invisible while the
    /// rest of the compound carries the frame.
    @Test("every layer is visible on its own", arguments: EmitterEffect.compoundPresets)
    func eachLayerIsVisible(preset: EffectPreset) {
        let placed = node(preset)

        for layer in placed.layers {
            #expect(
                isVisible(evaluator.evaluate(layer), within: preset.duration),
                "\(preset.id)/\(layer.name) is never visible",
            )
        }
    }

    @Test("the whole compound is visible", arguments: EmitterEffect.compoundPresets)
    func compoundIsVisible(preset: EffectPreset) {
        let placed = node(preset)
        #expect(isVisible(evaluator.evaluate(placed), within: preset.duration))
    }

    /// A compound produces more than its parent alone, or the layers were
    /// dropped somewhere between the node and the evaluator.
    @Test("layers add to what the parent produces", arguments: EmitterEffect.compoundPresets)
    func layersContribute(preset: EffectPreset) {
        let placed = node(preset)
        var parentOnly = placed
        parentOnly.layers = []

        let whole = evaluator.evaluate(placed).count
        let alone = evaluator.evaluate(parentOnly).count

        #expect(whole > alone, "\(preset.id) evaluated its layers away")
    }

    /// No two layers share a particle field.
    ///
    /// Seeds derived by adding would land adjacent, and SplitMix64 loses a
    /// difference of one in its own avalanche — two layers would come out as
    /// near-copies of each other, which is the bug this project already hit
    /// once when deriving per-particle streams.
    @Test("layers do not share a seed", arguments: EmitterEffect.compoundPresets)
    func layerSeedsDiffer(preset: EffectPreset) {
        let placed = node(preset)
        let seeds = [placed.seed] + placed.layers.map(\.seed)

        #expect(Set(seeds).count == seeds.count, "\(preset.id) reuses a seed")
    }

    /// Sprite ids stay unique across layers, because the whole document is
    /// drawn as one list and a duplicate id would collapse two sprites into one.
    @Test("layer sprites have distinct ids", arguments: EmitterEffect.compoundPresets)
    func spriteIDsAreUnique(preset: EffectPreset) {
        let ids = evaluator.evaluate(node(preset)).map(\.id)
        #expect(Set(ids).count == ids.count, "\(preset.id) produced duplicate sprite ids")
    }

    /// Hiding a layer removes it, and only it.
    @Test("a hidden layer stops producing")
    func hiddenLayerIsSkipped() throws {
        let preset = try #require(EmitterEffect.compoundPresets.first)
        var placed = node(preset)
        let whole = evaluator.evaluate(placed).count

        placed.layers[0].isVisible = false
        let reduced = evaluator.evaluate(placed).count

        #expect(reduced < whole)
        #expect(reduced > 0, "hiding one layer emptied the effect")
    }

    /// The group moves as one, which is the point of a compound: layers are
    /// evaluated at a local zero and the parent's offset is applied once, at
    /// the end, to everything.
    @Test("moving the clip moves every layer")
    func movingCarriesLayers() throws {
        let preset = try #require(EmitterEffect.compoundPresets.first)
        var placed = node(preset)
        placed.startTime = 5000

        let sprites = evaluator.evaluate(placed)
        let earliest = sprites.flatMap(\.commands).map(\.startTime).min() ?? 0

        #expect(earliest >= 5000, "a layer ignored the clip's offset")
    }

    /// Duplicating carries the layers, re-homed.
    ///
    /// A layer's id prefixes its sprites, so a copy sharing them would collapse
    /// into the original. `filters` was dropped from this exact path once
    /// already — this is the same omission waiting to happen.
    @Test("duplicating carries the layers, re-homed")
    func duplicateCarriesLayers() throws {
        let preset = try #require(EmitterEffect.compoundPresets.first)
        var document = EffectDocument()
        let track = document.addTrack()
        let placed = document.add(
            EmitterEffect.descriptor, at: 0, duration: preset.duration, on: track.id,
        )

        var original = node(preset)
        original = EffectNode(
            id: placed.id,
            type: placed.type,
            name: placed.name,
            startTime: placed.startTime,
            duration: placed.duration,
            seed: 12,
            values: preset.values,
            layers: node(preset).layers,
        )
        document[placed.id] = original
        let duplicated = document.duplicate(original.id)
        let copy = try #require(duplicated)

        #expect(copy.layers.count == original.layers.count)
        #expect(copy.layers.map(\.name) == original.layers.map(\.name))

        // Nothing shared: not an id, not a seed.
        let originalIDs = Set([original.id] + original.layers.map(\.id))
        let copyIDs = Set([copy.id] + copy.layers.map(\.id))
        #expect(originalIDs.isDisjoint(with: copyIDs))

        let originalSeeds = Set([original.seed] + original.layers.map(\.seed))
        let copySeeds = Set([copy.seed] + copy.layers.map(\.seed))
        #expect(originalSeeds.isDisjoint(with: copySeeds))

        // Every layer id still sits under its new parent, or the bounding box
        // stops recognising the sprites as the clip's own.
        for layer in copy.layers {
            #expect(ClipBounds.sprite(layer.id, belongsTo: copy.id))
        }
    }

    /// The whole compound reads as one clip, which is what makes a single
    /// bounding box the right frame for it.
    @Test("every sprite belongs to the clip", arguments: EmitterEffect.compoundPresets)
    func spritesBelongToTheClip(preset: EffectPreset) {
        let placed = node(preset)

        for sprite in evaluator.evaluate(placed) {
            #expect(
                ClipBounds.sprite(sprite.id, belongsTo: placed.id),
                "\(sprite.id) escaped the clip",
            )
        }
    }

    /// A ring preset emits on a ring.
    ///
    /// The failure this exists for: Fire Ring shipped as a wide, flat *bar*
    /// because the emitter could only spawn in a rectangle, so the preset's own
    /// name contradicted its output. A name is a promise, and this is the only
    /// part of that promise a test can hold.
    @Test("a preset named ring emits on a ring")
    func ringPresetsAreRound() throws {
        let preset = try #require(
            EmitterEffect.compoundPresets.first { $0.id == "fire-ring" },
        )
        #expect(
            preset.values[EmitterEffect.Param.shape]
                == .choice(EmitterEffect.Shape.ring.rawValue),
        )

        // Hollow in fact, not just in declaration: nothing near the centre.
        let placed = node(preset)
        var parentOnly = placed
        parentOnly.layers = []

        let centreX = TransformProperty.x.defaultValue
        let centreY = TransformProperty.y.defaultValue
        let sprites = evaluator.evaluate(parentOnly)

        let nearCentre = sprites.filter {
            let dx = $0.defaultX - centreX
            let dy = $0.defaultY - centreY
            // Well inside the smaller extent, so it cannot be rim overspill.
            return (dx * dx + dy * dy).squareRoot() < 30
        }

        #expect(nearCentre.isEmpty, "\(nearCentre.count) particles spawned in the hole")
    }

    /// A rim is drawn by the particles alive at one moment, not by the count.
    ///
    /// The failure this exists for: Fire Ring was a correct circle in the model
    /// and reached the eye as scattered dots with a curve implied between them.
    /// Density is `count × life ÷ duration`, and the first version had ninety
    /// alive across a six-hundred-pixel perimeter — a dotted line.
    ///
    /// Worth knowing while tuning: **life buys density for free**. Raising the
    /// count costs one sprite each and one more line in the file; lengthening
    /// life costs nothing and keeps just as many on screen.
    @Test("the ring is dense enough to read as a line")
    func ringIsDense() throws {
        let preset = try #require(
            EmitterEffect.compoundPresets.first { $0.id == "fire-ring" },
        )
        var parentOnly = node(preset)
        parentOnly.layers = []

        let prepared = StoryboardResolver.prepare(evaluator.evaluate(parentOnly))
        var states: [SpriteRenderState] = []
        StoryboardResolver.resolve(prepared, at: preset.duration * 0.5, into: &states)

        let alive = states.filter { $0.visible && $0.opacity > 0.02 }

        // The rim they have to cover, from the emitter's own extents.
        guard case let .number(width) = preset.values[EmitterEffect.Param.width],
              case let .number(height) = preset.values[EmitterEffect.Param.height]
        else {
            Issue.record("the ring has no extents")
            return
        }

        // Ramanujan's approximation — exact enough at these proportions.
        let a = width / 2
        let b = height / 2
        let h = ((a - b) * (a - b)) / ((a + b) * (a + b))
        let perimeter = .pi * (a + b) * (1 + (3 * h) / (10 + (4 - 3 * h).squareRoot()))

        // The built-in shapes are drawn at 64px, so scale is width in pixels.
        let covered = alive.reduce(0.0) { $0 + Double($1.scaleX) * 64 }

        #expect(
            covered > perimeter * 1.5,
            "the rim covers \(Int(covered))px of \(Int(perimeter))px — a dotted line",
        )
    }

    /// A compound is still one clip in a text file, and every particle in it is
    /// a sprite with its whole life written out. Density is not free here the
    /// way it is in a tool that simulates.
    @Test("a compound stays within a sane file cost", arguments: EmitterEffect.compoundPresets)
    func compoundsAreAffordable(preset: EffectPreset) {
        let sprites = evaluator.evaluate(node(preset))
        let commands = sprites.reduce(0) { $0 + $1.commands.count }

        #expect(sprites.count <= 2000, "\(preset.id) makes \(sprites.count) sprites")
        #expect(commands <= 24000, "\(preset.id) writes \(commands) commands")
    }

    /// A layer has to stay on screen.
    ///
    /// The failure this exists for: the orb's waves were thrown *up the beam*
    /// at speed, so they left the sphere and piled into a white mass above it —
    /// nothing that escapes ever thins out, so the pile only grew.
    ///
    /// Measured against the stage rather than against the parent's own size.
    /// Comparing the two directly reads false on anything that travels by
    /// design: a fire ring is wide and flat while its column rises well past
    /// it, and debris flying out of an impact is the impact. What is always
    /// wrong is a layer whose particles leave the screen — those are commands
    /// written for something nobody can see.
    @Test("no layer throws its particles off screen", arguments: EmitterEffect.compoundPresets)
    func layersStayOnStage(preset: EffectPreset) {
        // The tunnel's whole subject is rushing *past* the viewer, so leaving
        // the frame is what it is for. Named rather than quietly excused: an
        // exception nobody can see is how a rule stops meaning anything.
        guard preset.id != "tunnel" else { return }

        let placed = node(preset)
        let centreX = TransformProperty.x.defaultValue
        let centreY = TransformProperty.y.defaultValue

        for layer in placed.layers {
            var offStage = 0
            var total = 0

            for sprite in evaluator.evaluate(layer) {
                var furthest = 0.0
                func note(_ x: Double, _ y: Double) {
                    furthest = max(furthest, abs(x - centreX) / 427)
                    furthest = max(furthest, abs(y - centreY) / 240)
                }
                note(sprite.defaultX, sprite.defaultY)
                for command in sprite.commands {
                    switch command.payload {
                    case let .move(sx, sy, ex, ey): note(sx, sy); note(ex, ey)
                    case let .moveX(sx, ex): note(sx, centreY); note(ex, centreY)
                    case let .moveY(sy, ey): note(centreX, sy); note(centreX, ey)
                    default: break
                    }
                }

                total += 1
                if furthest > 1 { offStage += 1 }
            }

            guard total > 0 else { continue }
            let share = Double(offStage) / Double(total)

            // A few reaching the edge is fine — embers leaving the top of a
            // fire is what embers do. Most of a layer out there is a layer
            // aimed at nothing.
            #expect(
                share < 0.35,
                "\(preset.id)/\(layer.name) sends \(Int(share * 100))% of its particles off screen",
            )
        }
    }

    /// A layer's particles have to be sized against what they belong to.
    ///
    /// The failure this exists for, twice in one preset: the built-in textures
    /// are **512px square** and the drawn shapes are 64, so the same `Scale`
    /// means eight times the size depending on the sprite. The orb's beam came
    /// out 1465px tall — three times the stage — and its "bands" were 414px
    /// arcs draped over a 220px sphere. Both read as a white smear, and
    /// neither was a positioning bug, which is where I looked first.
    @Test("no layer draws particles larger than the stage", arguments: EmitterEffect.compoundPresets)
    func particlesAreSanelySized(preset: EffectPreset) {
        // The tunnel grows its arcs until they sweep past the viewer, so
        // outgrowing the frame is the effect rather than a mistake in it.
        guard preset.id != "tunnel" else { return }

        for layer in [EffectPreset.Layer(
            effectType: preset.effectType, name: "parent", values: preset.values,
        )] + preset.layers {
            guard case let .text(path) = layer.values[EmitterEffect.Param.sprite] else { continue }

            // The shapes the app draws are 64px; the files it ships are 512.
            let texture: Double = BuiltInSprite.shapes.contains(path) ? 64 : 512

            let node = EffectNode(
                id: "sized", type: layer.effectType, name: layer.name,
                startTime: 0, duration: preset.duration, seed: 4, values: layer.values,
            )
            let prepared = StoryboardResolver.prepare(evaluator.evaluate(node))

            var tallest = 0.0
            for fraction in [0.25, 0.5, 0.75] {
                var states: [SpriteRenderState] = []
                StoryboardResolver.resolve(prepared, at: preset.duration * fraction, into: &states)
                for state in states where state.visible && state.opacity > 0.02 {
                    tallest = max(tallest, Double(state.scaleY) * texture)
                    tallest = max(tallest, Double(state.scaleX) * texture)
                }
            }

            // The stage is 854×480. A particle larger than the whole frame is
            // not a particle — and one at that size stacked a dozen deep is
            // the white wash this caught.
            #expect(
                tallest < 854,
                "\(preset.id)/\(layer.name) draws \(Int(tallest))px particles on a 854×480 stage",
            )
        }
    }

    /// Hiding a layer removes it from the file, not just from the canvas.
    ///
    /// The distinction matters: an eye that only dims the preview would leave
    /// every one of those sprites in the exported storyboard, so a layer
    /// someone deliberately switched off would still be in the published map.
    /// The export writes the sprites the canvas is drawing, so the two cannot
    /// drift — this pins that they do not.
    @Test("a hidden layer reaches neither the canvas nor the file")
    func hiddenLayersAreNotExported() throws {
        let preset = try #require(
            EmitterEffect.compoundPresets.first { !$0.layers.isEmpty },
        )
        var placed = node(preset)

        let whole = evaluator.evaluate(placed)
        let hiddenName = placed.layers[0].name
        let hiddenID = placed.layers[0].id

        placed.layers[0].isVisible = false
        let reduced = evaluator.evaluate(placed)

        #expect(reduced.count < whole.count, "hiding \(hiddenName) changed nothing")

        // Not one sprite from that layer survives — a layer's id prefixes
        // everything it makes, so this catches a partial removal too.
        #expect(
            !reduced.contains { ClipBounds.sprite($0.id, belongsTo: hiddenID) },
            "\(hiddenName) still has sprites in the output",
        )

        // And the rest is untouched: hiding one layer is not an edit to the
        // others, so their sprites have to come out identical.
        let survivors = whole.filter { !ClipBounds.sprite($0.id, belongsTo: hiddenID) }
        #expect(reduced.count == survivors.count)
        #expect(reduced.map(\.id) == survivors.map(\.id))
    }

    /// The same for a whole clip, which is the other half of the eye.
    @Test("a hidden clip produces nothing at all")
    func hiddenClipsAreNotExported() throws {
        let preset = try #require(EmitterEffect.compoundPresets.first)
        var placed = node(preset)
        placed.isVisible = false

        #expect(evaluator.evaluate(placed).isEmpty)
    }
}
