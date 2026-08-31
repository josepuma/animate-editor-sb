import Testing

@testable import StoryboardCore

@Suite("Keyframe bounds")
struct KeyframeBoundsTests {
    private func document() -> (EffectDocument, EffectNode.ID) {
        var document = EffectDocument()
        let node = document.add(ImageEffect.descriptor, at: 5000, duration: 2000)
        return (document, node.id)
    }

    /// Keyframe times are local to the clip, so one past its end is a moment
    /// the clip never reaches: still in the file, still drawn in the row, and
    /// impossible to play.
    @Test("a keyframe dragged past the end stops at the end")
    func dragIsClampedToTheEnd() {
        var (document, id) = document()
        document.setKeyframe(1, for: .x, at: 0, on: id)
        let key = document[id]!.transform[.x].keyframes[0]

        document.moveKeyframe(key.id, in: .x, to: 99999, on: id)

        #expect(document[id]?.transform[.x].keyframes[0].time == 2000)
    }

    @Test("a keyframe dragged before the start stops at zero")
    func dragIsClampedToZero() {
        var (document, id) = document()
        document.setKeyframe(1, for: .x, at: 1000, on: id)
        let key = document[id]!.transform[.x].keyframes[0]

        document.moveKeyframe(key.id, in: .x, to: -5000, on: id)

        #expect(document[id]?.transform[.x].keyframes[0].time == 0)
    }

    /// The same bound however the key arrives — placing one obeys it too.
    @Test("a keyframe placed past the end lands at the end")
    func placementIsClamped() {
        var (document, id) = document()
        document.setKeyframe(1, for: .scaleX, at: 60000, on: id)

        #expect(document[id]?.transform[.scaleX].keyframes[0].time == 2000)
    }

    @Test("a keyframe inside the clip is left where it is")
    func insideIsUntouched() {
        var (document, id) = document()
        document.setKeyframe(1, for: .opacity, at: 800, on: id)

        #expect(document[id]?.transform[.opacity].keyframes[0].time == 800)
    }
}
