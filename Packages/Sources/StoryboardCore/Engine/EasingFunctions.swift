import Foundation

/// Applies an osu! easing function to a normalised progress value.
///
/// - Parameters:
///   - easing: osu! easing ID.
///   - t: normalised time in [0, 1].
/// - Returns: eased value in [0, 1]. Elastic and back easings may briefly
///   overshoot those bounds by design.
///
/// Ported from `applyEasing` in `app/lib/engine/easing.ts`.
public func applyEasing(_ easing: Easing, _ t: Double) -> Double {
    if t <= 0 { return 0 }
    if t >= 1 { return 1 }

    switch easing {
    case .linear: return t
    // NOTE: osu! easing IDs 1 and 2 are generic Out/In. The TypeScript source
    // maps both to the quadratic curves; kept identical here so the port stays
    // behaviour-compatible. Verify against osu! before changing — a mismatch
    // shifts every imported storyboard subtly.
    case .out: return quadOut(t)
    case .in: return quadIn(t)
    case .quadIn: return quadIn(t)
    case .quadOut: return quadOut(t)
    case .quadInOut: return quadInOut(t)
    case .cubicIn: return cubicIn(t)
    case .cubicOut: return cubicOut(t)
    case .cubicInOut: return cubicInOut(t)
    case .quartIn: return quartIn(t)
    case .quartOut: return quartOut(t)
    case .quartInOut: return quartInOut(t)
    case .quintIn: return quintIn(t)
    case .quintOut: return quintOut(t)
    case .quintInOut: return quintInOut(t)
    case .sineIn: return sineIn(t)
    case .sineOut: return sineOut(t)
    case .sineInOut: return sineInOut(t)
    case .expoIn: return expoIn(t)
    case .expoOut: return expoOut(t)
    case .expoInOut: return expoInOut(t)
    case .circIn: return circIn(t)
    case .circOut: return circOut(t)
    case .circInOut: return circInOut(t)
    case .elasticIn: return elasticIn(t)
    case .elasticOut: return elasticOut(t)
    case .elasticHalfOut: return elasticHalfOut(t)
    case .elasticQuarterOut: return elasticQuarterOut(t)
    case .elasticInOut: return elasticInOut(t)
    case .backIn: return backIn(t)
    case .backOut: return backOut(t)
    case .backInOut: return backInOut(t)
    case .bounceIn: return bounceIn(t)
    case .bounceOut: return bounceOut(t)
    case .bounceInOut: return bounceInOut(t)
    }
}

/// Linear interpolation between two values.
public func lerp(_ start: Double, _ end: Double, _ t: Double) -> Double {
    start + (end - start) * t
}

/// Eased interpolation between two values.
public func easedLerp(_ start: Double, _ end: Double, _ t: Double, _ easing: Easing) -> Double {
    lerp(start, end, applyEasing(easing, t))
}

// ─── Easing implementations ──────────────────────────────────────────────────
//
// The TypeScript source uses the `--t` pre-decrement operator, which mutates
// `t` and yields the decremented value. Swift has no such operator, so those
// expressions are written with an explicit local binding.

private func quadIn(_ t: Double) -> Double { t * t }
private func quadOut(_ t: Double) -> Double { t * (2 - t) }
private func quadInOut(_ t: Double) -> Double {
    t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t
}

private func cubicIn(_ t: Double) -> Double { t * t * t }
private func cubicOut(_ t: Double) -> Double {
    let u = t - 1
    return u * u * u + 1
}
private func cubicInOut(_ t: Double) -> Double {
    t < 0.5
        ? 4 * t * t * t
        : (t - 1) * (2 * t - 2) * (2 * t - 2) + 1
}

private func quartIn(_ t: Double) -> Double { t * t * t * t }
private func quartOut(_ t: Double) -> Double {
    let u = t - 1
    return 1 - u * u * u * u
}
private func quartInOut(_ t: Double) -> Double {
    if t < 0.5 { return 8 * t * t * t * t }
    let u = t - 1
    return 1 - 8 * u * u * u * u
}

