/// osu! easing functions.
///
/// Raw values match the numeric easing IDs used in `.osb` command lines.
/// Ported from `app/types/easing.ts`.
public enum Easing: Int, Sendable, CaseIterable {
    case linear = 0
    case out = 1
    case `in` = 2
    case quadIn = 3
    case quadOut = 4
    case quadInOut = 5
    case cubicIn = 6
    case cubicOut = 7
    case cubicInOut = 8
    case quartIn = 9
    case quartOut = 10
    case quartInOut = 11
    case quintIn = 12
    case quintOut = 13
    case quintInOut = 14
    case sineIn = 15
    case sineOut = 16
    case sineInOut = 17
    case expoIn = 18
    case expoOut = 19
    case expoInOut = 20
    case circIn = 21
    case circOut = 22
    case circInOut = 23
    case elasticIn = 24
    case elasticOut = 25
    case elasticHalfOut = 26
    case elasticQuarterOut = 27
    case elasticInOut = 28
    case backIn = 29
    case backOut = 30
    case backInOut = 31
    case bounceIn = 32
    case bounceOut = 33
    case bounceInOut = 34

    /// Falls back to `.linear` for unknown IDs, matching the TypeScript
    /// implementation's `default:` branch.
    public init(rawValueOrLinear raw: Int) {
        self = Easing(rawValue: raw) ?? .linear
    }
}
