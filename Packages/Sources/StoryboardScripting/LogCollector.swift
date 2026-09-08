import Foundation
import JavaScriptCore
import StoryboardCore

/// Collects what a script printed.
///
/// A reference type guarded by a lock, for the same reason `SpriteCollector`
/// is: the blocks handed to JavaScriptCore capture it, and the context calls
/// them from whichever context it happens to be on.
final class LogCollector {
    /// The most lines kept.
    ///
    /// A `console.log` inside a loop over two thousand particles is two
    /// thousand lines, and a panel showing them is a panel nobody can read —
    /// while the array behind it grows on every evaluation, which happens on
    /// every keystroke. The earliest are kept: the first few lines of a loop
    /// are what tell you the loop is wrong.
    static let maximumLines = 200

    private let lock = NSLock()
    private var collected: [ScriptRuntime.LogLine] = []
    private var dropped = 0

    func append(level: ScriptRuntime.LogLine.Level, value: JSValue) {
        // Read here rather than stored as a `JSValue`: the value belongs to a
        // context that will not outlive this call, and reading it later is a
        // use after free.
        let message = describe(value)

        lock.withLock {
            guard collected.count < Self.maximumLines else {
                dropped += 1
                return
            }
            collected.append(ScriptRuntime.LogLine(level: level, message: message))
        }
    }

    func lines() -> [ScriptRuntime.LogLine] {
        lock.withLock {
            guard dropped > 0 else { return collected }
            // Said rather than silently truncated: a list that stops without
            // explanation reads as the script stopping there.
            return collected + [ScriptRuntime.LogLine(
                level: .warn,
                message: "…and \(dropped) more line\(dropped == 1 ? "" : "s")",
            )]
        }
    }

    /// A readable form of whatever was passed.
    ///
    /// `console.log({ x: 1 })` is `[object Object]` through `toString`, which
    /// is the least useful thing it could say — and logging an object is most
    /// of what logging is for.
    private func describe(_ value: JSValue) -> String {
        if value.isObject, !value.isNull,
           let context = value.context,
           let json = context.objectForKeyedSubscript("JSON"),
           let stringify = json.objectForKeyedSubscript("stringify"),
           let printed = stringify.call(withArguments: [value]),
           !printed.isUndefined
        {
            return printed.toString() ?? "?"
        }
        return value.toString() ?? "?"
    }
}
