import StoryboardCore
import Testing

@testable import EditorShellFeature

@MainActor
@Suite("Linked scale")
struct LinkedScaleTests {
    private func shellWithClip() -> (EditorShellModel, EffectNode.ID) {
        let shell = EditorShellModel()
        let node = shell.addImage(at: "a.png", time: 0)!
        return (shell, node.id)
    }

    @Test("linked axes move together")
    func linkedAxesFollow() {
        let (shell, id) = shellWithClip()
        shell.scaleIsLinked = true

        shell.setScale(2, for: .scaleX, on: id, at: 0)

        #expect(shell.effects[id]?.transform[value: .scaleX] == 2)
        #expect(shell.effects[id]?.transform[value: .scaleY] == 2)
    }

    /// The lock means one number in both axes. A ratio sounds cleverer and is
    /// not what a lock is asked to do — and computing one from a value already
    /// written sent 0.3 in one axis to 1.5 in the other.
    @Test("linking sets both axes to the same number")
    func linkMatchesBothAxes() {
        let (shell, id) = shellWithClip()
        shell.scaleIsLinked = false
        shell.setScale(2, for: .scaleX, on: id, at: 0)

        shell.scaleIsLinked = true
        shell.setScale(0.3, for: .scaleX, on: id, at: 0)

        #expect(shell.effects[id]?.transform[value: .scaleX] == 0.3)
        #expect(shell.effects[id]?.transform[value: .scaleY] == 0.3)
    }

    @Test("unlinked axes are independent")
    func unlinkedAxesStayPut() {
        let (shell, id) = shellWithClip()
        shell.scaleIsLinked = false

        shell.setScale(3, for: .scaleX, on: id, at: 0)

        #expect(shell.effects[id]?.transform[value: .scaleX] == 3)
        #expect(shell.effects[id]?.transform[value: .scaleY] == 1)
    }

    @Test("either axis drives the other")
    func linkWorksBothWays() {
        let (shell, id) = shellWithClip()
        shell.scaleIsLinked = true

        shell.setScale(0.5, for: .scaleY, on: id, at: 0)

        #expect(shell.effects[id]?.transform[value: .scaleX] == 0.5)
    }

    @Test("zero is carried across like any other value")
    func zeroRecovers() {
        let (shell, id) = shellWithClip()
        shell.scaleIsLinked = true
        shell.setScale(0, for: .scaleX, on: id, at: 0)

        shell.setScale(2, for: .scaleX, on: id, at: 0)

        #expect(shell.effects[id]?.transform[value: .scaleY] == 2)
    }

    /// With the property animated, the link plants a keyframe on the other axis
    /// too — the same rule every other field follows.
    @Test("linked axes keyframe together when animated")
    func linkedKeyframes() {
        let (shell, id) = shellWithClip()
        shell.scaleIsLinked = true
        shell.beginAnimating(.scaleX, on: id, at: 0)
        shell.beginAnimating(.scaleY, on: id, at: 0)

        shell.setScale(3, for: .scaleX, on: id, at: 500)

        #expect((shell.effects[id]?.transform[.scaleY].keyframes.count ?? 0) > 1)
    }
}
