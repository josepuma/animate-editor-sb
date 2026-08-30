import EditorShellFeature
import PlaybackFeature
import SwiftUI

/// Places playback inside the editor layout.
///
/// Neither feature knows the other exists: the shell arranges panels around a
/// canvas it is handed, and playback supplies that canvas. Wiring them is the
/// app's job, which is what keeps either one replaceable.
struct EditorWindow: View {
    let source: any StoryboardSource
    /// Reported outwards so the window's own title bar can hide with the rest
    /// of the chrome; the toolbar belongs to the window, not to either feature.
    @Binding var isCanvasFullScreen: Bool

    @State private var playback = PlaybackModel()
    @State private var timeline = TimelineModel()

    var body: some View {
        let view = PlaybackView(model: playback, timeline: timeline, source: source)

        EditorShellView(
            title: playback.status.message,
            sprites: playback.sprites,
            missingImagePaths: playback.missingImagePaths,
            currentTime: playback.currentTime,
            duration: playback.duration,
            drawnCount: playback.drawnCount,
            grid: timeline.grid,
            breaks: playback.breaks,
            kiaiSections: playback.kiaiSections,
            waveformPeaks: playback.waveform?.peaks ?? [],
            isCanvasFullScreen: playback.isCanvasFullScreen,
            seek: { playback.seek(to: $0) },
            canvas: { view.canvas },
        )
        .onChange(of: playback.isCanvasFullScreen, initial: true) { _, isFullScreen in
            isCanvasFullScreen = isFullScreen
        }
        // Leaving has to actually let go: the audio engine and the sprites
        // outlive this view otherwise, so the track keeps playing behind the
        // browser and the next beatmap loads on top of the last one.
        .onDisappear { playback.unload() }
    }
}
