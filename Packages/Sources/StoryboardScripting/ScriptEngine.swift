import Foundation
import JavaScriptCore
import StoryboardCore

/// Runs one script and collects the sprites it built.
///
/// A fresh `JSContext` per invocation, deliberately. A pooled one would carry
/// whatever the last script left on the global object into the next, and two
/// scripts that agree separately but not together is the kind of bug that only
/// shows up in someone else's project.
public struct ScriptEngine: Sendable {
    /// Whether loops are made to count themselves.
    ///
    /// Only ever false in a test that has to prove the rewrite changes nothing
    /// about a script that terminates. There is no way to turn it off from the
    /// app, because a script that can outrun its guard is a hung editor.
    let instrumentsLoops: Bool

    public init() {
        instrumentsLoops = true
    }

    init(instrumentsLoops: Bool) {
        self.instrumentsLoops = instrumentsLoops
    }

    /// Everything a script can see, by name.
    ///
    /// The context is built by **adding** to an empty one. That is the whole
    /// security model: a script cannot read a file because no function exists
    /// that reads files — there is nothing to get around. A blocklist would
    /// only stop what somebody thought to list, and scanning source for
    /// suspicious code cannot work at all, since `"read" + "File"` and
    /// `eval(atob(…))` say the same thing unrecognisably.
    ///
    /// JavaScriptCore hands over a context already carrying the language, so
    /// the ones that read the outside world or the clock are removed by name
    /// below. Both halves are asserted by the tests, as equality against this
    /// list rather than as the absence of a blocklist.
    /// Read off a real context rather than written from memory. The list JSC
    /// actually installs is not the list anyone would guess — `Atomics`, `Intl`
    /// and `Float16Array` were all missing from the first attempt, and a
    /// hand-written list that disagrees fails the allow-list test for a reason
    /// that has nothing to do with security.
    public static let allowedGlobals: [String] = [
        // The language, as JavaScriptCore provides it.
        "AggregateError", "Array", "ArrayBuffer", "Atomics", "BigInt",
        "BigInt64Array", "BigUint64Array", "Boolean", "DataView", "Error",
        "EvalError", "FinalizationRegistry", "Float16Array", "Float32Array",
        "Float64Array", "Function", "Infinity", "Int16Array", "Int32Array",
        "Int8Array", "Intl", "Iterator", "JSON", "Map", "Math", "NaN", "Number",
        "Object", "Promise", "Proxy", "RangeError", "ReferenceError", "Reflect",
        "RegExp", "Set", "String", "Symbol", "SyntaxError", "TypeError",
        "URIError", "Uint16Array", "Uint32Array", "Uint8Array",
        "Uint8ClampedArray", "WeakMap", "WeakRef", "WeakSet",
        "decodeURI", "decodeURIComponent", "encodeURI", "encodeURIComponent",
        "escape", "eval", "globalThis", "isFinite", "isNaN", "parseFloat",
        "parseInt", "undefined", "unescape",
        // The storyboard API.
        "Ease", "Image", "Layer", "Origin", "console", "duration", "param",
        "params", "rng", "sprite",
        // The loop guard and its counter.
        //
        // Visible rather than hidden: they have to be callable from inside the
        // loops they protect, so they cannot be deleted before the script runs.
        // Declared here because the allow-list test asserts equality — it
        // caught these the moment instrumentation landed, which is the test
        // doing exactly its job.
        LoopInstrumenter.guardName, "__ticks",
    ]

    /// Names JavaScriptCore installs that a script must not reach.
    ///
    /// The clock belongs here alongside the obvious ones: `Date.now()` is a
    /// fresh number every run, so it breaks the preview/export agreement in
    /// exactly the way `Math.random` does. The original constraint named only
    /// `Math.random`, which would have left this open.
    static let removedGlobals = [
        "Date", "performance", "crypto",
        "require", "fetch", "XMLHttpRequest", "process", "WebAssembly",
        "setTimeout", "setInterval", "clearTimeout", "clearInterval",
        "window", "self", "location", "navigator",
    ]

