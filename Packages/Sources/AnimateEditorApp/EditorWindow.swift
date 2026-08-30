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
    /// Owned here rather than inside the shell because both features need it:
    /// the shell places and edits effects, and the canvas has to draw what they
    /// evaluate to. Neither feature may import the other, so the app holds the
    /// piece they share.
    @State private var shell = EditorShellModel()

    var body: some View {
        let view = PlaybackView(model: playback, timeline: timeline, source: source)

        EditorShellView(
            shell: shell,
            title: playback.status.message,
            sprites: playback.sprites,
            missingImagePaths: playback.missingImagePaths,
            currentTime: playback.currentTime,
            duration: playback.duration,
            timelineRange: playback.timelineRange,
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
        // One integer rather than the document itself: an effect's parameters
        // change on every frame of a drag, and diffing thousands of evaluated
        // sprites to notice would cost more than the evaluation.
        .onChange(of: shell.effectsRevision, initial: true) { _, _ in
            playback.effectsChanged(to: shell.evaluateEffects())
        }
        // A beatmap arriving replaces the beatmap half of the sprite list, so
        // the effects are handed over again. Keyed on the status rather than on
        // the sprite count: pushing effects changes that count, and watching it
        // would feed straight back into another push.
        .onChange(of: playback.status.message) { _, _ in
            guard !shell.effects.nodes.isEmpty else { return }
            playback.effectsChanged(to: shell.evaluateEffects())
        }
        // Leaving has to actually let go: the audio engine and the sprites
        // outlive this view otherwise, so the track keeps playing behind the
        // browser and the next beatmap loads on top of the last one.
        .onDisappear { playback.unload() }
    }
}
