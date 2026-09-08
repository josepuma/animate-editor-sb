import Foundation
import Testing

@testable import StoryboardCore

/// The ceiling on what a script may produce.
///
/// Every effect written by hand is self-limiting by construction: the emitter's
/// count cannot exceed `EmitterEffect.maximumCount` because its own parameter
/// range says so. A script has no such shape — a loop with the wrong bound
/// emits fifty thousand sprites, and each one is a line in a text file the game
/// has to open.
@Suite("Script clamp")
struct ScriptClampTests {
    private func sprite(_ index: Int, commands: Int = 1) -> StoryboardSprite {
        StoryboardSprite(
            id: "fx/s\(index)",
            layer: .foreground,
            origin: .centre,
            filePath: BuiltInSprite.soft,
            defaultX: 320,
            defaultY: 240,
            commands: (0..<commands).map { _ in
                Command(easing: .linear, startTime: 0, endTime: 1000, payload: .fade(start: 0, end: 1))
            },
        )
    }

    // MARK: - The numbers themselves

    /// The sprite ceiling matches the emitter's, deliberately.
    ///
    /// Two different answers to "how many sprites can one clip hold" would be
    /// two numbers to keep in step, and nothing about a script makes it able to
    /// afford more than an emitter can.
    @Test("the sprite ceiling is the emitter's ceiling")
    func spriteCeilingMatchesEmitter() {
        #expect(ScriptLimits.maximumSprites == EmitterEffect.maximumCount)
    }

    /// The command ceiling is derived from the sprite ceiling, not invented.
    @Test("the command ceiling is the sprite ceiling times a per-sprite budget")
    func commandCeilingIsDerived() {
        #expect(ScriptLimits.maximumCommands == ScriptLimits.maximumSprites * ScriptLimits.commandsPerSprite)
        #expect(ScriptLimits.maximumCommands == 40_000)
    }

    // MARK: - Truncating, not failing

    @Test("too many sprites are truncated to the ceiling")
    func spritesTruncate() {
        let produced = (0..<(ScriptLimits.maximumSprites + 1000)).map { sprite($0) }

        let clamped = ScriptLimits.clamped(produced)

        #expect(clamped.sprites.count == ScriptLimits.maximumSprites)
        #expect(clamped.diagnostics.contains(
            .spritesTruncated(produced: ScriptLimits.maximumSprites + 1000, kept: ScriptLimits.maximumSprites),
        ))
    }

    /// The ones kept are the first ones, in the order the script made them.
    ///
    /// Keeping an arbitrary subset would make the same script draw differently
    /// between runs for no reason the author could see.
    @Test("truncation keeps the earliest sprites in creation order")
    func truncationKeepsTheFirst() {
        let produced = (0..<(ScriptLimits.maximumSprites + 10)).map { sprite($0) }

        let clamped = ScriptLimits.clamped(produced)

        #expect(clamped.sprites.first?.id == "fx/s0")
        #expect(clamped.sprites.last?.id == "fx/s\(ScriptLimits.maximumSprites - 1)")
    }

    /// A script within the ceiling is passed through untouched, with nothing to
    /// report — a diagnostic on a healthy clip is noise that teaches the author
    /// to ignore diagnostics.
    @Test("output within the ceiling is untouched")
    func withinCeilingIsUntouched() {
        let produced = (0..<10).map { sprite($0) }

        let clamped = ScriptLimits.clamped(produced)

        #expect(clamped.sprites.count == 10)
        #expect(clamped.diagnostics.isEmpty)
    }

    /// Few sprites can still be far too many commands.
    ///
    /// The sprite count alone is not the file's size: one sprite carrying
    /// thousands of commands writes thousands of lines, and clamping only
    /// sprites would let that straight through.
    @Test("too many commands are truncated even when sprite count is fine")
    func commandsTruncate() {
        // Ten sprites, each far past the per-sprite budget.
        let produced = (0..<10).map { sprite($0, commands: ScriptLimits.maximumCommands) }

        let clamped = ScriptLimits.clamped(produced)

        let total = clamped.sprites.reduce(0) { $0 + $1.commands.count }
        #expect(total <= ScriptLimits.maximumCommands)
        #expect(clamped.diagnostics.contains { diagnostic in
            if case .commandsTruncated = diagnostic { return true }
            return false
        })
    }

    /// A sprite kept after the command ceiling is reached keeps no commands, so
    /// it is dropped rather than left as a sprite that draws with its defaults
    /// from the start of the file.
    @Test("a sprite left with no commands is dropped, not left drawing")
    func emptySpritesAreDropped() {
        let produced = (0..<10).map { sprite($0, commands: ScriptLimits.maximumCommands) }

        let clamped = ScriptLimits.clamped(produced)

        #expect(clamped.sprites.allSatisfy { !$0.commands.isEmpty })
    }
}
