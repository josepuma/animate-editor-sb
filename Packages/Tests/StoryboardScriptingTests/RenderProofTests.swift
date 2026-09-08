import Foundation
import Testing

@testable import StoryboardCore
@testable import StoryboardScripting

/// What the renderer would actually be handed for a placed script clip.
///
/// The end-to-end suite proves the pieces connect; this prints what a real
/// clip resolves to at a real moment, because "996 tests pass" and "something
/// is on screen" have already proved to be different claims in this project.
@Suite("Render proof")
struct RenderProofTests {
    @Test("a placed script clip resolves to drawable state mid-clip")
    func resolvesToDrawableState() throws {
        try ScriptRuntime.withRuntime({ ScriptEngine().run($0) }) {
            var document = EffectDocument()
            let track = document.addTrack(layer: .foreground)
            let node = document.add(ScriptEffect.descriptor, at: 1000, duration: 4000, on: track.id)

            let sprites = EffectEvaluator().evaluate(document)
            let prepared = StoryboardResolver.prepare(sprites)

            // Mid-clip, where the template's ring is on its way out.
            var states: [SpriteRenderState] = []
            StoryboardResolver.resolve(prepared, at: 2500, into: &states)
            let visible = states.filter { $0.visible && $0.opacity > 0.01 }

            print("PROOF placed at \(node.startTime), \(sprites.count) sprites, \(visible.count) visible at 2500ms")
            if let first = visible.first {
                print("PROOF first visible: x=\(Int(first.x)) y=\(Int(first.y)) opacity=\(String(format: "%.2f", first.opacity)) scale=\(String(format: "%.2f", first.scaleX))")
            }

            #expect(sprites.count == 24)
            #expect(!visible.isEmpty, "nothing would be drawn — the clip is on screen but blank")
            // On the stage, not off in the margins.
            #expect(visible.allSatisfy { $0.x > -107 && $0.x < 747 && $0.y > -50 && $0.y < 530 })
        }
    }
}
