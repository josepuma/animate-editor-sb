import Testing

@testable import DesignSystem

@Suite("Theme.Radius")
struct RadiusTests {
    @Test("a nested radius keeps the curves parallel")
    func nestedRadiusSubtractsTheInset() {
        // Two rounded rectangles are concentric only when the inner radius is
        // the outer one less the gap. Reaching for the next step down the scale
        // instead is what makes a chip read as too square inside its picker.
        #expect(Theme.Radius.nested(in: 10, inset: 2) == 8)
        #expect(Theme.Radius.nested(in: 14, inset: 4) == 10)
    }

    @Test("an inset deeper than the radius clamps to square")
    func nestedRadiusClampsAtZero() {
        // A negative corner radius draws nothing in SwiftUI, so it has to stop
        // at square rather than going through it.
        #expect(Theme.Radius.nested(in: 6, inset: 10) == 0)
    }

    @Test("the picker's chips are concentric with the picker")
    func chipsMatchTheirContainer() {
        // Guards the pairing itself, not just the arithmetic: changing either
        // token without the other is what breaks this.
        //
        // Compared with a tolerance because `CGFloat` is binary floating point:
        // two routes to the same decimal can land on neighbouring bit patterns
        // and fail an equality that prints as `8.0 == 8.0`.
        let expected = Theme.Radius.control - Theme.Spacing.hair
        let actual = Theme.Radius.nested(in: Theme.Radius.control, inset: Theme.Spacing.hair)

        #expect(abs(actual - expected) < 1e-9)
    }
}
