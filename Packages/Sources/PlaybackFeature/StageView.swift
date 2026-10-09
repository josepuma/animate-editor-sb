import StoryboardCore
import SwiftUI

/// The storyboard and nothing else: no controls, no selection, no picking.
///
/// For places that show a storyboard rather than edit one — the home screen's
/// hero. It is the same canvas the editor draws with, so a trailer is exactly
/// what the project looks like, not a second rendering of it.
public struct StageView: View {
    private let model: PlaybackModel
    private let source: any StoryboardSource
    private let maximumPixelWidth: CGFloat?

    /// - Parameter maximumPixelWidth: the widest drawable to render. A stage
    ///   shown full-bleed behind a scrim does not need the display's full
    ///   resolution, and on a 5K screen paying for it saturated the GPU.
    public init(model: PlaybackModel, source: any StoryboardSource, maximumPixelWidth: CGFloat? = nil) {
        self.model = model
        self.source = source
        self.maximumPixelWidth = maximumPixelWidth
    }

    public var body: some View {
        MetalCanvasView(model: model, source: source, maximumPixelWidth: maximumPixelWidth)
            .allowsHitTesting(false)
    }
}

/// Which stretch of the song a trailer loops over.
public enum TrailerRange {
    /// How long a trailer runs before it loops.
    public static let length: Double = 30_000

    /// Starts where the map says its best moment is — the preview time osu!
    /// plays in its own menu — then the first kiai, then two fifths in.
    ///
    /// Backed up from the end rather than cut short: a loop of a few seconds
    /// reads as a stutter, not a trailer.
    public static func range(
        previewTime: Double?,
        kiai: [KiaiSection],
        duration: Double,
    ) -> ClosedRange<Double> {
        guard duration > length else { return 0 ... max(duration, 1) }
        let wanted = previewTime ?? kiai.first?.startTime ?? duration * 0.4
        let start = min(max(wanted, 0), duration - length)
        return start ... start + length
    }
}
