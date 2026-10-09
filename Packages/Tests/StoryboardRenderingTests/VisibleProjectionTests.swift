import CoreGraphics
import simd
import Testing

@testable import StoryboardRendering

/// The renderer draws whatever part of the canvas the view shows — more than
/// the stage when zoomed out, so what sits off it is visible.
@Suite("Visible-area projection")
struct VisibleProjectionTests {
    private func clip(_ point: SIMD2<Float>, _ matrix: matrix_float4x4) -> SIMD2<Float> {
        let out = matrix * SIMD4<Float>(point.x, point.y, 0, 1)
        return SIMD2(out.x, out.y)
    }

    private func close(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Bool {
        abs(a.x - b.x) < 1e-5 && abs(a.y - b.y) < 1e-5
    }

    /// Without a visible area the projection is the one the canvas always
    /// had: the stage exactly fills the view.
    @Test("no visible area projects the stage")
    func defaultsToStage() {
        let m = MetalStoryboardRenderer.projectionMatrix(widescreen: true, visible: nil)
        #expect(close(clip([0, 0], m), [-1, 1]))
        #expect(close(clip([854, 480], m), [1, -1]))
    }

    /// The visible area's corners reach the view's corners, wherever it is.
    @Test("the visible area fills the view")
    func visibleFills() {
        let visible = CGRect(x: -427, y: -240, width: 1708, height: 960)
        let m = MetalStoryboardRenderer.projectionMatrix(widescreen: true, visible: visible)
        #expect(close(clip([-427, -240], m), [-1, 1]))
        #expect(close(clip([1281, 720], m), [1, -1]))
        // The stage sits in the middle half.
        #expect(close(clip([0, 0], m), [-0.5, 0.5]))
    }
}
