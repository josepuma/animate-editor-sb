import Testing

@testable import StoryboardCore

@Suite("Text effect")
struct TextEffectTests {
    private func sprites(
        _ text: String,
        duration: Double = 3000,
        configure: (inout EffectNode) -> Void = { _ in },
    ) -> [StoryboardSprite] {
        var document = EffectDocument()
        var node = document.add(TextEffect.descriptor, at: 0, duration: duration)
        node.values[TextEffect.Param.text] = .text(text)
        configure(&node)
        document[node.id] = node
        return EffectEvaluator().evaluate(document)
    }

    /// One sprite per character is the whole point: a word held in one sprite
    /// can only move as a word, which is a caption rather than motion graphics.
    @Test("each character becomes its own sprite")
    func onePerCharacter() {
        #expect(sprites("ABC").count == 3)
    }

    /// A space takes its width and draws nothing — a sprite for it would be an
    /// invisible quad carrying commands into the file.
    @Test("spaces take room without becoming sprites")
    func spacesAreNotDrawn() {
        #expect(sprites("A B").count == 2)
    }

    @Test("empty text draws nothing")
    func emptyDrawsNothing() {
        #expect(sprites("").isEmpty)
    }

    /// The same character in the same style resolves to one image however many
    /// times it appears, so a repeated letter costs one texture.
    @Test("repeated characters share one path")
    func repeatedCharactersDeduplicate() {
        let paths = Set(sprites("AAA").map(\.filePath))
        #expect(paths.count == 1)
    }

    @Test("different characters get different paths")
    func differentCharactersDiffer() {
        #expect(Set(sprites("AB").map(\.filePath)).count == 2)
    }

    /// Style is part of the identity: the same letter at another size is a
    /// different image.
    @Test("style changes the path")
    func styleChangesThePath() {
        let small = TextSprite.path(for: "A", style: TextStyle(size: 24))
        let large = TextSprite.path(for: "A", style: TextStyle(size: 96))
        #expect(small != large)
    }

    // ─── Layout ──────────────────────────────────────────────────────────────

    /// Laid out around the centre, because the clip's transform turns and
    /// scales about that point — text laid out from a corner would swing around
    /// one end when rotated.
    @Test("text is centred on the clip")
    func textIsCentred() {
        let placed = sprites("ABCD")
        let centre = placed.map(\.defaultX).reduce(0, +) / Double(placed.count)

        #expect(abs(centre - TransformProperty.x.defaultValue) < 1)
    }

    @Test("characters run left to right")
    func charactersAreOrdered() {
        let xs = sprites("ABC").map(\.defaultX)
        #expect(xs == xs.sorted())
    }

    @Test("a second line sits below the first")
    func linesStack() {
        let placed = sprites("A\nB")
        #expect(placed.count == 2)
        #expect(placed[1].defaultY > placed[0].defaultY)
    }

    // ─── Animation ───────────────────────────────────────────────────────────

