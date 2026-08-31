import StoryboardCore
import Testing

@testable import EditorShellFeature

@MainActor
@Suite("Inspector cost cache")
struct InspectorCacheTests {
    /// The inspector reads these from its `body`, which SwiftUI re-runs on
    /// every frame the playhead moves — and each one evaluates the effect in
    /// full. A cache is only safe if an edit is guaranteed to invalidate it.
    @Test("a cached sprite count follows an edit")
    func countFollowsEdits() {
        let shell = EditorShellModel()
        let node = shell.addEffect(EmitterEffect.descriptor, at: 0)

        shell.setValue(.integer(20), for: EmitterEffect.Param.count, on: node.id)
        let few = shell.spriteCount(of: shell.effects[node.id]!)

        shell.setValue(.integer(200), for: EmitterEffect.Param.count, on: node.id)
        let many = shell.spriteCount(of: shell.effects[node.id]!)

        #expect(many > few)
    }

    @Test("repeated reads of an unchanged node agree")
    func repeatedReadsAgree() {
        let shell = EditorShellModel()
        let node = shell.addEffect(EmitterEffect.descriptor, at: 0)

        let first = shell.spriteCount(of: node)
        let second = shell.spriteCount(of: node)
        #expect(first == second)
    }
}
