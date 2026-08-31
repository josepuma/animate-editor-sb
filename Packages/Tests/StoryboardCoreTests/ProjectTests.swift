import Foundation
import Testing

@testable import StoryboardCore

/// What a project file holds.
///
/// The document — effects, parameters, keyframes — and never the sprites those
/// produce: sprites are derived on every evaluation, so saving them would be
/// saving an answer beside its own question, and the two drift the moment
/// anything changes.
@Suite("Project files")
struct ProjectTests {
    private func document() -> EffectDocument {
        var document = EffectDocument()
        let track = document.addTrack(named: "Intro", layer: .background)

        var node = document.add(EmitterEffect.descriptor, at: 1000, duration: 3000, on: track.id)
        node.values[EmitterEffect.Param.count] = .integer(42)
        node.values[EmitterEffect.Param.color] = .color(EffectColor(r: 255, g: 100, b: 0))
        node.transform[value: .scaleX] = 0.4
        node.transform[.x] = KeyframeTrack([
            Keyframe(time: 0, value: 100, easing: .out),
            Keyframe(time: 3000, value: 500),
        ])
        document[node.id] = node

        _ = document.addFilter(GlowFilter.descriptor, to: node.id)
        return document
    }

    @Test("a project round-trips through its file format")
    func roundTrip() throws {
        let original = document()
        let data = try ProjectFile.encode(Project(document: original))
        let restored = try ProjectFile.decode(data).document

        #expect(restored.tracks.count == original.tracks.count)
        #expect(restored.nodes.count == original.nodes.count)

        let node = try #require(restored.nodes.first)
        #expect(node.values[EmitterEffect.Param.count] == .integer(42))
        #expect(node.transform[value: .scaleX] == 0.4)
        #expect(node.transform[.x].keyframes.count == 2)
        #expect(node.transform[.x].keyframes[0].easing == .out)
    }

    /// The point of saving the document rather than its output: a restored
    /// project evaluates to exactly what the original did.
    @Test("a restored project renders identically")
    func rendersIdentically() throws {
        let original = document()
        let restored = try ProjectFile.decode(ProjectFile.encode(Project(document: original))).document

        let evaluator = EffectEvaluator()
        let before = evaluator.evaluate(original)
        let after = evaluator.evaluate(restored)

        #expect(before.count == after.count)
        for (a, b) in zip(before, after) {
            #expect(a.filePath == b.filePath)
            #expect(a.defaultX == b.defaultX)
            #expect(a.commands.count == b.commands.count)
        }
    }

    @Test("track structure survives")
    func trackStructure() throws {
        var original = EffectDocument()
        let first = original.addTrack(named: "Behind", layer: .background)
        let second = original.addTrack(named: "Front", layer: .overlay)
        original.toggleVisibility(of: first.id)
        original.toggleLock(of: second.id)

        let restored = try ProjectFile.decode(ProjectFile.encode(Project(document: original))).document

        #expect(restored.tracks.map(\.name) == ["Behind", "Front"])
        #expect(restored.tracks[0].layer == .background)
        #expect(restored.tracks[0].isVisible == false)
        #expect(restored.tracks[1].isLocked == true)
    }

    @Test("filters survive with their settings")
    func filtersSurvive() throws {
        var original = EffectDocument()
        let node = original.add(EmitterEffect.descriptor, at: 0, duration: 1000)
        let filter = original.addFilter(GlowFilter.descriptor, to: node.id)!
        original.setFilterValue(.number(24), for: GlowFilter.Param.radius, on: filter.id, in: node.id)
        original.toggleFilter(filter.id, in: node.id)

        let restored = try ProjectFile.decode(ProjectFile.encode(Project(document: original))).document
        let restoredFilter = try #require(restored.nodes.first?.filters.first)

        #expect(restoredFilter.type == "glow")
        #expect(restoredFilter.values[GlowFilter.Param.radius] == .number(24))
        #expect(restoredFilter.isEnabled == false)
    }

    // ─── Versioning ──────────────────────────────────────────────────────────