private func quintIn(_ t: Double) -> Double { t * t * t * t * t }
private func quintOut(_ t: Double) -> Double {
    let u = t - 1
    return 1 + u * u * u * u * u
}
private func quintInOut(_ t: Double) -> Double {
    if t < 0.5 { return 16 * t * t * t * t * t }
    let u = t - 1
    return 1 + 16 * u * u * u * u * u
}

private func sineIn(_ t: Double) -> Double { 1 - cos((t * .pi) / 2) }
private func sineOut(_ t: Double) -> Double { sin((t * .pi) / 2) }
private func sineInOut(_ t: Double) -> Double { -(cos(.pi * t) - 1) / 2 }

private func expoIn(_ t: Double) -> Double { pow(2, 10 * (t - 1)) }
private func expoOut(_ t: Double) -> Double { 1 - pow(2, -10 * t) }
private func expoInOut(_ t: Double) -> Double {
    t < 0.5
        ? pow(2, 20 * t - 10) / 2
        : (2 - pow(2, -20 * t + 10)) / 2
}

private func circIn(_ t: Double) -> Double { 1 - (1 - t * t).squareRoot() }
private func circOut(_ t: Double) -> Double {
    let u = t - 1
    return (1 - u * u).squareRoot()
}
private func circInOut(_ t: Double) -> Double {
    t < 0.5
        ? (1 - (1 - 4 * t * t).squareRoot()) / 2
        : ((1 - pow(-2 * t + 2, 2)).squareRoot() + 1) / 2
}

private let c4 = (2 * Double.pi) / 3
private let c5 = (2 * Double.pi) / 4.5

private func elasticIn(_ t: Double) -> Double {
    -(pow(2, 10 * t - 10) * sin((t * 10 - 10.75) * c4))
}
private func elasticOut(_ t: Double) -> Double {
    pow(2, -10 * t) * sin((t * 10 - 0.75) * c4) + 1
}
private func elasticHalfOut(_ t: Double) -> Double {
    pow(2, -10 * t) * sin((t * 10 - 0.75) * c4 * 0.5) + 1
}
private func elasticQuarterOut(_ t: Double) -> Double {
    pow(2, -10 * t) * sin((t * 10 - 0.75) * c4 * 0.25) + 1
}
private func elasticInOut(_ t: Double) -> Double {
    t < 0.5
        ? -(pow(2, 20 * t - 10) * sin((20 * t - 11.125) * c5)) / 2
        : (pow(2, -20 * t + 10) * sin((20 * t - 11.125) * c5)) / 2 + 1
}

private let c1 = 1.70158
private let c2 = c1 * 1.525
private let c3 = c1 + 1

private func backIn(_ t: Double) -> Double { c3 * t * t * t - c1 * t * t }
private func backOut(_ t: Double) -> Double {
    1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
}
private func backInOut(_ t: Double) -> Double {
    t < 0.5
        ? (pow(2 * t, 2) * ((c2 + 1) * 2 * t - c2)) / 2
        : (pow(2 * t - 2, 2) * ((c2 + 1) * (2 * t - 2) + c2) + 2) / 2
}

private func bounceOut(_ t: Double) -> Double {
    let n1 = 7.5625
    let d1 = 2.75
    if t < 1 / d1 { return n1 * t * t }
    if t < 2 / d1 {
        let u = t - 1.5 / d1
        return n1 * u * u + 0.75
    }
    if t < 2.5 / d1 {
        let u = t - 2.25 / d1
        return n1 * u * u + 0.9375
    }
    let u = t - 2.625 / d1
    return n1 * u * u + 0.984375
}

private func bounceIn(_ t: Double) -> Double { 1 - bounceOut(1 - t) }
private func bounceInOut(_ t: Double) -> Double {
    t < 0.5
        ? (1 - bounceOut(1 - 2 * t)) / 2
        : (1 + bounceOut(2 * t - 1)) / 2
}
