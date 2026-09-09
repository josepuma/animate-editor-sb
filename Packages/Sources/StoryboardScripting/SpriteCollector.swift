import Foundation
import JavaScriptCore
import StoryboardCore

/// Collects the sprites a script builds, and names them.
///
/// A script asks for a sprite and gets a builder back; it never sets an id.
/// Ids are assigned here, in creation order, prefixed with the clip's own — the
/// canvas decides which clip a sprite belongs to by that prefix, so a script
/// free to write raw ids could put its sprites inside another clip's selection
/// box, or outside every one.
final class SpriteCollector {
    private let idPrefix: String
    private var built: [StoryboardSprite] = []

    /// Set when a call was given a name that does not exist.
    private(set) var undefinedArgument = false

    /// How many sprites the script asked for beyond the ceiling.
    ///
    /// Counted here because the clamp downstream can no longer see them: they
    /// are declined at the door rather than built and trimmed, so without this
    /// the truncation would be silent — and silent truncation is the failure
    /// mode the whole diagnostic exists to avoid.
    private(set) var refused = 0

    init(idPrefix: String) {
        self.idPrefix = idPrefix
    }

    func sprites() -> [StoryboardSprite] {
        built
    }

    /// Installs `sprite(path, options?)` into the context.
    func install(in context: JSContext) {
        // Captured strongly, and the context holds the block: the collector has
        // to outlive every call a script makes, and nothing else refers to it
        // once `install` returns. Captured weakly it was released before the
        // script ran, so `sprite()` returned nil — which JavaScriptCore reports
        // as `undefined is not an object` at the call site, pointing at the
        // script rather than at the bridge.
        let make: @convention(block) (String, JSValue?) -> JSValue? = { path, options in
            guard let context = JSContext.current() else { return nil }
            // A name that does not exist arrives as the *string* "undefined",
            // because the block's parameter is typed `String` — so
            // `sprite(Image.blurry)` produced a sprite pointing at a file
            // called "undefined" and drew nothing, silently.
            guard path != "undefined", path != "null", !path.isEmpty else {
                self.undefinedArgument = true
                return self.inertBuilder(in: context)
            }
            return self.builder(path: path, options: options, in: context)
        }
        context.setObject(make, forKeyedSubscript: "sprite" as NSString)
    }

    // MARK: - The builder

