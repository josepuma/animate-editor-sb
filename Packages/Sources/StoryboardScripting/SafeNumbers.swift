import Foundation

/// Numbers arriving from a script, made safe to use.
///
/// A script can hand over anything a `Double` can hold, including NaN and
/// infinity — `0/0` and `1/0` are ordinary JavaScript. Converting either to
/// `Int` in Swift is not an error that can be caught: it **traps**, and takes
/// the process with it.
///
/// So a script would be able to crash the editor with one division. Found by a
/// test crashing the test runner rather than failing, which is its own lesson:
/// a suite that dies has no failure to read.
extension Double {
    /// This value if it is finite, clamped into a range `Int` can hold.
    var clampedToInt: Double {
        guard isFinite else { return 0 }
        // Well inside `Int.max` rather than at it: a value near the boundary
        // can still overflow once something adds to it, and no storyboard
        // coordinate is anywhere near this large.
        return Swift.min(Swift.max(self, -1_000_000_000), 1_000_000_000)
    }

    /// This value if it is finite, or `fallback`.
    ///
    /// For coordinates and times, where clamping to a huge number would be
    /// worse than refusing: a sprite at 1e9 is not visible, and a command
    /// ending at 1e9 makes the timeline meaningless.
    func finite(or fallback: Double = 0) -> Double {
        isFinite ? self : fallback
    }
}
