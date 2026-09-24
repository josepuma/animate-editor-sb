import Foundation
import Testing

@testable import StoryboardCore

/// The audio presets, and presets that bring filters with them.
///
/// Every check here that says "it listens" measures it: the preset evaluated
/// under two different songs has to draw two different things. A preset in
/// the Audio pack that draws the same over a kick and over silence is a plain
/// effect with a promising name.
@Suite("Audio presets")
struct AudioPresetTests {
    private static var all: [EffectPreset] {
        TextEffect.presets + ShapeEffect.presets + AudioBarsEffect.presets + AudioWavesEffect.presets
            + EmitterEffect.presets + EmitterEffect.compoundPresets
    }

    static let audio = all.filter { $0.pack == "Audio" }.map(\.id)

    private func preset(_ id: String) throws -> EffectPreset {
        try #require(Self.all.first { $0.id == id }, "no preset \(id)")
    }

    /// A clip built the way the shell places one, filters included.
    private func node(_ preset: EffectPreset) -> EffectNode {
        var node = EffectNode(
            id: preset.id, type: preset.effectType, name: preset.name,
            startTime: 0, duration: preset.duration, seed: 12, values: preset.values,
        )
        node.filters = preset.filterNodes(using: .standard) { "\(preset.id)-f\($0)" }
        return node
    }

    /// A song: bass kicks every 500ms from `offset`, everything else quiet.
    private func kicks(every period: Double, offset: Double) -> AudioSpectrum.Analyser {
        { range, bands, interval in
            let count = max(1, Int((range.upperBound - range.lowerBound) / interval))
            let levels = (0 ..< count).map { frame -> [Float] in
                let time = range.lowerBound + Double(frame) * interval
                let since = (time - offset).truncatingRemainder(dividingBy: period)
                let hit = since >= 0 && since < 150 ? Float(0.95 * pow(0.5, since / interval)) : 0.05
                return (0 ..< bands).map { $0 < 12 ? hit : hit * 0.6 }
            }
            return AudioSpectrum.Frames(levels: levels, interval: interval)
        }
    }

    private func signature(_ sprites: [StoryboardSprite]) -> String {
        sprites.map { sprite in
            "\(sprite.defaultX),\(sprite.defaultY):" + sprite.commands.map { command in
                "\(command.kind.rawValue)@\(Int(command.startTime)):\(command.payload)"
            }.joined(separator: ",")
        }.joined(separator: "|")
    }

    // ─── Filters in presets ──────────────────────────────────────────────────

    @Test("a preset's filters come with their defaults under them, and ids of the clip's own")
    func filterNodes() throws {
        let preset = try preset("pulse-ring")
        let nodes = preset.filterNodes(using: .standard) { "clip-f\($0)" }
        #expect(!nodes.isEmpty)
        for (index, filter) in nodes.enumerated() {
            #expect(filter.id == "clip-f\(index)")
            let defaults = try #require(FilterLibrary.standard.descriptor(for: filter.type)).defaultValues
            #expect(Set(filter.values.keys) == Set(defaults.keys), "\(filter.type) is missing its defaults")
        }
    }

    /// A filter named wrong, or a value keyed to a parameter it does not
    /// have, is silently dropped when the clip evaluates — the preset looks
    /// fine and does not do what its name says.
    @Test("every preset's filters exist and set only what they declare", arguments: all.map(\.id))
    func filtersAreReal(id: String) throws {
        for filter in try preset(id).filters {
            let descriptor = try #require(FilterLibrary.standard.descriptor(for: filter.type), "no filter \(filter.type)")
            let declared = Set(descriptor.parameters.map(\.id))
            #expect(Set(filter.values.keys).isSubset(of: declared), "\(id)/\(filter.type) sets \(filter.values.keys)")
        }
    }

    // ─── The audio pack ──────────────────────────────────────────────────────

    @Test("there is an audio pack worth the name")
    func packSize() {
        #expect(Self.audio.count >= 14, "\(Self.audio.count) audio presets")
    }

