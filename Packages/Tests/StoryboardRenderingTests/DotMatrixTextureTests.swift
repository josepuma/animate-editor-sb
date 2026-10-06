import CoreGraphics
import Foundation
import ImageIO
import StoryboardCore
import Testing
import UniformTypeIdentifiers

@testable import StoryboardRendering

/// The dot textures behind the LED filter, and the alignment they exist for.
///
/// Read with Core Graphics rather than the GPU, so unlike the texture decoding
/// suite these run on a CI runner too. Coordinates are visual: row 0 is the top
/// of the picture and `y` grows downward, which is the stage's own direction.
@Suite("Dot-matrix textures")
struct DotMatrixTextureTests {
    // ─── Fixtures ────────────────────────────────────────────────────────────

    private struct Picture {
        let width: Int
        let height: Int
        private let bytes: [UInt8]

        init(_ data: Data) throws {
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            width = image.width
            height = image.height

            var buffer = [UInt8](repeating: 0, count: width * height * 4)
            let context = try #require(CGContext(
                data: &buffer, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            bytes = buffer
        }

        func alpha(_ x: Int, _ y: Int) -> Double { Double(bytes[(y * width + x) * 4 + 3]) / 255 }
        func red(_ x: Int, _ y: Int) -> UInt8 { bytes[(y * width + x) * 4] }

        /// The centre of mass of the ink in one cell, in texture pixels, or
        /// `nil` when the cell is empty.
        func centroid(column: Int, row: Int, pitch: Int) -> (x: Double, y: Double)? {
            var total = 0.0
            var sumX = 0.0
            var sumY = 0.0
            for y in (row * pitch)..<((row + 1) * pitch) {
                for x in (column * pitch)..<((column + 1) * pitch) {
                    let a = alpha(x, y)
                    total += a
                    // Pixel centres, not corners.
                    sumX += a * (Double(x) + 0.5)
                    sumY += a * (Double(y) + 0.5)
                }
            }
            guard total > 0.5 else { return nil }
            return (sumX / total, sumY / total)
        }

        /// Every lit cell's centroid, in texture pixels.
        func dots(pitch: Int) -> [(x: Double, y: Double)] {
            var found: [(x: Double, y: Double)] = []
            for row in 0..<(height / pitch) {
                for column in 0..<(width / pitch) {
                    if let dot = centroid(column: column, row: row, pitch: pitch) {
                        found.append(dot)
                    }
                }
            }
            return found
        }

        func litCells(pitch: Int) -> Int { dots(pitch: pitch).count }
    }

