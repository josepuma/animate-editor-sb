import Foundation
import Testing

@testable import StoryboardCore

/// Vertical text (縦書き): characters top to bottom, each line a column, the
/// columns running right to left.
///
/// Read off the evaluated sprites, with no measurer installed — Core's
/// fallback metrics — since `TextSnapshotTests` needs the global measurer nil.
@Suite("Vertical text")
struct VerticalTextTests {
    private func sprites(_ text: String, _ values: [String: EffectValue] = [:]) -> [StoryboardSprite] {
        var document = EffectDocument()
        var node = document.add(TextEffect.descriptor, at: 0, duration: 2000)
        node.values[TextEffect.Param.text] = .text(text)
        node.values[TextEffect.Param.size] = .number(40)
        for (key, value) in values { node.values[key] = value }
        return EffectEvaluator().evaluate(node)
    }

    private let vertical: [String: EffectValue] = [TextEffect.Param.orientation: .choice(TextEffect.Orientation.vertical.rawValue)]

    @Test("horizontal is the default and draws what it always drew")
    func horizontalIsInert() {
        let plain = sprites("あい\nう")
        let explicit = sprites("あい\nう", [TextEffect.Param.orientation: .choice(TextEffect.Orientation.horizontal.rawValue)])
        #expect(plain.map { "\($0.filePath)|\($0.defaultX)|\($0.defaultY)|\($0.commands.count)" }
            == explicit.map { "\($0.filePath)|\($0.defaultX)|\($0.defaultY)|\($0.commands.count)" })
    }

    @Test("a line runs down a single column, a glyph's advance apart")
    func runsDown() {
        let out = sprites("あいう", vertical)
        #expect(Set(out.map(\.defaultX)).count == 1, "one column")
        let ys = out.map(\.defaultY)
        #expect(ys == ys.sorted(), "top to bottom")
        // The fallback's vertical advance is one em.
        #expect(abs((ys[1] - ys[0]) - 40) < 1e-9)
        // Centred on the clip like horizontal text.
        #expect(abs((ys.first! + ys.last!) / 2 - 240) < 1e-9)
    }

    @Test("each line is a column, and the columns run right to left")
    func columnsRightToLeft() {
        let out = sprites("あい\nう", vertical)
        #expect(out[0].defaultX == out[1].defaultX)
        #expect(out[2].defaultX < out[0].defaultX, "the second line is to the left")
        #expect(abs((out[0].defaultX + out[2].defaultX) / 2 - 320) < 1e-9, "the block is centred")
    }

    @Test("a vertical glyph is its own texture, drawn in vertical forms")
    func verticalTexture() {
        let horizontal = sprites("ー")[0].filePath
        let upright = sprites("ー", vertical)[0].filePath
        #expect(horizontal != upright)
        #expect(TextStyle(isVertical: false) != TextStyle(isVertical: true))
    }

    /// Latin is turned on its side by default, as 縦書き sets it; Upright
    /// keeps it standing, drawn as horizontal text.
    @Test("latin turns on its side by default, or stands upright when asked")
    func latin() {
        let rotated = sprites("A", vertical)[0].filePath
        let standing = sprites("A", vertical.merging([TextEffect.Param.latin: .choice(TextEffect.Latin.upright.rawValue)]) { _, new in new })[0].filePath
        let horizontal = sprites("A")[0].filePath
        #expect(rotated != horizontal)
        #expect(standing == horizontal)
        // Kana never stands any other way.
        let kana = sprites("あ", vertical.merging([TextEffect.Param.latin: .choice(TextEffect.Latin.upright.rawValue)]) { _, new in new })[0].filePath
        #expect(kana == sprites("あ", vertical)[0].filePath)
    }

    @Test("a column counts as a line for everything that reads lines")
    func columnIsALine() {
        // Line units: the two glyphs of a column arrive together.
        let out = sprites("あい\nう", vertical.merging([
            TextEffect.Param.unit: .choice("Line"), TextEffect.Param.stagger: .number(300), TextEffect.Param.fadeIn: .number(100),
        ]) { _, new in new })
        let births = out.map { $0.commands.map(\.startTime).min()! }
        #expect(births[0] == births[1])
        #expect(births[2] > births[0])
    }

    @Test("a saved style without the field still reads")
    func decodesOldStyle() throws {
        let old = #"{"font":"Helvetica","size":48,"isBold":false,"isItalic":false,"strokeWidth":0}"#
        let style = try JSONDecoder().decode(TextStyle.self, from: Data(old.utf8))
        #expect(!style.isVertical)
    }
}