    /// A JS object whose command methods return itself, so calls chain.
    ///
    /// Built as a dictionary of blocks rather than by evaluating a JS class,
    /// because each block writes straight into the Swift sprite: a JS-side
    /// object would need converting afterwards, and every field in that
    /// conversion is a field that can be forgotten.
    private func builder(path: String, options: JSValue?, in context: JSContext) -> JSValue? {
        // Past the ceiling, a builder that accepts calls and keeps nothing.
        //
        // The iteration guard stops an endless loop, but `while (true) {
        // sprite(...) }` reaches that ceiling having built two million sprites
        // in Swift first — measured at **100 seconds** before the clamp, which
        // only trims the finished array, ever saw them. Refusing early takes
        // that to 1.4s.
        //
        // Inert rather than `nil`: returning nothing makes the *next* chained
        // call throw, which discards the two thousand good sprites the script
        // had already built. Truncating is the decision — a clip somebody can
        // look at and turn down beats an error and a blank canvas — and it has
        // to hold here too.
        guard built.count < ScriptLimits.maximumSprites else {
            refused += 1
            return inertBuilder(in: context)
        }

        let index = built.count
        built.append(StoryboardSprite(
            id: "\(idPrefix)/s\(index)",
            layer: layer(from: options),
            origin: origin(from: options),
            filePath: path,
            defaultX: 320,
            defaultY: 240,
        ))

        guard let handle = JSValue(newObjectIn: context) else { return nil }

        // Captured by index rather than by reference to the sprite: `built` is
        // an array of value types, so a captured copy would collect commands
        // that never reach the stored one.
        add(to: handle, name: .fade) { arguments in
            guard let timing = Timing(arguments, values: 2) else { return }
            self.append(Command(
                easing: timing.easing,
                startTime: timing.start,
                endTime: timing.end,
                payload: .fade(start: timing.values[0], end: timing.values[1]),
            ), at: index)
        }

        add(to: handle, name: .move) { arguments in
            guard let timing = Timing(arguments, values: 4) else { return }
            self.append(Command(
                easing: timing.easing,
                startTime: timing.start,
                endTime: timing.end,
                payload: .move(
                    startX: timing.values[0],
                    startY: timing.values[1],
                    endX: timing.values[2],
                    endY: timing.values[3],
                ),
            ), at: index)
        }

        add(to: handle, name: .scale) { arguments in
            guard let timing = Timing(arguments, values: 2) else { return }
            self.append(Command(
                easing: timing.easing,
                startTime: timing.start,
                endTime: timing.end,
                payload: .scale(start: timing.values[0], end: timing.values[1]),
            ), at: index)
        }

        add(to: handle, name: .rotate) { arguments in
            guard let timing = Timing(arguments, values: 2) else { return }
            self.append(Command(
                easing: timing.easing,
                startTime: timing.start,
                endTime: timing.end,
                payload: .rotate(start: timing.values[0], end: timing.values[1]),
            ), at: index)
        }

        add(to: handle, name: .moveX) { arguments in
            guard let timing = Timing(arguments, values: 2) else { return }
            self.append(Command(
                easing: timing.easing,
                startTime: timing.start,
                endTime: timing.end,
                payload: .moveX(start: timing.values[0], end: timing.values[1]),
            ), at: index)
        }

        add(to: handle, name: .moveY) { arguments in
            guard let timing = Timing(arguments, values: 2) else { return }
            self.append(Command(
                easing: timing.easing,
                startTime: timing.start,
                endTime: timing.end,
                payload: .moveY(start: timing.values[0], end: timing.values[1]),
            ), at: index)
        }

        // `_V`, without which a letterbox bar cannot be written at all: a bar
        // is a rectangle with very different axes, and a uniform scale has no
        // way to say that.
        add(to: handle, name: .scaleVec) { arguments in
            guard let timing = Timing(arguments, values: 4) else { return }
            self.append(Command(
                easing: timing.easing,
                startTime: timing.start,
                endTime: timing.end,
                payload: .vectorScale(
                    startX: timing.values[0],
                    startY: timing.values[1],
                    endX: timing.values[2],
                    endY: timing.values[3],
                ),
            ), at: index)
        }

        // `_C`, channels in [0, 255] as the format has them — not 0–1. A colour
        // ramp is what makes a particle field read as material rather than as
        // dots, so this is not an optional extra.
        add(to: handle, name: .color) { arguments in
            guard let timing = Timing(arguments, values: 6) else { return }
            self.append(Command(
                easing: timing.easing,
                startTime: timing.start,
                endTime: timing.end,
                payload: .color(
                    startR: timing.values[0],
                    startG: timing.values[1],
                    startB: timing.values[2],
                    endR: timing.values[3],
                    endG: timing.values[4],
                    endB: timing.values[5],
                ),
            ), at: index)
        }

        add(to: handle, name: .at) { arguments in
            guard arguments.count >= 2 else { return }
            self.place(x: arguments[0], y: arguments[1], at: index)
        }

        // `_P` — the flags. A span rather than values, so `Timing` with zero
        // values reads them.
        for (name, kind) in [
            (SpriteMethod.additive, ParameterKind.additive),
            (SpriteMethod.flipH, ParameterKind.flipHorizontal),
            (SpriteMethod.flipV, ParameterKind.flipVertical),
        ] {
            add(to: handle, name: name) { arguments in
                guard let timing = Timing(arguments, values: 0) else { return }
                self.append(Command(
                    easing: timing.easing,
                    startTime: timing.start,
                    endTime: timing.end,
                    payload: .parameter(kind),
                ), at: index)
            }
        }

        wrapMethods(on: handle, in: context)
        return handle
    }

    /// A builder that accepts every call and keeps nothing.
    ///
    /// Handed out once the sprite ceiling is reached, so a script that asks for
    /// too many carries on running and chaining rather than throwing on its
    /// next `.fade(…)`. Built once per context and reused: past the ceiling
    /// there may be millions of calls, and one JS object per call is work spent
    /// on sprites nobody will see.
    private func inertBuilder(in context: JSContext) -> JSValue? {
        if let existing = context.objectForKeyedSubscript("__inert"), !existing.isUndefined {
            return existing
        }
        // Generated from `SpriteMethod`, never listed by hand. Written out, it
        // held five of the twelve the real builder registers, so a script past
        // the ceiling chaining `.color(…)` threw and produced **nothing** —
        // truncation that only survived the methods a test happened to call.
        let methods = SpriteMethod.allCases
            .map { "\($0.rawValue): noop" }
            .joined(separator: ", ")

        return context.evaluateScript("""
        globalThis.__inert = (function () {
            const noop = function () { return globalThis.__inert }
            return { \(methods) }
        })()
        """)
    }

    /// Adds a chaining method: it runs `body`, then returns the builder.
    ///
    /// The block takes an **array** rather than a variadic list, and the JS
    /// side is wrapped once in `builder(path:options:in:)` to pass one. A
    /// `@convention(block)` cannot be variadic, and a command needs up to nine
    /// numbers — read by count, since an omitted easing shifts them all left.
    private func add(to handle: JSValue, name: SpriteMethod, body: @escaping ([Double]) -> Void) {
        let method: @convention(block) (JSValue) -> JSValue = { arguments in
            let count = Int(arguments.forProperty("length")?.toInt32() ?? 0)
            // An `undefined` argument is refused rather than made finite.
            //
            // `Ease.outQuad` — a name that does not exist — arrives here as
            // `undefined`. Made finite it became 0, and 0 is `linear`, so a
            // misspelled curve produced a working sprite animating differently
            // from what was asked with nothing to say so. Measured on a saved
            // project that had been drawing wrong for a while.
            //
            // A real NaN is still made finite: `0/0` is ordinary arithmetic
            // somebody may have written on purpose, and a NaN converted to
            // `Int` downstream traps and takes the editor with it. What is
            // refused is the *absence* of a value, which is always a mistake.
            let values = (0..<count).map { index -> Double? in
                guard let value = arguments.atIndex(index), !value.isUndefined, !value.isNull else {
                    return nil
                }
                return value.toDouble().finite()
            }
            guard !values.contains(where: { $0 == nil }) else {
                self.undefinedArgument = true
                return handle
            }
            body(values.compactMap { $0 })
            return handle
        }
        handle.setObject(method, forKeyedSubscript: "__\(name.rawValue)" as NSString)
    }