    /// A white rectangle of ink on a transparent canvas, in visual
    /// coordinates.
    private func source(
        width: Int, height: Int, ink: CGRect? = nil,
    ) -> Data {
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        )!
        context.setShouldAntialias(false)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        // Flipped into CG's bottom-up space so the caller thinks top-down.
        let rect = ink ?? CGRect(x: 0, y: 0, width: width, height: height)
        context.fill(CGRect(
            x: rect.minX, y: CGFloat(height) - rect.maxY, width: rect.width, height: rect.height,
        ))

        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil,
        )!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    private func dots(
        of image: Data,
        pitch: Double = 8, dotSize: Double = 0.7,
        shape: DerivedSprite.DotShape = .round, threshold: Double = 0.4,
    ) throws -> Picture {
        // A source name of its own per call, not a shared "src.png" behind a
        // cache clear. `DerivedTextures` caches by path, globally, and these
        // tests run in parallel: two of them clearing the cache and then
        // asking for the same path with different sources could each get the
        // other's picture — a test failing on another test's image size, now
        // and then, depending on timing.
        let path = DerivedSprite.dotMatrix(
            "src-\(UUID().uuidString).png", pitch: pitch, dotSize: dotSize, shape: shape, threshold: threshold,
        )
        let made = try #require(DerivedTextures.data(for: path) { _ in image })
        return try Picture(made)
    }

    // ─── Texture ─────────────────────────────────────────────────────────────

    /// An even number of cells each way is what lets the filter snap without
    /// knowing the image's size: with it, every anchor of the sprite — left,
    /// centre, right — is a whole number of pitches from the edge.
    @Test("the canvas is an even number of whole cells")
    func canvasSize() throws {
        let picture = try dots(of: source(width: 50, height: 30))

        #expect(picture.width == 64)
        #expect(picture.height == 32)
        #expect(picture.width % 16 == 0)
        #expect(picture.height % 16 == 0)
    }

    @Test("lit cells hold a dot centred on the cell")
    func dotsAreCentred() throws {
        let picture = try dots(of: source(
            width: 48, height: 48, ink: CGRect(x: 8, y: 8, width: 32, height: 16),
        ))

        var count = 0
        for row in 0..<6 {
            for column in 0..<6 {
                guard let dot = picture.centroid(column: column, row: row, pitch: 8) else { continue }
                count += 1
                #expect(abs(dot.x - (Double(column) + 0.5) * 8) < 0.05)
                #expect(abs(dot.y - (Double(row) + 0.5) * 8) < 0.05)
            }
        }
        // 4 columns × 2 rows of ink.
        #expect(count == 8)
    }

    /// A dot is not a tile: between neighbours there is nothing.
    @Test("the gaps between dots are transparent")
    func gapsAreEmpty() throws {
        let picture = try dots(of: source(width: 48, height: 48), pitch: 8, dotSize: 0.5)

        for y in 0..<picture.height {
            for x in 0..<picture.width where x % 8 == 0 || y % 8 == 0 {
                #expect(picture.alpha(x, y) == 0, "ink on a cell edge at \(x),\(y)")
            }
        }
        #expect(picture.litCells(pitch: 8) == 36)
    }

    @Test("a cell with no ink produces no dot")
    func emptyCellsStayDark() throws {
        let picture = try dots(of: source(
            width: 48, height: 48, ink: CGRect(x: 8, y: 8, width: 8, height: 8),
        ))

        #expect(picture.litCells(pitch: 8) == 1)
        #expect(picture.centroid(column: 1, row: 1, pitch: 8) != nil)
        #expect(picture.centroid(column: 0, row: 0, pitch: 8) == nil)
        #expect(picture.centroid(column: 5, row: 5, pitch: 8) == nil)
    }

    /// Ink covering half a cell: a low threshold lights it, a high one does
    /// not. That is the whole meaning of the parameter.
    @Test("the threshold decides which cells light")
    func thresholdMatters() throws {
        // Columns 1-4 fully covered, column 5 half covered, two rows.
        let image = source(width: 48, height: 48, ink: CGRect(x: 8, y: 8, width: 36, height: 16))

        let low = try dots(of: image, threshold: 0.4)
        let high = try dots(of: image, threshold: 0.6)

        #expect(low.litCells(pitch: 8) == 10)
        #expect(high.litCells(pitch: 8) == 8)
    }

    /// The corner of a square dot is ink; the same pixel on a round one is not.
    @Test("square and round dots differ at the corner")
    func shapesDiffer() throws {
        let image = source(width: 32, height: 32)
        let round = try dots(of: image, pitch: 16, dotSize: 0.75, shape: .round)
        let square = try dots(of: image, pitch: 16, dotSize: 0.75, shape: .square)

        // d = 12, so the dot spans 2...13 in a 16 cell; (2, 2) is its corner.
        #expect(square.alpha(2, 2) > 0.9)
        #expect(round.alpha(2, 2) < 0.1)
        // The middle of an edge, where both are ink.
        #expect(round.alpha(8, 3) > 0.9)
        #expect(square.alpha(8, 3) > 0.9)
    }

    /// The colour comes from `_C` on the sprite, so one texture serves every
    /// tint: the dots have to be white.
    @Test("dots are white, so a tint colours them")
    func dotsAreWhite() throws {
        let picture = try dots(of: source(width: 32, height: 32), pitch: 16, dotSize: 0.75)
        #expect(picture.red(8, 8) == 255)
        #expect(picture.alpha(8, 8) == 1)
    }

    /// Ink is judged against the *coloured* source too: only its alpha counts.
    @Test("a size step changes the dot, not the grid")
    func dotSizeChangesDiameter() throws {
        let image = source(width: 32, height: 32)
        let small = try dots(of: image, pitch: 16, dotSize: 0.4)
        let large = try dots(of: image, pitch: 16, dotSize: 0.9)

        func inked(_ p: Picture) -> Int {
            (0..<16).count { p.alpha($0, 8) > 0.5 }
        }
        #expect(inked(large) > inked(small))
        #expect(small.litCells(pitch: 16) == large.litCells(pitch: 16))
    }

    /// The source is centred in its canvas, not pinned to a corner, so the
    /// sign is not nudged towards the top left by the padding.
    @Test("the picture stays centred in the padded canvas")
    func sourceIsCentred() throws {
        // 50 wide → a 64 canvas, and ink centred on the source.
        let picture = try dots(of: source(
            width: 50, height: 32, ink: CGRect(x: 10, y: 0, width: 30, height: 32),
        ))
        let xs = picture.dots(pitch: 8).map(\.x)

        let middle = (xs.min()! + xs.max()!) / 2
        #expect(abs(middle - Double(picture.width) / 2) < 0.5)
    }

    @Test("a missing source produces nothing")
    func missingSource() {
        DerivedTextures.clearCache()
        let path = DerivedSprite.dotMatrix(
            "gone.png", pitch: 8, dotSize: 0.7, shape: .round, threshold: 0.4,
        )
        #expect(DerivedTextures.data(for: path) { _ in nil } == nil)
    }

    // ─── Panel ───────────────────────────────────────────────────────────────

    @Test("a panel is a full lattice of dots at the named size")
    func panelTexture() throws {
        DerivedTextures.clearCache()
        let path = DerivedSprite.dotPanel(
            columns: 6, rows: 4, pitch: 8, dotSize: 0.5, shape: .round,
        )
        let data = try #require(DerivedTextures.data(for: path) { _ in nil })
        let picture = try Picture(data)

        #expect(picture.width == 48)
        #expect(picture.height == 32)
        #expect(picture.litCells(pitch: 8) == 24)
        #expect(picture.alpha(0, 0) == 0)
    }

    // ─── Alignment ───────────────────────────────────────────────────────────

    /// Where the dots of a sprite's texture land on the stage, at rest.
    ///
    /// Measured from the pixels of the real generated image and the sprite's
    /// own position and origin — nothing here reuses the filter's arithmetic,
    /// so a disagreement between the two cannot cancel out.
    private func stageDots(
        of sprite: StoryboardSprite,
        source: @escaping (String) -> Data?,
    ) throws -> (pitch: Int, dots: [(x: Double, y: Double)]) {
        let parsed = try #require(DerivedSprite.parse(sprite.filePath))
        let data = try #require(DerivedTextures.data(for: sprite.filePath, source: source))
        let picture = try Picture(data)

        let pitch: Int
        switch parsed.kind {
        case let .dotMatrix(p, _, _, _): pitch = p
        case let .dotPanel(_, _, p, _, _): pitch = p
        default: throw NSError(domain: "not dots", code: 0)
        }

        let anchor = sprite.origin.anchor
        let left = sprite.defaultX - Double(anchor.x) * Double(picture.width)
        let top = sprite.defaultY - Double(anchor.y) * Double(picture.height)
        return (pitch, picture.dots(pitch: pitch).map { (left + $0.x, top + $0.y) })
    }

    /// How far a coordinate is from the middle of a lattice cell, in cells.
    private func offCentre(_ value: Double, origin: Double, pitch: Int) -> Double {
        let cells = (value - origin) / Double(pitch) - 0.5
        return abs(cells - cells.rounded())
    }

    private func registerGlyphs(_ text: String, style: TextStyle) {
        for character in text where !character.isWhitespace {
            TextTextures.register(character, style: style)
        }
    }

    /// The test that matters. Two letters, laid out by the text effect with
    /// font advances that are not multiples of anything, each rasterised on its
    /// own — and every dot of both, plus the panel's, has to sit on ONE lattice
    /// anchored at the stage origin.
    @Test("dots of neighbouring glyphs and the panel share one lattice")
    func glyphsAndPanelShareALattice() throws {
        let style = TextStyle(font: "Helvetica", size: 48, isBold: false, isItalic: false)
        registerGlyphs("LED", style: style)

        var document = EffectDocument()
        var node = document.add(TextEffect.descriptor, at: 0, duration: 2000)
        node.values[TextEffect.Param.text] = .text("LED")
        document[node.id] = node
        let filter = document.addFilter(LEDFilter.descriptor, to: node.id)!
        document.setFilterValue(
            .choice(LEDFilter.Panel.stage.rawValue), for: LEDFilter.Param.panel, on: filter.id, in: node.id,
        )
        let sprites = EffectEvaluator().evaluate(document)
        #expect(sprites.count == 4)

        var checked = 0
        for sprite in sprites {
            let (pitch, found) = try stageDots(of: sprite) { TextTextures.data(for: $0) }
            #expect(!found.isEmpty, "no dots for \(sprite.filePath)")

            for dot in found {
                #expect(
                    offCentre(dot.x, origin: DotGrid.originX, pitch: pitch) < 0.02,
                    "x \(dot.x) is off the lattice (\(sprite.id))",
                )
                #expect(
                    offCentre(dot.y, origin: DotGrid.originY, pitch: pitch) < 0.02,
                    "y \(dot.y) is off the lattice (\(sprite.id))",
                )
                checked += 1
            }
        }
        #expect(checked > 100, "only \(checked) dots were checked")
    }

    /// Every origin: the snap does not know the texture's size, so it has to
    /// work for a sprite anchored at any of the nine points.
    @Test("the lattice holds for every origin", arguments: Origin.allCases)
    func everyOrigin(origin: Origin) throws {
        let style = TextStyle(font: "Helvetica", size: 48, isBold: false, isItalic: false)
        registerGlyphs("W", style: style)

        // An awkward position, and an awkward glyph size.
        let sprite = StoryboardSprite(
            id: "w", layer: .foreground, origin: origin,
            filePath: TextSprite.rawPath(for: "W", style: style),
            defaultX: 123.4, defaultY: 77.7,
            commands: [Command(
                easing: .linear, startTime: 0, endTime: 1000, payload: .fade(start: 1, end: 1),
            )],
        )
        let descriptor = LEDFilter.descriptor
        let context = FilterContext(
            descriptor: descriptor,
            node: FilterNode(id: "led", type: descriptor.type, values: descriptor.defaultValues),
        )
        let out = LEDFilter().apply(to: [sprite], in: context)
        let led = try #require(out.first)

        let (pitch, found) = try stageDots(of: led) { TextTextures.data(for: $0) }
        #expect(!found.isEmpty)
        for dot in found {
            #expect(offCentre(dot.x, origin: DotGrid.originX, pitch: pitch) < 0.02)
            #expect(offCentre(dot.y, origin: DotGrid.originY, pitch: pitch) < 0.02)
        }
    }

    /// The lattice follows the pitch, not a constant.
    @Test("a different pitch gives a different lattice", arguments: [5.0, 8.0, 12.0])
    func otherPitches(pitch: Double) throws {
        let style = TextStyle(font: "Helvetica", size: 48, isBold: false, isItalic: false)
        registerGlyphs("LE", style: style)

        var document = EffectDocument()
        var node = document.add(TextEffect.descriptor, at: 0, duration: 2000)
        node.values[TextEffect.Param.text] = .text("LE")
        document[node.id] = node
        let filter = document.addFilter(LEDFilter.descriptor, to: node.id)!
        document.setFilterValue(
            .number(pitch), for: LEDFilter.Param.pitch, on: filter.id, in: node.id,
        )

        for sprite in EffectEvaluator().evaluate(document) {
            let (cell, found) = try stageDots(of: sprite) { TextTextures.data(for: $0) }
            #expect(Double(cell) == pitch)
            for dot in found {
                #expect(offCentre(dot.x, origin: DotGrid.originX, pitch: cell) < 0.02)
                #expect(offCentre(dot.y, origin: DotGrid.originY, pitch: cell) < 0.02)
            }
        }
    }
}