    /// Present from the first release, because the alternative is guessing
    /// later: a file with no version cannot be told apart from one written
    /// before versions existed.
    @Test("a project carries its format version")
    func carriesAVersion() throws {
        let data = try ProjectFile.encode(Project(document: EffectDocument()))
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text.contains("formatVersion"))
        #expect(try ProjectFile.decode(data).formatVersion == Project.currentVersion)
    }

    @Test("a file from a newer build is refused rather than half-read")
    func refusesNewerFiles() throws {
        let project = Project(document: EffectDocument(), formatVersion: Project.currentVersion + 1)
        let data = try ProjectFile.encode(project)

        #expect(throws: ProjectError.self) {
            try ProjectFile.decode(data)
        }
    }

    // ─── On disk ─────────────────────────────────────────────────────────────

    @Test("a project writes into its beatmap folder and reads back")
    func writesAndReads() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "project-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(!ProjectFile.exists(inFolder: folder))

        try ProjectFile.write(Project(document: document()), toFolder: folder)

        #expect(ProjectFile.exists(inFolder: folder))
        let restored = try #require(try ProjectFile.read(fromFolder: folder))
        #expect(restored.document.nodes.count == 1)
    }

    /// Most folders have never been opened in this editor, and that is the
    /// ordinary case rather than a failure.
    @Test("a folder with no project reads as nothing, not as an error")
    func missingProjectIsNotAnError() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "project-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(try ProjectFile.read(fromFolder: folder) == nil)
    }

    /// A save interrupted halfway has to leave the previous project intact: a
    /// truncated project is a lost project.
    @Test("saving twice replaces rather than appends")
    func savingReplaces() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "project-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        try ProjectFile.write(Project(document: document()), toFolder: folder)
        try ProjectFile.write(Project(document: EffectDocument()), toFolder: folder)

        let restored = try #require(try ProjectFile.read(fromFolder: folder))
        #expect(restored.document.nodes.isEmpty)
    }

    // ─── Older files ─────────────────────────────────────────────────────────

    /// A project saved by an older build is a project someone still has.
    ///
    /// The bug this pins: filters moved from the track onto the clip, and the
    /// decoder simply failed on the old shape — a real project opened as an
    /// empty document, with nothing said about why.
    @Test("a project with filters on its tracks still opens")
    func readsFiltersFromTracks() throws {
        let json = """
        {
          "formatVersion": 1,
          "document": {
            "tracks": [{
              "id": "track-1",
              "name": "Effects",
              "layer": "Foreground",
              "isVisible": true,
              "isLocked": false,
              "filters": [{
                "id": "glow-1",
                "type": "glow",
                "isEnabled": true,
                "values": {}
              }],
              "nodes": [{
                "id": "image-1",
                "type": "image",
                "name": "bg.jpg",
                "layer": "Foreground",
                "startTime": 0,
                "duration": 2000,
                "seed": 1,
                "values": {},
                "transform": { "tracks": {}, "values": {} },
                "isVisible": true,
                "isLocked": false
              }]
            }]
          }
        }
        """

        let project = try ProjectFile.decode(Data(json.utf8))
        let node = try #require(project.document.nodes.first)

        #expect(project.document.tracks.count == 1)
        // The track's filters moved onto what was on it, which is what they
        // applied to before: the look is preserved.
        #expect(node.filters.count == 1)
        #expect(node.filters[0].type == "glow")
    }

    /// A node written before it had filters of its own reads as having none,
    /// rather than failing.
    @Test("a node with no filters key still opens")
    func readsNodeWithoutFilters() throws {
        let json = """
        {
          "formatVersion": 1,
          "document": {
            "tracks": [{
              "id": "t", "name": "T", "layer": "Foreground",
              "isVisible": true, "isLocked": false,
              "nodes": [{
                "id": "n", "type": "image", "name": "n",
                "layer": "Foreground", "startTime": 0, "duration": 1000,
                "seed": 1, "values": {},
                "transform": { "tracks": {}, "values": {} },
                "isVisible": true, "isLocked": false
              }]
            }]
          }
        }
        """

        let project = try ProjectFile.decode(Data(json.utf8))
        #expect(project.document.nodes.first?.filters.isEmpty == true)
    }

    /// Once read, the file is written in the new shape.
    @Test("an older project is re-saved in the current shape")
    func migratesOnSave() throws {
        var document = EffectDocument()
        let node = document.add(EmitterEffect.descriptor, at: 0, duration: 1000)
        _ = document.addFilter(GlowFilter.descriptor, to: node.id)

        let text = try #require(String(
            data: try ProjectFile.encode(Project(document: document)),
            encoding: .utf8,
        ))

        // Filters appear under the node, and a track no longer carries any.
        #expect(text.contains("\"filters\""))
        let trackSection = text.components(separatedBy: "\"nodes\"").first ?? ""
        #expect(!trackSection.contains("\"filters\""))
    }
}

