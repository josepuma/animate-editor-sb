import Foundation
import Testing

@testable import StoryboardCore

/// Opening a project written before a script's code lived in a file.
///
/// The `.aesb` was the only place a script's source existed, so a decoder that
/// dropped the old key would open someone's work with empty script clips and
/// nothing to say why — the same loss the `"scale"`-to-two-axes migration
/// exists to prevent. The document reports what it carried so the layer above
/// can write the files, because Core cannot.
@Suite("Script migration")
struct ScriptMigrationTests {
    /// A v1 node's inline source survives the decode.
    @Test("inline source is carried out of a v1 project")
    func inlineSourceSurvivesDecode() throws {
        let node = try decodeNode(scriptSource: "sprite(Image.soft).fade(0, 100, 0, 1)")

        #expect(node.scriptSource == "sprite(Image.soft).fade(0, 100, 0, 1)")
        #expect(node.scriptFile == nil, "a v1 node names no file yet")
        #expect(node.needsScriptMigration, "it has source and no file, which is what migration is")
    }

    /// A node already on the new format is left alone.
    ///
    /// It carries **both** fields on purpose. A migrated node whose source has
    /// been resolved from its file has source *and* a file, and that is the
    /// only shape that distinguishes "already done" from "still inline" — a
    /// node with a file and no source agrees with a broken rule by accident,
    /// which is how the first version of this test passed a mutation that
    /// ignored the file entirely.
    @Test("a migrated node is not migrated again")
    func migratedNodeIsLeftAlone() throws {
        let node = try decodeNode(scriptSource: "sprite(Image.soft)", scriptFile: "wave")

        #expect(node.scriptFile == ScriptFile(name: "wave"))
        #expect(node.scriptSource == "sprite(Image.soft)", "the resolved source rides along")
        #expect(!node.needsScriptMigration, "it names a file, so there is nothing to migrate")
    }

    /// A node that is not a script is not a migration candidate.
    @Test("a non-script node needs nothing")
    func nonScriptNeedsNothing() throws {
        let node = try decodeNode()

        #expect(node.scriptSource == nil)
        #expect(node.scriptFile == nil)
        #expect(!node.needsScriptMigration)
    }

    /// Two clips with identical inline source migrate to two files.
    ///
    /// They were independently editable before, so de-duplicating by content
    /// would create a link the author never made — and their next edit would
    /// silently change both. Sharing is what duplicating a clip means from
    /// here on; it is not something migration may impose retroactively.
    @Test("identical sources are two migration candidates, not one")
    func identicalSourcesStayIndependent() throws {
        let shared = "sprite(Image.glow)"
        let first = try decodeNode(id: "a", scriptSource: shared)
        let second = try decodeNode(id: "b", scriptSource: shared)

        #expect(first.needsScriptMigration)
        #expect(second.needsScriptMigration)
        #expect(first.id != second.id, "each clip migrates on its own account")
    }

    /// An unsafe file name in a hostile `.aesb` costs the clip, not the project.
    @Test("an unsafe reference degrades to no file")
    func unsafeReferenceDegrades() throws {
        let node = try decodeNode(scriptFile: "../../../../etc/passwd")

        #expect(node.scriptFile == nil, "a traversal must not survive the decode")
    }

    // MARK: -

    private func decodeNode(
        id: String = "fx",
        scriptSource: String? = nil,
        scriptFile: String? = nil,
    ) throws -> EffectNode {
        var fields: [String] = [
            "\"id\": \"\(id)\"",
            "\"type\": \"script\"",
            "\"name\": \"Script\"",
            "\"layer\": \"Foreground\"",
            "\"startTime\": 0",
            "\"duration\": 4000",
            "\"seed\": 1",
            "\"values\": {}",
        ]
        if let scriptSource {
            fields.append("\"scriptSource\": \(quoted(scriptSource))")
        }
        if let scriptFile {
            fields.append("\"scriptFile\": \(quoted(scriptFile))")
        }
        let json = "{\(fields.joined(separator: ","))}"
        return try JSONDecoder().decode(EffectNode.self, from: Data(json.utf8))
    }

    private func quoted(_ value: String) -> String {
        String(data: try! JSONEncoder().encode(value), encoding: .utf8)!
    }
}
