import Foundation

/// The seam the core reaches through to run an author's script.
///
/// Core cannot run JavaScript, so it declares what it needs here and the app
/// installs an implementation — the same shape as ``TextMetrics/measure`` and
/// `AudioSpectrum.analyse`, and for the same reason: the core's tests keep
/// running with no engine, no GPU and no window.
///
/// It differs from both in one deliberate way. Those fall back to a stand-in
/// because the *shape* of the answer is known — a travelling wave, a glyph
/// width near enough to lay text out. Arbitrary code has no honest stand-in, so
/// with nothing installed a script draws nothing and says why. Silence alone
/// would look exactly like a script that legitimately drew nothing, leaving the
/// author tuning code that never had an engine to run on.
public enum ScriptRuntime {
    /// Everything a script is allowed to know about where it is running.
    ///
    /// Deliberately not in here: where the clip sits on the timeline. A script
    /// generates over `0...duration` and the evaluator shifts the result into
    /// place afterwards. One that could read its own `startTime` would draw
    /// *different* particles when dragged instead of the same ones moved — and
    /// moving a clip being safe is what the whole timeline rests on.
    public struct Request: Sendable {
        /// Which node asked, so a diagnostic can be shown on its clip.
        public let nodeID: String
        /// What every sprite id must begin with, so the canvas can tell which
        /// clip a sprite belongs to.
        public let idPrefix: String
        public let source: String
        /// The values behind the controls the script declared.
        public let values: [String: EffectValue]
        /// The clip's length, in milliseconds of local time.
        public let duration: Double
        /// Fixes the random stream, so two evaluations agree.
        public let seed: UInt64

        public init(
            nodeID: String,
            idPrefix: String,
            source: String,
            values: [String: EffectValue],
            duration: Double,
            seed: UInt64,
        ) {
            self.nodeID = nodeID
            self.idPrefix = idPrefix
            self.source = source
            self.values = values
            self.duration = duration
            self.seed = seed
        }
    }

    /// What went wrong, in terms the inspector can show on the clip.
    ///
    /// The cases stay distinct because they call for different reactions: a
    /// compile error is a typo to fix, a missing runtime is a broken build, and
    /// an empty script is somebody who has not started yet.
    public enum Diagnostic: Sendable, Equatable {
        /// No implementation installed — a packaging fault, not the author's.
        case noRuntime
        /// The clip has no code in it yet.
        case noSource
        case compileFailed(String)
        case runtimeFailed(String)
        /// More sprites than a storyboard can carry; the rest were dropped.
        case spritesTruncated(produced: Int, kept: Int)
        /// More commands than a storyboard can carry; the rest were dropped.
        case commandsTruncated(produced: Int, kept: Int)
    }

    public struct Outcome: Sendable {
        public var sprites: [StoryboardSprite]
        public var diagnostics: [Diagnostic]

        public init(sprites: [StoryboardSprite], diagnostics: [Diagnostic]) {
            self.sprites = sprites
            self.diagnostics = diagnostics
        }
    }

    /// Installed by the app at launch.
    nonisolated(unsafe) public static var run: (@Sendable (Request) -> Outcome)?

    /// Runs a script, or explains why it could not.
    public static func sprites(for request: Request) -> Outcome {
        guard !request.source.isEmpty else {
            return Outcome(sprites: [], diagnostics: [.noSource])
        }
        guard let run else {
            return Outcome(sprites: [], diagnostics: [.noRuntime])
        }
        return run(request)
    }
}

// MARK: - Testing

public extension ScriptRuntime {
    /// Runs `body` with no runtime installed, restoring whatever was there.
    ///
    /// Here rather than in the test target because the property is
    /// `nonisolated(unsafe)`: a test that sets it and forgets to put it back
    /// changes the result of every test that runs afterwards, and which of them
    /// that is depends on execution order.
    static func withoutRuntime<T>(_ body: () throws -> T) rethrows -> T {
        let saved = run
        run = nil
        defer { run = saved }
        return try body()
    }

    /// Runs `body` with `runtime` installed, restoring whatever was there.
    static func withRuntime<T>(
        _ runtime: @escaping @Sendable (Request) -> Outcome,
        _ body: () throws -> T,
    ) rethrows -> T {
        let saved = run
        run = runtime
        defer { run = saved }
        return try body()
    }
}
