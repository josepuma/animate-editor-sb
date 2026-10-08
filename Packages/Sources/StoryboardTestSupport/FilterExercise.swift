import Foundation
import StoryboardCore

/// Raising a filter's parameters off their defaults, for tests that guard
/// what a filter writes.
///
/// Defaults are the wrong setting to audit with: Chromatic's jitter is off by
/// default and writes movement only when it is on, so a sweep at the defaults
/// declared it clean while it was the second offender. A guard has to exercise
/// the thing it guards.
public enum FilterExercise {
    /// Every numeric parameter with a range, turned up to 1 (or its ceiling,
    /// if lower).
    public static func exercised(_ descriptor: FilterDescriptor) -> [String: EffectValue] {
        var values: [String: EffectValue] = [:]
        for parameter in descriptor.parameters {
            guard case .number = parameter.defaultValue, let range = parameter.range else { continue }
            values[parameter.id] = .number(min(range.upperBound, 1))
        }
        return values
    }
}
