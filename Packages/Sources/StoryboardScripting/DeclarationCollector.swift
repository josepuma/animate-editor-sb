import Foundation
import JavaScriptCore
import StoryboardCore

/// Collects the controls a script declares with `params()`.
///
/// The declaration is read at evaluation time rather than in a separate pass.
/// A pass of its own would have to run the script twice — once to find the
/// declarations and again to draw — and a script is run on every edit, so that
/// is double the work for a list that the same run already knows.
final class DeclarationCollector {
    private let lock = NSLock()
    private var declared: [EffectParameter]?

    /// Records one `params({...})` call.
    func record(_ value: JSValue) {
        guard value.isObject,
              let keys = value.context?.objectForKeyedSubscript("Object")?
                  .objectForKeyedSubscript("keys")?
                  .call(withArguments: [value]),
              let names = keys.toArray() as? [String]
        else { return }

        // In declaration order, which is the order they appear in the
        // inspector: a control list that reorders itself is a list nobody can
        // learn the shape of.
        let parameters = names.compactMap { name -> EffectParameter? in
            guard let declaration = value.objectForKeyedSubscript(name) else { return nil }
            return parameter(named: name, from: declaration)
        }

        lock.withLock { declared = parameters }
    }

    func parameters() -> [EffectParameter]? {
        lock.withLock { declared }
    }

    /// Ids a script read that it never declared.
    ///
    /// Almost always a typo, or a `params()` call somebody has not written
    /// yet — and `param('cout')` returned `undefined` silently, so a script
    /// reading a control it forgot to declare drew nothing with nothing to say
    /// why. Reported as exactly that confusion.
    private var unknown: Set<String> = []

    func recordUnknown(_ id: String) {
        lock.withLock { unknown.insert(id) }
    }

    /// A diagnostic naming what was read but never declared, if anything was.
    func unknownDiagnostic() -> ScriptRuntime.Diagnostic? {
        let ids = lock.withLock { unknown }
        guard !ids.isEmpty else { return nil }

        let named = ids.sorted().map { "'\($0)'" }.joined(separator: ", ")
        return .runtimeFailed(
            "param(\(named)) was read but never declared — add it to params() so it has a control and a default",
        )
    }

    // MARK: - One declaration

    /// Reads `{ type: 'integer', default: 24, range: [1, 200] }`.
    ///
    /// A declaration missing its type is skipped rather than guessed at: a
    /// control drawn as the wrong kind reads the wrong value back, and a
    /// missing control is at least visibly missing.
    private func parameter(named name: String, from declaration: JSValue) -> EffectParameter? {
        guard declaration.isObject,
              let rawType = declaration.objectForKeyedSubscript("type")?.toString(),
              let kind = EffectParameter.Kind(rawValue: rawType)
        else { return nil }

        let fallback = declaration.objectForKeyedSubscript("default")
        guard let value = effectValue(kind: kind, from: fallback) else { return nil }

        return EffectParameter(
            id: name,
            name: label(declaration, fallback: name),
            group: declaration.objectForKeyedSubscript("group")?.toStringOrNil() ?? "Script",
            defaultValue: value,
            range: range(declaration),
            step: declaration.objectForKeyedSubscript("step")?.toFiniteDouble(),
            unit: declaration.objectForKeyedSubscript("unit")?.toStringOrNil(),
            options: options(declaration),
            // A range means a slider, which is what a range is for: a value
            // dialled in by feel. Without one it is a field, typed exactly.
            presentation: range(declaration) == nil ? .field : .slider,
        )
    }

    /// The label, defaulting to the id with its first letter raised.
    ///
    /// `count` reads as "Count" in the inspector without anybody writing it
    /// twice, and every other parameter in the app is titled that way.
    private func label(_ declaration: JSValue, fallback: String) -> String {
        if let given = declaration.objectForKeyedSubscript("name")?.toStringOrNil() {
            return given
        }
        return fallback.prefix(1).uppercased() + fallback.dropFirst()
    }

    private func range(_ declaration: JSValue) -> ClosedRange<Double>? {
        guard let pair = declaration.objectForKeyedSubscript("range")?.toArray() as? [Any],
              pair.count == 2,
              let low = (pair[0] as? NSNumber)?.doubleValue,
              let high = (pair[1] as? NSNumber)?.doubleValue,
              low.isFinite, high.isFinite, low < high
        else { return nil }
        return low...high
    }

    private func options(_ declaration: JSValue) -> [String] {
        (declaration.objectForKeyedSubscript("options")?.toArray() as? [String]) ?? []
    }

    /// The default, coerced to the declared kind.
    private func effectValue(kind: EffectParameter.Kind, from value: JSValue?) -> EffectValue? {
        switch kind {
        case .number: .number(value?.toFiniteDouble() ?? 0)
        case .integer: .integer(Int(value?.toFiniteDouble() ?? 0))
        case .toggle: .toggle(value?.toBool() ?? false)
        case .choice: .choice(value?.toStringOrNil() ?? "")
        case .text: .text(value?.toStringOrNil() ?? "")
        case .color: .color(colour(from: value))
        // A motion path cannot be written in a declaration — it is drawn on the
        // canvas — so a script asking for one is skipped rather than given an
        // empty one it cannot fill.
        case .path: nil
        }
    }

    /// `'#ff8844'` — the form somebody writes a colour in.
    private func colour(from value: JSValue?) -> EffectColor {
        guard let text = value?.toStringOrNil() else { return .white }

        var hex = text.hasPrefix("#") ? String(text.dropFirst()) : text
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        guard hex.count == 6, let packed = UInt32(hex, radix: 16) else { return .white }

        return EffectColor(
            r: Double((packed >> 16) & 0xFF),
            g: Double((packed >> 8) & 0xFF),
            b: Double(packed & 0xFF),
        )
    }
}

private extension JSValue {
    /// The string, or `nil` for anything that is not one.
    ///
    /// `toString` on `undefined` gives the *word* "undefined", which as a
    /// label would put that on screen.
    func toStringOrNil() -> String? {
        guard !isUndefined, !isNull, let text = toString(), text != "undefined" else {
            return nil
        }
        return text
    }

    /// The number, or `nil` when there is not one.
    func toFiniteDouble() -> Double? {
        guard !isUndefined, !isNull else { return nil }
        let number = toDouble()
        return number.isFinite ? number : nil
    }
}