    /// The stagger is what makes text read as motion graphics rather than as a
    /// caption appearing.
    /// Placed plain, text is text and not a performance: the moves live in the
    /// presets, and a placed effect animates nothing until asked.
    @Test("a placed text effect does not animate")
    func placedTextIsStill() {
        let placed = sprites("ABC")

        // On screen for the whole clip, and identically so for every character.
        let starts = Set(placed.map { $0.commands.map(\.startTime).min() ?? -1 })
        #expect(starts == [0])
        #expect(placed.allSatisfy { sprite in
            sprite.commands.allSatisfy { command in
                if case let .fade(start, end) = command.payload { return start == 1 && end == 1 }
                return true
            }
        })
    }

    @Test("characters arrive one after another")
    func staggerDelaysEachCharacter() {
        let placed = sprites("ABC") { $0.values[TextEffect.Param.stagger] = .number(100) }
        let starts = placed.map { $0.commands.map(\.startTime).min() ?? 0 }

        #expect(starts[0] < starts[1])
        #expect(starts[1] < starts[2])
    }

    @Test("no stagger starts everything together")
    func zeroStaggerIsSimultaneous() {
        let placed = sprites("ABC") { $0.values[TextEffect.Param.stagger] = .number(0) }
        let starts = Set(placed.map { $0.commands.map(\.startTime).min() ?? 0 })

        #expect(starts.count == 1)
    }

    /// Staggering from the end reverses the order without reordering the
    /// sprites themselves — their array order is their draw order.
    @Test("stagger can run from the end")
    func staggerFromEnd() {
        let placed = sprites("ABC") {
            $0.values[TextEffect.Param.stagger] = .number(100)
            $0.values[TextEffect.Param.staggerFrom] = .choice("End")
        }
        let starts = placed.map { $0.commands.map(\.startTime).min() ?? 0 }

        #expect(starts[0] > starts[2])
        // Still in reading order on screen.
        #expect(placed.map(\.defaultX) == placed.map(\.defaultX).sorted())
    }

    /// With a fade asked for, every character starts from nothing — otherwise
    /// the sprite holds its default opacity from the start of the file and the
    /// whole line is visible before its own stagger reaches it.
    @Test("a fade in starts every character from nothing")
    func everyCharacterFadesIn() {
        let faded = sprites("ABC") { $0.values[TextEffect.Param.fadeIn] = .number(200) }
        for sprite in faded {
            let fade = sprite.commands.first { $0.kind == .fade }
            if case let .fade(start, _) = fade?.payload {
                #expect(start == 0)
            } else {
                Issue.record("a character had no fade")
            }
        }
    }

    /// White glyphs tinted by command, so one texture serves every colour.
    @Test("colour is a command, not a different texture")
    func colourIsTinted() {
        let plain = sprites("A")
        let red = sprites("A") {
            $0.values[TextEffect.Param.color] = .color(EffectColor(r: 255, g: 0, b: 0))
        }

        #expect(plain[0].filePath == red[0].filePath)
        #expect(red[0].commands.contains { $0.kind == .color })
    }

    /// What makes a burst read as one: no two characters agree on where they
    /// are going. A shared heading is a slide, however fast it moves.
    @Test("an explode exit sends each character its own way")
    func explodeScattersCharacters() {
        let placed = sprites("ABCDEF") {
            $0.values[TextEffect.Param.fadeOut] = .number(500)
            $0.values[TextEffect.Param.exit] = .choice("Explode")
        }

        var endings: Set<String> = []
        for sprite in placed {
            for command in sprite.commands {
                if case let .move(_, _, endX, endY) = command.payload {
                    endings.insert("\(Int(endX)),\(Int(endY))")
                }
            }
        }

        #expect(endings.count == placed.count)
    }

    /// Text that arrives, holds perfectly still and leaves is three separate
    /// moments; travelling while it holds makes them one.
    @Test("travel moves the line while it holds")
    func travelMovesWhileHolding() {
        let placed = sprites("AB") {
            $0.values[TextEffect.Param.fadeIn] = .number(200)
            $0.values[TextEffect.Param.fadeOut] = .number(200)
            $0.values[TextEffect.Param.driftY] = .number(-100)
        }

        let travelled = placed[0].commands.contains { command in
            if case let .move(_, startY, _, endY) = command.payload {
                return abs((startY - endY) - 100) < 1
            }
            return false
        }
        #expect(travelled)
    }

    /// Reproducible, like every other effect: the preview and the exported file
    /// have to agree.
    @Test("a random stagger repeats for the same seed")
    func randomStaggerIsSeeded() {
        func starts(seed: UInt64) -> [Double] {
            var document = EffectDocument()
            var node = document.add(TextEffect.descriptor, at: 0, duration: 3000)
            node.values[TextEffect.Param.text] = .text("ABCDEF")
            node.values[TextEffect.Param.stagger] = .number(50)
            node.values[TextEffect.Param.staggerFrom] = .choice("Random")
            node.seed = seed
            document[node.id] = node
            return EffectEvaluator().evaluate(document)
                .map { $0.commands.map(\.startTime).min() ?? 0 }
        }

        #expect(starts(seed: 7) == starts(seed: 7))
        #expect(starts(seed: 7) != starts(seed: 8))
    }
}
