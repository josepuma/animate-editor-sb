import SwiftUI

/// Plays a short run of frames on a loop — an animated preview.
///
/// A still cannot tell two motions apart: the difference between a typewriter
/// and a fade is **when** each letter arrives, and every frame after the
/// entrance shows the same settled word.
///
/// Holds its **poster** frame while not playing, and only runs its timer while
/// it is, so a grid of forty previews costs nothing until the pointer reaches
/// one.
public struct FrameSequence: View {
    private let frames: [CGImage]
    private let isPlaying: Bool
    private let interval: Duration

    @State private var index = 0

    /// - Parameter interval: time per frame. The default plays twelve frames
    ///   over a second and a half, the length of the previews the renderer
    ///   makes.
    public init(_ frames: [CGImage], isPlaying: Bool = true, interval: Duration = .milliseconds(125)) {
        self.frames = frames
        self.isPlaying = isPlaying
        self.interval = interval
    }

    /// The frame to show at rest.
    ///
    /// Not the first. A preview starts at the instant before anything has
    /// entered — no letter typed yet, no particle emitted — so the first frame
    /// is empty, and a grid holding first frames was a grid of black tiles.
    /// Two thirds of the way through the run: the frames bunch towards the
    /// start, so that lands well after an entrance has happened and while an
    /// emitter is still full, and before everything fades out at the end.
    public static func posterIndex(count: Int) -> Int {
        max(0, count * 2 / 3)
    }

    public var body: some View {
        if let frame = frames[safe: isPlaying ? index : Self.posterIndex(count: frames.count)] ?? frames.first {
            Image(decorative: frame, scale: 1)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                // Keyed on `isPlaying`, so stopping cancels the loop and
                // starting begins a fresh one.
                .task(id: isPlaying) {
                    // Starting from the beginning when it plays: the entrance
                    // is what a moving preview is for.
                    guard isPlaying, frames.count > 1 else {
                        index = 0
                        return
                    }
                    while !Task.isCancelled {
                        try? await Task.sleep(for: interval)
                        index = (index + 1) % frames.count
                    }
                }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