    /// The measurement that matters: two songs, two pictures.
    @Test("every audio preset draws something different for a different song", arguments: audio)
    func listens(id: String) throws {
        let placed = node(try preset(id))
        let a = EffectEvaluator(audio: kicks(every: 500, offset: 0)).evaluate(placed)
        let b = EffectEvaluator(audio: kicks(every: 700, offset: 230)).evaluate(placed)
        #expect(!a.isEmpty, "\(id) drew nothing")
        #expect(signature(a) != signature(b), "\(id) ignores the song")
    }

    /// Every command is a line of the `.osb`, and lines, strands and frames
    /// multiply: a silky bundle sized by eye came to about 270,000. Held to a
    /// number a storyboard section can carry.
    @Test("no audio preset writes more than a section can carry", arguments: audio)
    func affordable(id: String) throws {
        let commands = EffectEvaluator(audio: kicks(every: 500, offset: 0))
            .evaluate(node(try preset(id)))
            .reduce(0) { $0 + $1.commands.count }
        #expect(commands <= 20_000, "\(id) writes \(commands) commands")
    }

    @Test("the wave presets draw how their names say", arguments: [
        ("oscilloscope", "Signal", "Line"), ("silk-strands", "Signal", "Line"),
        ("dotted-flow", "Signal", "Dots"), ("wave-ring", "Signal", "Line"),
    ])
    func wavePresets(id: String, style: String, draw: String) throws {
        let preset = try preset(id)
        #expect(preset.values[AudioWavesEffect.Param.style] == .choice(style))
        #expect(preset.values[AudioWavesEffect.Param.drawAs] == .choice(draw))
    }

    @Test("silk strands flow as a bundle, one hearing after another")
    func silkIsABundle() throws {
        let preset = try preset("silk-strands")
        #expect(preset.values[AudioWavesEffect.Param.strands].flatMap { if case let .integer(n) = $0 { n } else { nil } } ?? 0 >= 3)
        #expect(preset.values[AudioWavesEffect.Param.lag] != .number(0))
    }

    @Test("the spectrum presets stand where their names say", arguments: [
        ("circular-spectrum", "Circle", "Bar"), ("arc-spectrum", "Arc", "Bar"),
        ("hex-spectrum", "Polygon", "Bar"), ("led-meter", "Line", "Segments"),
        ("waveform", "Line", "Dots"), ("dot-ring", "Circle", "Dots"),
    ])
    func spectrumShapes(id: String, layout: String, element: String) throws {
        let preset = try preset(id)
        #expect(preset.effectType == AudioBarsEffect.descriptor.type)
        #expect(preset.values[AudioBarsEffect.Param.layout] == .choice(layout))
        #expect(preset.values[AudioBarsEffect.Param.element] == .choice(element))
    }

    /// A waveform opens both ways from its line; grown from one side it is a
    /// row of bars made of dots.
    @Test("the waveform straddles its line")
    func waveformCentred() throws {
        #expect(try preset("waveform").values[AudioBarsEffect.Param.origin] == .choice("Centre"))
    }

    /// Ripples are the pulse read backwards — born at rest, opening out and
    /// dissolving — fired by the kicks rather than by the beat.
    @Test("kick ripples open on the kicks")
    func kickRipples() throws {
        let pulse = try #require(try preset("kick-ripples").filters.first { $0.type == PulseFilter.descriptor.type })
        #expect(pulse.values[PulseFilter.Param.trigger] == .choice("Bass Hits"))
        #expect(pulse.values[PulseFilter.Param.expand] == .toggle(true))
    }

    @Test("a beat flash only flashes: it does not kick in size")
    func beatFlash() throws {
        let pulse = try #require(try preset("beat-flash").filters.first { $0.type == PulseFilter.descriptor.type })
        #expect(pulse.values[PulseFilter.Param.punch] == .number(0))
        #expect(pulse.values[PulseFilter.Param.release] == .number(1))
    }

    @Test("the pulse ring and the breathing glow follow the level", arguments: ["pulse-ring", "breathing-glow"])
    func driven(id: String) throws {
        #expect(try preset(id).filters.contains { $0.type == AudioDriveFilter.descriptor.type })
    }
}
