import Foundation
import Testing

@testable import StoryboardCore
@testable import StoryboardScripting

/// Every command the format has, reachable from a script.
///
/// The bridge shipped with four of nine. Nothing was broken — what a script
/// could not do was simply absent, which is the worst way for a gap to exist:
/// `scaleVec` missing means a letterbox bar cannot be written at all, and
/// nothing says so.
@Suite("Sprite bridge", .serialized)
struct SpriteBridgeTests {
    private func sprites(_ source: String) -> [StoryboardSprite] {
        ScriptEngine().run(ScriptRuntime.Request(
            nodeID: "fx", idPrefix: "fx", source: source,
            values: [:], duration: 4000, seed: 42,
        )).sprites
    }

    private func kind(of source: String) -> CommandKind? {
        sprites("sprite(Image.soft).\(source)").first?.commands.first?.kind
    }

    /// Each of the nine, by the call a script would write.
    @Test("every command kind is reachable", arguments: [
        ("fade(0, 100, 0, 1)", CommandKind.fade),
        ("move(0, 100, 0, 0, 10, 10)", .move),
        ("moveX(0, 100, 0, 10)", .moveX),
        ("moveY(0, 100, 0, 10)", .moveY),
        ("scale(0, 100, 1, 2)", .scale),
        ("scaleVec(0, 100, 1, 1, 2, 3)", .vectorScale),
        ("rotate(0, 100, 0, 1)", .rotate),
        ("color(0, 100, 255, 0, 0, 0, 0, 255)", .color),
        ("additive(0, 100)", .parameter),
    ])
    func everyKindIsReachable(call: String, expected: CommandKind) {
        #expect(kind(of: call) == expected, "\(call) did not produce a \(expected.rawValue) command")
    }

    /// The optional easing, on every command that takes one.
    @Test("an easing can be given", arguments: [
        "fade(Ease.quadOut, 0, 100, 0, 1)",
        "move(Ease.quadOut, 0, 100, 0, 0, 10, 10)",
        "scaleVec(Ease.quadOut, 0, 100, 1, 1, 2, 3)",
        "color(Ease.quadOut, 0, 100, 255, 0, 0, 0, 0, 255)",
    ])
    func easingIsAccepted(call: String) {
        let command = sprites("sprite(Image.soft).\(call)").first?.commands.first

        #expect(command?.timing.easing == Easing.quadOut, "\(call) lost its easing")
        #expect(command?.timing.startTime == 0)
        #expect(command?.timing.endTime == 100)
    }

    /// The three `_P` flags are distinct.
    @Test("each flag is its own kind", arguments: [
        ("additive(0, 100)", ParameterKind.additive),
        ("flipH(0, 100)", .flipHorizontal),
        ("flipV(0, 100)", .flipVertical),
    ])
    func flagsAreDistinct(call: String, expected: ParameterKind) throws {
        let command = try #require(sprites("sprite(Image.soft).\(call)").first?.commands.first)

        guard case let .parameter(kind) = command.payload else {
            Issue.record("\(call) did not produce a parameter command")
            return
        }
        #expect(kind == expected)
    }

    // MARK: - Names that do not exist

    /// A misspelled constant is an error, not a different animation.
    ///
    /// Measured before this: `Ease.outQuad` — the spelling that does not exist
    /// — reached the bridge as `undefined`, became NaN, was made finite as 0,
    /// and 0 is `linear`. One sprite, no diagnostic, and an animation quietly
    /// not the one asked for. It was on screen in a saved project for a while
    /// and nothing said so.
    @Test("an unknown constant is reported", arguments: [
        "sprite(Image.soft).move(Ease.outQuad, 0, 900, 0, 0, 10, 10)",
        "sprite(Image.blurry)",
        "sprite(Image.soft, { layer: Layer.Middle })",
        "sprite(Image.soft, { origin: Origin.Middle })",
    ])
    func unknownConstantIsReported(source: String) {
        let outcome = ScriptEngine().run(ScriptRuntime.Request(
            nodeID: "fx", idPrefix: "fx", source: source,
            values: [:], duration: 4000, seed: 1,
        ))

        #expect(!outcome.diagnostics.isEmpty, "\(source) failed silently")
        #expect(outcome.sprites.isEmpty)
    }

    /// The real names still work, which is what makes the guard worth having
    /// rather than merely strict.
    @Test("the real names are accepted", arguments: [
        "sprite(Image.soft).move(Ease.quadOut, 0, 900, 0, 0, 10, 10)",
        "sprite(Image.glow)",
        "sprite(Image.soft, { layer: Layer.Overlay })",
        "sprite(Image.soft, { origin: Origin.TopLeft })",
    ])
    func realNamesAreAccepted(source: String) {
        let outcome = ScriptEngine().run(ScriptRuntime.Request(
            nodeID: "fx", idPrefix: "fx", source: source,
            values: [:], duration: 4000, seed: 1,
        ))

        #expect(outcome.diagnostics.isEmpty, "\(source) was refused")
        #expect(outcome.sprites.count == 1)
    }

    /// The engine still has to be able to inspect these objects.
    ///
    /// A proxy that throws on every unknown key throws on the symbols the
    /// language itself reads — `Symbol.toPrimitive` when something is logged
    /// or coerced — which breaks the language rather than catching a typo.
    @Test("the language can still inspect a namespace", arguments: [
        "String(Image)",
        "`${Object.keys(Ease).length}`",
        "JSON.stringify(Object.keys(Layer))",
    ])
    func namespacesRemainInspectable(expression: String) {
        let outcome = ScriptEngine().run(ScriptRuntime.Request(
            nodeID: "fx", idPrefix: "fx",
            source: "const x = \(expression); sprite(Image.soft)",
            values: [:], duration: 4000, seed: 1,
        ))

        #expect(outcome.diagnostics.isEmpty, "\(expression) threw")
        #expect(outcome.sprites.count == 1)
    }

    /// Colour channels are 0–255 as the format has them, not 0–1.
    ///
    /// A script writing `color(0, 100, 1, 0, 0, …)` for red would get black,
    /// and nothing would say why — so the range is worth one test rather than
    /// only a note in a summary.
    @Test("colour channels pass through unscaled")
    func colourIsUnscaled() throws {
        let command = try #require(
            sprites("sprite(Image.soft).color(0, 100, 255, 128, 0, 0, 0, 255)").first?.commands.first,
        )

        guard case let .color(startR, startG, startB, _, _, endB) = command.payload else {
            Issue.record("not a colour command")
            return
        }
        #expect(startR == 255)
        #expect(startG == 128)
        #expect(startB == 0)
        #expect(endB == 255)
    }
}