    public func run(_ request: ScriptRuntime.Request) -> ScriptRuntime.Outcome {
        guard let context = JSContext() else {
            return ScriptRuntime.Outcome(sprites: [], diagnostics: [.runtimeFailed("no JS context")])
        }

        var thrown: String?
        context.exceptionHandler = { _, value in
            thrown = value?.toString() ?? "unknown error"
        }

        let collector = SpriteCollector(idPrefix: request.idPrefix)
        let logs = LogCollector()
        let declarations = DeclarationCollector()
        install(
            into: context,
            request: request,
            collector: collector,
            logs: logs,
            declarations: declarations,
        )

        if instrumentsLoops {
            context.evaluateScript(LoopInstrumenter.preamble)
            context.evaluateScript(LoopInstrumenter.instrument(request.source))
        } else {
            context.evaluateScript(request.source)
        }

        if let thrown {
            // The logs travel with the failure. A script that threw is exactly
            // when the lines printed before it matter — dropping them here
            // would take away the only trace of how far it got.
            return ScriptRuntime.Outcome(
                sprites: [],
                diagnostics: [.runtimeFailed(thrown)],
                logs: logs.lines(),
                declared: declarations.parameters(),
            )
        }

        // A call given a name that does not exist is a failure, not a sprite.
        //
        // Returning the sprite anyway is what let `Ease.outQuad` animate as
        // linear for a while: the clip drew, so nothing looked wrong.
        if collector.undefinedArgument {
            return ScriptRuntime.Outcome(
                sprites: [],
                diagnostics: [.runtimeFailed(
                    "a value passed to a sprite command does not exist — check a name like Ease.quadOut",
                )],
                logs: logs.lines(),
                declared: declarations.parameters(),
            )
        }

        let clamped = ScriptLimits.clamped(collector.sprites())
        var diagnostics = clamped.diagnostics
        if let unknown = declarations.unknownDiagnostic() {
            diagnostics.append(unknown)
        }
        if collector.refused > 0 {
            diagnostics.append(.spritesTruncated(
                produced: clamped.sprites.count + collector.refused,
                kept: clamped.sprites.count,
            ))
        }
        return ScriptRuntime.Outcome(
            sprites: clamped.sprites,
            diagnostics: diagnostics,
            logs: logs.lines(),
            declared: declarations.parameters(),
        )
    }

    // MARK: - Building the context

    private func install(
        into context: JSContext,
        request: ScriptRuntime.Request,
        collector: SpriteCollector,
        logs: LogCollector,
        declarations: DeclarationCollector,
    ) {
        remove(Self.removedGlobals, from: context)
        lockRandom(in: context, seed: request.seed)
        installConsole(in: context, into: logs)

        context.setObject(request.duration, forKeyedSubscript: "duration" as NSString)
        context.setObject(ImageConstants.table, forKeyedSubscript: "Image" as NSString)
        context.setObject(EaseConstants.table, forKeyedSubscript: "Ease" as NSString)
        context.setObject(LayerConstants.table, forKeyedSubscript: "Layer" as NSString)
        context.setObject(LayerConstants.originTable, forKeyedSubscript: "Origin" as NSString)

        installRandom(in: context, seed: request.seed)
        installParameters(in: context, values: request.values, declarations: declarations)
        collector.install(in: context)
    }

    /// Removes a global by name.
    ///
    /// `delete globalThis.X` rather than assigning `undefined`: assigning
    /// leaves an own property whose value is `undefined`, which still shows up
    /// in `Object.getOwnPropertyNames` — so the allow-list test would see a
    /// name that a script cannot use, and the two would disagree about what
    /// "absent" means. Measured against a real context, both forms make
    /// `typeof` report `undefined`; only `delete` also removes the name.
    private func remove(_ names: [String], from context: JSContext) {
        let script = names.map { "delete globalThis.\($0);" }.joined()
        context.evaluateScript(script)
    }

    /// Replaces `Math.random` with the seeded stream, and locks it there.
    ///
    /// `writable: false, configurable: false` is not belt-and-braces. Measured
    /// against a real `JSContext`: installed as a plain assignment, one line
    /// (`Math.random = () => 0.9`) replaces it and another (`delete
    /// Math.random`) removes it entirely. Locked, reassignment and delete both
    /// fail silently and `Function('return Math.random')()` and `eval` both
    /// resolve to the locked function.
    ///
    /// A script that reached a real random number would draw a different field
    /// in the preview than in the exported file — a disagreement nobody notices
    /// until the `.osb` is already published.
    private func lockRandom(in context: JSContext, seed: UInt64) {
        let stream = RandomStream(seed: seed)
        let random: @convention(block) () -> Double = { stream.next() }

        context.setObject(random, forKeyedSubscript: "__seededRandom" as NSString)
        context.evaluateScript("""
        Object.defineProperty(Math, 'random', {
            value: globalThis.__seededRandom,
            writable: false,
            enumerable: false,
            configurable: false,
        });
        delete globalThis.__seededRandom;
        """)
    }

