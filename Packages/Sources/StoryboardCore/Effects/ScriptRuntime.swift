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

    /// One line a script printed.
    public struct LogLine: Sendable, Equatable {
        public enum Level: Sendable, Equatable {
            case log
            case warn
            case error
        }

        public let level: Level
        public let message: String

        public init(level: Level, message: String) {
            self.level = level
            self.message = message
        }
    }

    public struct Outcome: Sendable {
        public var sprites: [StoryboardSprite]
        public var diagnostics: [Diagnostic]

        /// The controls the script declared, if it declared any.
        ///
        /// `nil` when the script never called `params()`, which is different
        /// from an empty list: a script that declares nothing should keep
        /// whatever the inspector already had rather than have it cleared by a
        /// run that never mentioned it.
        public var declared: [EffectParameter]?

        /// What the script printed, in order.
        ///
        /// `console.log` was installed as a no-op so a script reaching for it
        /// would not die — which is the right instinct and the wrong result:
        /// somebody logs precisely when they cannot work out what a script did,
        /// and a log going nowhere is the one moment that help is missing.
        public var logs: [LogLine]

        public init(
            sprites: [StoryboardSprite],
            diagnostics: [Diagnostic],
            logs: [LogLine] = [],
            declared: [EffectParameter]? = nil,
        ) {
            self.sprites = sprites
            self.diagnostics = diagnostics
            self.logs = logs
            self.declared = declared
        }
    }

    /// Installed by the app at launch.
    nonisolated(unsafe) public static var run: (@Sendable (Request) -> Outcome)?

    /// What the last evaluation reported, by node.
    ///
    /// A ledger beside the sprites rather than a return value, because
    /// `Effect.evaluate` cannot throw and must not fail the document for one
    /// broken clip. The UI reads it after a pass lands.
    ///
    /// Replaced per node rather than appended: a problem fixed in one pass must
    /// not still be listed in the next, and a log from a run that is over is
    /// noise pretending to be current.
    nonisolated(unsafe) private static var reports: [String: Report] = [:]
    private static let reportLock = NSLock()

    /// What one node's last run had to say.
    public struct Report: Sendable, Equatable {
        public var diagnostics: [Diagnostic]
        public var logs: [LogLine]

        /// The controls the run declared, if it declared any.
        ///
        /// Carried here rather than written onto the node during `evaluate`:
        /// mutating the document from inside an evaluation of that document is
        /// how a pass ends up reading state its own run just changed. The shell
        /// picks it up after the pass lands.
        public var declared: [EffectParameter]?

        public init(
            diagnostics: [Diagnostic],
            logs: [LogLine],
            declared: [EffectParameter]? = nil,
        ) {
            self.diagnostics = diagnostics
            self.logs = logs
            self.declared = declared
        }

        public var isEmpty: Bool {
            diagnostics.isEmpty && logs.isEmpty && declared == nil
        }
    }

    /// Records what a node's run reported.
    public static func record(_ report: Report, for nodeID: String) {
        reportLock.withLock {
            if report.isEmpty {
                reports.removeValue(forKey: nodeID)
            } else {
                reports[nodeID] = report
            }
        }
    }

    /// What a node's last run reported, if anything.
    public static func report(for nodeID: String) -> Report? {
        reportLock.withLock { reports[nodeID] }
    }

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
    ///
    /// > Important: **`run` is one global, and swift-testing runs suites in
    /// parallel.** Save-and-restore is correct in series and useless against a
    /// second suite doing the same thing at the same moment — one leaves its
    /// `defer` and pulls the runtime out from under the other mid-evaluation.
    /// It showed up as a Grid test reporting 0 sprites where it wanted 96, on
    /// roughly one run in three, having passed twenty times before. Every suite
    /// that installs here is `.serialized` and shares one lock, which is why
    /// these helpers exist rather than each test setting the property itself.
    static func withoutRuntime<T>(_ body: () throws -> T) rethrows -> T {
        try holding(nil, body)
    }

    /// Runs `body` with `runtime` installed, restoring whatever was there.
    static func withRuntime<T>(
        _ runtime: @escaping @Sendable (Request) -> Outcome,
        _ body: () throws -> T,
    ) rethrows -> T {
        try holding(runtime, body)
    }

    /// Holds the seam at one value for the duration of `body`.
    ///
    /// The lock is what makes this safe, not the save-and-restore: two suites
    /// swapping one global at the same time is the race, and only one of them
    /// can be inside here at a time.
    private static func holding<T>(
        _ runtime: (@Sendable (Request) -> Outcome)?,
        _ body: () throws -> T,
    ) rethrows -> T {
        seamLock.lock()
        let saved = run
        run = runtime
        defer {
            run = saved
            seamLock.unlock()
        }
        return try body()
    }
}

/// Guards the scripting seam while a test holds it at a known value.
private let seamLock = NSLock()
