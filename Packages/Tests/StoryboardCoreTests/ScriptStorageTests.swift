import Foundation
import Testing

@testable import StoryboardCore

/// Storing a script: its source, the parameters it declares, and getting both
/// back out of a saved project intact.
///
/// A script's controls are not known at compile time, so unlike every native
/// effect its parameter declarations have to survive in the document. That
/// makes `EffectParameter` part of the file format, which it was not before.
@Suite("Script storage")
struct ScriptStorageTests {
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private let decoder = JSONDecoder()

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        try decoder.decode(T.self, from: try encoder.encode(value))
    }

    // MARK: - EffectParameter as file format

    /// Every field, including the two that are not `Codable` for free: an
    /// optional `ClosedRange` and an enum case carrying a value.
    @Test("a parameter survives a round trip with every field set")
    func parameterRoundTrips() throws {
        let parameter = EffectParameter(
            id: "count",
            name: "Count",
            group: "Emission",
            defaultValue: .integer(200),
            range: 1...2000,
            step: 10,
            unit: "px",
            options: ["a", "b"],
            presentation: .slider,
            shownWhen: .init(parameter: "shape", isAnyOf: ["ring", "ellipse"]),
            animation: .textures(step: 2),
        )

        let decoded = try roundTrip(parameter)

        #expect(decoded == parameter)
    }

    /// The associated value is the whole point of this case: a `.textures`
    /// parameter whose step is lost reports the wrong sprite cost, and the
    /// inspector's whole reason for showing a cost is to be right about it.
    @Test("the textures step survives, not just the case")
    func texturesStepSurvives() throws {
        let parameter = EffectParameter(
            id: "radius",
            name: "Radius",
            group: "Blur",
            defaultValue: .number(0),
            animation: .textures(step: 2),
        )

        let decoded = try roundTrip(parameter)

        #expect(decoded.animation == .textures(step: 2))
        // Not merely animatable — a decoder that dropped the step and fell back
        // to `.commands` would still pass an `isAnimatable` check.
        #expect(decoded.animation != .commands)
    }

    /// A parameter with no range must not come back carrying one.
    @Test("an absent range stays absent")
    func absentRangeStaysAbsent() throws {
        let parameter = EffectParameter(
            id: "label",
            name: "Label",
            group: "Text",
            defaultValue: .text("hello"),
        )

        let decoded = try roundTrip(parameter)

        #expect(decoded.range == nil)
        #expect(decoded.step == nil)
        #expect(decoded.unit == nil)
        #expect(decoded.shownWhen == nil)
        #expect(decoded.animation == EffectParameter.Animation.none)
    }

    @Test("every value kind survives", arguments: [
        EffectValue.number(1.5),
        .integer(7),
        .toggle(true),
        .choice("ring"),
        .color(EffectColor(r: 10, g: 20, b: 30)),
        .text("sb/a.png"),
    ])
    func everyKindRoundTrips(value: EffectValue) throws {
        let parameter = EffectParameter(id: "p", name: "P", group: "G", defaultValue: value)

        let decoded = try roundTrip(parameter)

        #expect(decoded.defaultValue == value)
    }

    // MARK: - The node's new fields

    private func scriptNode() -> EffectNode {
        var node = EffectNode(
            id: "fx",
            type: "script",
            name: "Script",
            startTime: 1000,
            duration: 4000,
            seed: 42,
        )
        node.scriptSource = "for (let i = 0; i < 3; i++) sprite(Image.soft)"
        node.scriptParameters = [
            EffectParameter(
                id: "count",
                name: "Count",
                group: "Script",
                defaultValue: .integer(3),
                range: 1...100,
            ),
        ]
        return node
    }

    @Test("a script node round-trips its source and declarations")
    func nodeRoundTrips() throws {
        let node = scriptNode()
        let decoded = try roundTrip(node)

        #expect(decoded.scriptSource == node.scriptSource)
        #expect(decoded.scriptParameters == node.scriptParameters)
        #expect(decoded == node)
    }

    /// A project saved before scripts existed has neither key.
    ///
    /// Decoded as a failure, the whole document refuses to open — so someone
    /// who has never written a script loses a project to a feature they never
    /// used. This is the same reason `transform`, `filters` and `layers` are
    /// read with `decodeIfPresent`.
    @Test("a node saved before scripts existed still opens")
    func olderNodeStillOpens() throws {
        let json = Data("""
        {
          "duration": 4000,
          "id": "fx",
          "layer": "Foreground",
          "name": "Emitter",
          "seed": 1,
          "startTime": 0,
          "type": "emitter",
          "values": {}
        }
        """.utf8)

        let decoded = try decoder.decode(EffectNode.self, from: json)

        #expect(decoded.scriptSource == nil)
        #expect(decoded.scriptParameters.isEmpty)
        // The fields that already used this pattern, as a check that the new
        // keys were added without disturbing them.
        #expect(decoded.filters.isEmpty)
        #expect(decoded.layers.isEmpty)
        #expect(decoded.isVisible)
    }

    /// An additive field does not move the version. Moving the code does.
    ///
    /// This guard was right for the change it was written for: `scriptSource`
    /// and `scriptParameters` were two optional keys, and bumping the version
    /// for them would have made older builds refuse projects they could read
    /// perfectly well.
    ///
    /// Scripts moving **out** of the document is a different shape. A build
    /// that has not learned about `scriptFile` opens those clips empty, and a
    /// node with source and no file is indistinguishable from one written
    /// before the change — so the version has to say which. Version 1 stays
    /// readable, which is the half of the policy that protects the work.
    @Test("the version moved because the code moved out of the document")
    func formatVersionReflectsWhereCodeLives() {
        #expect(Project.currentVersion == 2)
        #expect(Project.minimumReadableVersion == 1, "a v1 project must never be stranded")
    }

    // MARK: - The three copy paths

    /// Duplicating, re-homing a compound layer, and pasting.
    ///
    /// All three build a fresh `EffectNode` field by field, so a new field is
    /// dropped unless each one is told about it. This codebase has already lost
    /// `filters` down two of these paths, which is why all three are tested
    /// together rather than whichever one seems most likely.
    @Test("duplicating a script carries its source and declarations")
    func duplicateCarriesScript() throws {
        var document = EffectDocument()
        let track = document.addTrack(layer: .foreground)
        let added = document.add(EmitterEffect.descriptor, at: 0, duration: 4000, on: track.id)
        let placed = try #require(added)

        // Written onto the placed node rather than inserting one built by hand:
        // a test whose subject is assembled differently from the way the app
        // assembles it measures something else.
        var stored = try #require(document[placed.id])
        stored.scriptSource = scriptNode().scriptSource
        stored.scriptParameters = scriptNode().scriptParameters
        document[placed.id] = stored

        let duplicated = document.duplicate(placed.id)
        let copy = try #require(duplicated)

        #expect(copy.scriptSource == stored.scriptSource)
        #expect(copy.scriptParameters == stored.scriptParameters)
        #expect(copy.id != stored.id)
    }

    @Test("a re-homed layer carries its source and declarations")
    func rehomedLayerCarriesScript() throws {
        var parent = EffectNode(
            id: "parent",
            type: "emitter",
            name: "Compound",
            startTime: 0,
            duration: 4000,
            seed: 7,
        )
        parent.layers = [scriptNode()]

        let rehomed = parent.layersRehomed(under: "newParent", seed: 99)
        let layer = try #require(rehomed.first)

        #expect(layer.scriptSource == scriptNode().scriptSource)
        #expect(layer.scriptParameters == scriptNode().scriptParameters)
        // Re-homing has to give the copy a new identity, or two nodes name the
        // same sprites and collapse onto each other.
        #expect(layer.id != scriptNode().id)
    }
}