    /// `rng`, the reproducible source a script is meant to use.
    private func installRandom(in context: JSContext, seed: UInt64) {
        // A stream of its own, so using `rng` does not shift what `Math.random`
        // returns. Two scripts that differ only in which one they call would
        // otherwise produce unrelated fields for no reason the author can see.
        let stream = RandomStream(seed: seed &+ 0x9E37_79B9_7F4A_7C15)

        let unit: @convention(block) () -> Double = { stream.next() }

        // Every number crossing this bridge is guarded, because a script can
        // hand over anything: `rng.integer(0, 0/0)` reaches Swift as NaN, and
        // `Int(nan)` is not an error — it is a **trap**, which takes the whole
        // editor down. A script must not be able to crash the app it runs in,
        // and this was found by a test crashing the process rather than failing.
        let between: @convention(block) (Double, Double) -> Double = { low, high in
            guard low.isFinite, high.isFinite else { return 0 }
            return low + stream.next() * (high - low)
        }
        let integer: @convention(block) (Double, Double) -> Double = { low, high in
            guard low.isFinite, high.isFinite else { return 0 }
            let lower = Int(low.rounded().clampedToInt)
            let upper = Int(high.rounded().clampedToInt)
            guard upper > lower else { return Double(lower) }
            return Double(lower + Int(stream.next() * Double(upper - lower + 1)))
        }

        let table = JSValue(newObjectIn: context)
        table?.setObject(unit, forKeyedSubscript: "unit" as NSString)
        table?.setObject(between, forKeyedSubscript: "between" as NSString)
        table?.setObject(integer, forKeyedSubscript: "integer" as NSString)
        context.setObject(table, forKeyedSubscript: "rng" as NSString)
    }

    /// `param(id)` — the values behind the controls the script declared.
    private func installParameters(
        in context: JSContext,
        values: [String: EffectValue],
        declarations: DeclarationCollector,
    ) {
        let resolved: [String: Any] = values.compactMapValues { Self.javaScriptValue(of: $0) }

        // The declared default answers when nothing is stored yet.
        //
        // A freshly placed clip has a declaration and no values — the
        // inspector fills those in on the next pass — so `param('count')`
        // returned 0 and the template drew nothing at all. Caught by the test
        // that asserts the template draws, which is exactly the claim it
        // exists to make.
        let lookup: @convention(block) (String) -> Any? = { [weak declarations] id in
            if let stored = resolved[id] { return stored }
            guard let declared = declarations?.parameters()?.first(where: { $0.id == id }) else {
                // Read but never declared — almost always a typo, or a
                // `params()` call somebody has not written yet. It returned
                // `undefined` silently, and `undefined * 2` is NaN, so a script
                // reading a control it forgot to declare drew nothing with
                // nothing to say why. Reported as exactly that confusion.
                declarations?.recordUnknown(id)
                return nil
            }
            return Self.javaScriptValue(of: declared.defaultValue)
        }
        context.setObject(lookup, forKeyedSubscript: "param" as NSString)

        // `params` records what it is handed.
        //
        // It was a no-op, so a script could declare controls and nothing read
        // them — the inspector had nothing to draw and `param(id)` always fell
        // back to a default. Declared and unreachable is the worst of the
        // three states.
        let declare: @convention(block) (JSValue) -> Void = { [weak declarations] value in
            declarations?.record(value)
        }
        context.setObject(declare, forKeyedSubscript: "params" as NSString)
    }

    /// One `EffectValue` as JavaScript sees it.
    ///
    /// Shared by the stored path and the declared-default path, so a control
    /// reads the same either way — two conversions is how a colour arrives as
    /// channels from the inspector and as a string from its own default.
    static func javaScriptValue(of value: EffectValue) -> Any? {
        switch value {
        case let .number(number): number
        case let .integer(number): Double(number)
        case let .toggle(on): on
        case let .choice(option): option
        case let .text(text): text
        case let .color(colour): ["r": colour.r, "g": colour.g, "b": colour.b]
        case .path: nil
        }
    }

    /// `console.log`, which goes nowhere yet.
    ///
    /// Present rather than absent because a script that calls it should not
    /// die: reaching for a log is what somebody does when a script misbehaves,
    /// and having that throw turns one problem into two. Wiring it to the
    /// diagnostics panel comes with the editor.
    private func installConsole(in context: JSContext, into collector: LogCollector) {
        func writer(_ level: ScriptRuntime.LogLine.Level) -> @convention(block) (JSValue) -> Void {
            { value in collector.append(level: level, value: value) }
        }

        let table = JSValue(newObjectIn: context)
        table?.setObject(writer(.log), forKeyedSubscript: "log" as NSString)
        table?.setObject(writer(.warn), forKeyedSubscript: "warn" as NSString)
        table?.setObject(writer(.error), forKeyedSubscript: "error" as NSString)
        context.setObject(table, forKeyedSubscript: "console" as NSString)
    }
}
