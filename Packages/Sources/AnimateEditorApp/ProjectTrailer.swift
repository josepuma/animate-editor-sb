import EditorShellFeature
import PlaybackFeature
import StoryboardCore
import StoryboardPersistence
import StoryboardScripting
import SwiftUI

/// A project's storyboard playing as the home screen's hero.
///
/// The real thing, not a recording: the beatmap's `.osb`, the placed effects
/// and the scripts, evaluated by the same shell model the editor uses and drawn
/// by the same canvas. A second, lighter pipeline would be a trailer that drifts
/// from what the project actually looks like the first time either changes.
///
/// Built here because it is the one place that may hold both features — the
/// browser only knows it was handed a view.
struct ProjectTrailer: View {
    let folder: URL
    let previewTime: Double?
    let isMuted: Bool

    @State private var playback = PlaybackModel()
    @State private var shell = EditorShellModel(scriptRuntime: { request in ScriptEngine().run(request) })
    @State private var source: BeatmapStoryboardSource?
    /// The effects' first pass has landed, or there were none to wait for.
    ///
    /// Shown before that, the hero would play the bare beatmap and then pop
    /// the effects in a second later — a trailer that visibly assembles itself.
    @State private var effectsLanded = false
    @State private var isShowing = false
    @State private var audioURL = AudioTrackBox()

    var body: some View {
        ZStack {
            if let source {
                // 1920 px wide at most: the picture sits under a scrim and a
                // fade, and at a 5K window's full resolution (5120 × 2880) the
                // GPU spent every frame filling it — 67–86% busy, measured,
                // with the main thread blocked on the next drawable.
                StageView(model: playback, source: source, maximumPixelWidth: 1920)
            }
        }
        // Faded in over the artwork the browser draws beneath, so the hero is
        // never a black hole while a project with scripts evaluates.
        .opacity(isShowing ? 1 : 0)
        .animation(.easeInOut(duration: 0.8), value: isShowing)
        .task(id: folder) { await load() }
        .onChange(of: playback.status) { _, _ in startIfReady() }
        .onChange(of: effectsLanded) { _, _ in startIfReady() }
        .onChange(of: isMuted) { _, muted in playback.setVolume(muted ? 0 : 1) }
        // Leaving has to let go of the audio engine and the sprites, or the
        // trailer keeps playing under the editor it just opened.
        .onDisappear { playback.unload() }
    }

    private func load() async {
        let folder = folder
        let loaded = await Task.detached(priority: .userInitiated) {
            try? BeatmapStoryboardSource(folderURL: folder)
        }.value
        guard let loaded else { return }

        // The same seams the editor installs, the ones evaluation needs: a
        // trailer of Audio Bars dancing to the placeholder wave would be a
        // trailer of the wrong storyboard.
        let audioURL = audioURL
        shell.audioAnalyser = { range, bands, interval in
            guard let trackURL = audioURL.url else { return nil }
            return SpectrumCache.levels(from: trackURL, range: range, bands: bands, interval: interval)
        }
        shell.onSpritesChanged = { [weak playback] sprites in
            playback?.effectsChanged(to: sprites)
            effectsLanded = true
        }
        playback.onTrackLoaded = { [weak shell, weak playback] url in
            audioURL.url = url
            shell?.beat = playback?.timing.map { BeatGrid(timing: $0) }
            shell?.inputsChanged()
        }

        shell.loadProject(fromFolder: folder)
        // Nothing placed means nothing to wait for; a folder with no project
        // file loads nothing and never sends sprites.
        if shell.effects.nodes.isEmpty { effectsLanded = true }
        source = loaded
    }

    private func startIfReady() {
        guard case .ready = playback.status, effectsLanded, !isShowing else { return }

        let range = TrailerRange.range(
            previewTime: previewTime,
            kiai: playback.kiaiSections,
            duration: playback.duration,
        )
        playback.loopRange = range
        playback.seek(to: range.lowerBound)
        playback.setVolume(isMuted ? 0 : 1)
        playback.startPlayback()
        isShowing = true
    }
}
