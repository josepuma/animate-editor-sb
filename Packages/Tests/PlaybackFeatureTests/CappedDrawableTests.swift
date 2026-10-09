import CoreGraphics
import Testing

@testable import PlaybackFeature

/// The home screen's trailer draws behind a scrim at full window width; on a
/// 5K display that was a 5120 × 2880 drawable a frame, and the GPU spent the
/// frame filling it while the main thread waited for the next one.
@Suite("Capped drawable")
struct CappedDrawableTests {
    @Test("a wide retina view is capped to the maximum width, keeping its shape")
    func caps() {
        let size = CappedDrawable.size(bounds: CGSize(width: 2560, height: 1440), scale: 2, maximumWidth: 1920)
        #expect(size == CGSize(width: 1920, height: 1080))
    }

    @Test("a view already under the cap draws at its full backing scale")
    func underCap() {
        let size = CappedDrawable.size(bounds: CGSize(width: 800, height: 450), scale: 2, maximumWidth: 1920)
        #expect(size == CGSize(width: 1600, height: 900))
    }

    @Test("an empty view asks for at least one pixel")
    func empty() {
        // A zero drawable makes `nextDrawable` fail, which reads as a crash
        // waiting for the first layout.
        let size = CappedDrawable.size(bounds: .zero, scale: 2, maximumWidth: 1920)
        #expect(size.width >= 1 && size.height >= 1)
    }
}
