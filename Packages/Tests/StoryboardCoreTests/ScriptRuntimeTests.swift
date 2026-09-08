import Foundation
import Testing

@testable import StoryboardCore

/// The seam the core reaches through to run a script.
///
/// Core cannot run JavaScript, so it declares what it needs and something above
/// installs it — the same shape as `TextMetrics.measure` and
/// `AudioSpectrum.analyse`.
///
/// It differs from both in one deliberate way, which these tests pin down: they
/// fall back to a stand-in because the *shape* of the answer is known — a wave,
/// an approximate glyph width. Arbitrary code has no honest stand-in, so the
/// fallback here draws nothing and says why.
@Suite("Script runtime seam", .serialized)
struct ScriptRuntimeTests {
    private func request(source: String = "sprite(Image.soft)") -> ScriptRuntime.Request {
        ScriptRuntime.Request(
            nodeID: "fx",
            idPrefix: "fx",
            source: source,
            values: [:],
            duration: 4000,
            seed: 42,
        )
    }

    /// With nothing installed, a script draws nothing and reports why.
    ///
    /// Not an empty result on its own: silence would look identical to a script
    /// that legitimately drew nothing, and the author would be left tuning code
    /// that never had an engine to run on.
    @Test("no runtime draws nothing and says so")
    func noRuntimeReports() {
        ScriptRuntime.withoutRuntime {
            let outcome = ScriptRuntime.sprites(for: request())

            #expect(outcome.sprites.isEmpty)
            #expect(outcome.diagnostics.contains(.noRuntime))
        }
    }

    /// An installed runtime is asked, and its answer is passed through.
    @Test("an installed runtime is used")
    func installedRuntimeIsUsed() {
        let sprite = StoryboardSprite(
            id: "fx/s0",
            layer: .foreground,
            origin: .centre,
            filePath: BuiltInSprite.soft,
            defaultX: 320,
            defaultY: 240,
        )

        ScriptRuntime.withRuntime({ _ in
            ScriptRuntime.Outcome(sprites: [sprite], diagnostics: [])
        }, {
            let outcome = ScriptRuntime.sprites(for: request())

            #expect(outcome.sprites.count == 1)
            #expect(outcome.sprites.first?.id == "fx/s0")
            #expect(outcome.diagnostics.isEmpty)
        })
    }

    /// The request carries what a script is allowed to know, and nothing more.
    ///
    /// Notably absent: where the clip sits. A script generates over
    /// `0...duration` and the evaluator shifts it afterwards — a script that
    /// could read its own `startTime` would draw *different* particles when
    /// dragged rather than the same ones moved, which is the property that
    /// makes moving a clip safe.
    @Test("the request cannot tell a script where its clip sits")
    func requestHidesPlacement() {
        let fields = "\(request())"

        #expect(fields.contains("4000"), "the request must carry the local duration")
        #expect(!fields.contains("startTime"), "a script must not be able to read its placement")
    }

    /// Diagnostics have to be distinguishable, or the UI cannot say what broke.
    @Test("a compile failure and a runtime failure are different diagnostics")
    func failuresAreDistinct() {
        #expect(ScriptRuntime.Diagnostic.compileFailed("x") != ScriptRuntime.Diagnostic.runtimeFailed("x"))
        #expect(ScriptRuntime.Diagnostic.noRuntime != ScriptRuntime.Diagnostic.noSource)
    }
}