    /// Wraps every `__name` block in a variadic function of the same name.
    ///
    /// Done in one pass over the finished handle rather than per method: the
    /// per-method version reached for `handle.context` while the handle was
    /// still being built, and JavaScriptCore had nothing to hand back — which
    /// surfaced as `sprite()` itself throwing `undefined is not an object`,
    /// with nothing to say the fault was two layers down.
    private func wrapMethods(on handle: JSValue, in context: JSContext) {
        // The wrapper is fetched once and cached on the context, not rebuilt
        // per sprite: `evaluateScript` on every sprite is a parse per sprite,
        // and a script making two thousand of them would pay for two thousand
        // parses of the same four lines.
        if context.objectForKeyedSubscript("__wrap")?.isUndefined ?? true {
            context.evaluateScript("""
            globalThis.__wrap = function (target) {
                const keys = Object.getOwnPropertyNames(target).filter(function (k) {
                    return k.indexOf('__') === 0
                })
                for (let i = 0; i < keys.length; i++) {
                    const key = keys[i]
                    const raw = target[key]
                    target[key.substring(2)] = function () {
                        return raw(Array.prototype.slice.call(arguments))
                    }
                    delete target[key]
                }
                return target
            }
            """)
        }
        context.objectForKeyedSubscript("__wrap")?.call(withArguments: [handle])
    }

    private func append(_ command: Command, at index: Int) {
        guard built.indices.contains(index) else { return }
        built[index].commands.append(command)
    }

    private func place(x: Double, y: Double, at index: Int) {
        guard built.indices.contains(index) else { return }
        built[index].defaultX = x
        built[index].defaultY = y
    }

    // MARK: - Options

    /// Reads one option, or `nil` when there are none.
    ///
    /// The `isObject` check is what makes this safe. An omitted argument
    /// reaches Swift as a `JSValue` holding `undefined` rather than as `nil`,
    /// and `forProperty` on undefined *throws* — which fired the context's
    /// exception handler while the sprite was being built perfectly well. The
    /// handler recorded it, so `sprite('a.png')` was reported as failing even
    /// though it returned a working builder and the sprite was collected.
    ///
    /// It cost five wrong hypotheses to find, every one of them reasoned about
    /// from outside instead of measured on the real path. What settled it was
    /// printing the order of events: the exception landed *before* the handle
    /// was made, and the call still returned an object.
    private func option(_ name: String, from options: JSValue?) -> String? {
        guard let options, options.isObject else { return nil }
        guard let value = options.forProperty(name) else { return nil }

        // An option present but undefined is a name that does not exist.
        //
        // `{ layer: Layer.Middle }` reads as `undefined` here, and treating
        // that the same as an absent option meant a typo silently drew on the
        // foreground. The distinction is whether the KEY is there: an option
        // nobody wrote is fine, an option written wrong is not.
        guard !value.isUndefined, !value.isNull else {
            if options.hasProperty(name) { undefinedArgument = true }
            return nil
        }

        return value.toString()
    }

    private func layer(from options: JSValue?) -> Layer {
        guard let raw = option("layer", from: options) else { return .foreground }
        return Layer(rawValue: raw) ?? .foreground
    }

    private func origin(from options: JSValue?) -> Origin {
        guard let raw = option("origin", from: options) else { return .centre }
        return Origin(rawValue: raw) ?? .centre
    }
}

/// The leading arguments every command shares.
///
/// osu!'s own convention, which the format itself follows: an optional easing,
/// then a start and an end time, then the values. Read by **count** rather than
/// by type, because that is how the format's own shorthand works — an omitted
/// easing shifts everything left by one.
private struct Timing {
    let easing: Easing
    let start: Double
    let end: Double
    let values: [Double]

    init?(_ arguments: [Double], values expected: Int) {
        // With easing: easing, start, end, then the values.
        if arguments.count == expected + 3 {
            easing = Easing(rawValue: Int(arguments[0])) ?? .linear
            start = arguments[1]
            end = arguments[2]
            self.values = Array(arguments[3...])
            return
        }
        // Without: start, end, then the values, eased linearly.
        if arguments.count == expected + 2 {
            easing = .linear
            start = arguments[0]
            end = arguments[1]
            self.values = Array(arguments[2...])
            return
        }
        return nil
    }
}
