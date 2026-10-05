import AppKit
import Testing

@testable import DesignSystem

@Suite("Bundled fonts")
struct FontTests {
    @Test("every face the tokens name is found after registration", arguments: Theme.FontFace.all)
    func faceRegisters(_ name: String) {
        // `Font.custom` with a name nobody registered falls back to the system
        // font silently: the app would ship in San Francisco and nothing would
        // say so. This is the only place that failure can be seen.
        Theme.registerFonts()
        #expect(NSFont(name: name, size: 12) != nil)
    }

    @Test("readout digits share one width")
    func readoutDigitsAreTabular() throws {
        // `readout` is the playhead's time: digits of different widths make it
        // jitter as it counts. Measured on the digits themselves rather than by
        // asking for a `tnum` feature — Nunito has none because its default
        // digits are already tabular, and a test demanding the feature would
        // fail on a face that does the right thing.
        Theme.registerFonts()
        let base = try #require(NSFont(name: Theme.FontFace.regular, size: 12))
        let tabular = CTFontCreateCopyWithAttributes(
            base as CTFont,
            0,
            nil,
            CTFontDescriptorCreateWithAttributes([
                kCTFontFeatureSettingsAttribute: [[
                    kCTFontFeatureTypeIdentifierKey: kNumberSpacingType,
                    kCTFontFeatureSelectorIdentifierKey: kMonospacedNumbersSelector,
                ]],
            ] as CFDictionary),
        )

        // Measured through a `CTLine`, which shapes the text the way SwiftUI
        // does. Asking for per-glyph advances skips shaping, so the feature's
        // substitution never happens: a face whose digits are tabular only
        // through `tnum` would read as proportional, and this test would fail
        // on a face doing the right thing.
        let widths = Set("0123456789".map { digit in
            let line = CTLineCreateWithAttributedString(NSAttributedString(
                string: String(digit),
                attributes: [NSAttributedString.Key(kCTFontAttributeName as String): tabular],
            ))
            return (CTLineGetTypographicBounds(line, nil, nil, nil) * 1000).rounded()
        })
        #expect(widths.count == 1, "digit widths: \(widths.sorted())")
    }
}
