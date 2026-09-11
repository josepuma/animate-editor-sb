import Foundation
import Testing

@testable import StoryboardCore

/// A character's fade-out cannot start before it has finished arriving.
///
/// `birth` carries the stagger, so it differs per character, while `death` is
/// the clip's end and is the same for all of them. A late character therefore
/// had its fade-in still running forward while its fade-out had already begun
/// — two commands fighting over the same property, which osu! resolves by
/// letting the last one written win.
///
/// Reported from use on `cascade`: "de la nada al final todas hacen fade-out
/// pero algunas quedan por terminar de hacer fade-in". With stagger 110 and a
/// 700ms fade-in, the twentieth character starts arriving at 2200ms and takes
/// until 2900 — and on a clip whose fade-out is 500ms, anything shorter than
/// 3400ms of clip has them overlapping.
@Suite("Text fade overlap")
struct TextFadeOverlapTests {
    /// No character has its two fades overlapping.
    ///
    /// Parameterised over every preset because the numbers that produce it are
    /// a preset's business, and a new one could reintroduce it.
    @Test("a character's fades never overlap", arguments: TextEffect.presets)
    func fadesNeverOverlap(_ preset: EffectPreset) throws {
        // A line long enough that the last character's stagger is significant,
        // which is the case that breaks.
        let sprites = evaluate(preset: preset, text: "twenty characters her", duration: 4000)

        for sprite in sprites {
            let fades = sprite.commands.compactMap { command -> (Double, Double, Double, Double)? in
                guard case let .fade(start, end) = command.payload else { return nil }
                return (command.startTime, command.endTime, start, end)
            }
            // Rising runs, and falling runs.
            let rising = fades.filter { $0.3 > $0.2 }
            let falling = fades.filter { $0.3 < $0.2 }

            for rise in rising {
                for fall in falling {
                    #expect(
                        fall.0 >= rise.1,
                        """
                        \(preset.id)/\(sprite.id): fade-out starts at \(fall.0) \
                        while the fade-in runs to \(rise.1)
                        """,
                    )
                }
            }
        }
    }

    /// The overlap is worst on a short clip, which is where it was seen.
    @Test("a short clip still lets every character arrive")
    func shortClipStillArrives() throws {
        let cascade = try #require(TextEffect.presets.first { $0.id == "cascade" })
        // Deliberately shorter than stagger × count + fadeIn + fadeOut.
        let sprites = evaluate(preset: cascade, text: "abcdefghijklmnop", duration: 2000)

        #expect(!sprites.isEmpty)
        for sprite in sprites {
            let fades = sprite.commands.compactMap { command -> (Double, Double, Double, Double)? in
                guard case let .fade(start, end) = command.payload else { return nil }
                return (command.startTime, command.endTime, start, end)
            }
            for rise in fades where rise.3 > rise.2 {
                #expect(rise.0 <= rise.1, "\(sprite.id): a fade-in that runs backwards")
                for fall in fades where fall.3 < fall.2 {
                    #expect(fall.0 >= rise.1, "\(sprite.id): overlapping fades on a short clip")
                }
            }
        }
    }

    // MARK: -

    private func evaluate(
        preset: EffectPreset,
        text: String,
        duration: Double,
    ) -> [StoryboardSprite] {
        var document = EffectDocument()
        let track = document.addTrack(layer: .foreground)
        var node = document.add(
            TextEffect.descriptor, at: 0, duration: duration, on: track.id,
        )
        node.values = preset.values
        node.values[TextEffect.Param.text] = .text(text)
        document[node.id] = node

        return EffectEvaluator().evaluate(document)
    }
}
