import EditorShellFeature
import PlaybackFeature
import StoryboardCore
import StoryboardPersistence
import StoryboardRendering
import SwiftUI

/// Places playback inside the editor layout.
///
/// Neither feature knows the other exists: the shell arranges panels around a
/// canvas it is handed, and playback supplies that canvas. Wiring them is the
/// app's job, which is what keeps either one replaceable.
struct EditorWindow: View {
    let source: any StoryboardSource
    /// The beatmap folder, where the project is saved.
    let folder: URL?
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
        let view = PlaybackView(
            model: playback,
            timeline: timeline,
            source: source,
            // Read from the model at gesture time rather than here: reading it
            // in this body rebuilds the whole window on every selection, and
            // the value is only ever consulted when a drag begins.
            isClipLocked: false,
            onClipDrag: { drag in
                shell.applyCanvasDrag(
                    dx: drag.dx, dy: drag.dy,
                    scaleX: drag.scaleX, scaleY: drag.scaleY,
                    isFinished: drag.isFinished, at: playback.currentTime,
                )
            },
            onDeselect: {
                shell.selectedNodeID = nil
                shell.selectedKeyframe = nil
            },
            // Asked for at gesture time, not read here: reading any of these in
            // this body rebuilds the whole window on every edit, which is the
            // trap this file has already documented three times.
            editablePath: { shell.editablePath },
            isDrawingPath: { shell.isDrawingPath },
            onPathChange: { shell.setEditablePath($0) },
        )
        // Read here, in the body itself.
        //
        // `@Observable` re-evaluates a view when it *reads* a property while
        // rendering; an `onChange` alone is not a read, so this view was never
        // re-evaluated and the change it watches for never fired. Effects edited
        // after the first push never reached the canvas — the same trap that
        // caught `updateNSView` earlier.
        let revision = shell.effectsRevision
        // Read for the same reason, and it is the third time this trap has been
        // walked into: without a read, opening the keyframe editor never
        // re-evaluated this view, so the `onChange` that bounds playback to the
        // clip never fired and a two-second clip played the whole song.
        let keyframeNodeID = shell.keyframeNodeID
        EditorShellView(
            shell: shell,
            title: playback.status.message,
            sprites: playback.sprites,
            missingImagePaths: playback.missingImagePaths,
            isPlaying: playback.isPlaying,
            duration: playback.duration,
            timelineRange: playback.timelineRange,
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
        // Taken when a pass lands rather than when an edit starts: evaluation
        // runs off the main thread now, so a revision fires before the sprites
        // exist.
        .onChange(of: revision, initial: true) { _, _ in
            playback.effectsChanged(to: shell.evaluateEffects())
        }
        .task {
            shell.onSpritesChanged = { sprites in
                playback.effectsChanged(to: sprites)
            }
        }
        // Editing one clip's keyframes, playback belongs to that clip: past its
        // end the ruler no longer reaches, and every property reads as whatever
        // its last key left behind.
        // Bounding playback and moving the playhead are one step, in this
        // order.
        //
        // Split across two observers they raced: the seek clamps against
        // whatever bound is set at that instant, so a playhead sent to the
        // clip's start could be pulled somewhere else by a range that had not
        // caught up — and every keyframe then landed at the wrong local time,
        // since local time is measured from the playhead.
        //
        // Keyed on the revision too, since the clip can be moved or resized
        // while the mode is open and a stale bound would loop over the span it
        // used to have.
        .onChange(of: keyframeNodeID, initial: true) { _, _ in
            enterKeyframeMode(seekingIntoClip: true)
        }
        .onChange(of: revision) { _, _ in
            enterKeyframeMode(seekingIntoClip: false)
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
        // The project loads with the folder and saves back into it.
        // Read during the body and forwarded there too, not from `onChange`.
        //
        // `onChange` fires *after* the view has rendered, so the canvas learned
        // of a new selection a cycle late — and the box could not appear until
        // the frame after that, once the renderer had measured it. Two frames
        // plus two SwiftUI passes is long enough to feel like a delay between
        // clicking a clip and seeing it selected.

        // The clock reaches the shell through the model, written from playback
        // itself rather than read in this body.
        //
        // Read here, `currentTime` made the window rebuild sixty times a second
        // — and with it the shell, the timeline and everything under them. The
        // fps matched the rebuild rate almost exactly.
        .onAppear {
            playback.onTimeChanged = { [weak shell] time in
                shell?.playheadTime = time
            }
            // Straight through, with no scheduling hop: the box is drawn from
            // the next frame the canvas renders, and that frame is 16ms away.
            shell.onSelectionChanged = { [weak playback] id in
                playback?.selectedClipID = id
            }
            guard let folder else { return }
            shell.loadProject(fromFolder: folder)

            // Installed here because exporting needs images the renderer owns
            // and the shell cannot import it. The app already stands between
            // the two for the canvas; this is the same seam.
            shell.videoExportHandler = { [weak playback] url, progress in
                guard let playback, let write = playback.writeVideo else { return }
                // Only where something is drawn, falling back to the track.
                try await write(url, shell.videoRange ?? playback.timelineRange, progress)
            }
            // Previews come from the renderer, which the shell deliberately
            // cannot see — the same seam the export sits on.
            // The song's beat, so a pulse follows the map without being told
            // its tempo.
            shell.beat = playback.timing.map { BeatGrid(timing: $0) }

            // The map's own audio, so a bank of bars asks for nothing: no file
            // to pick, no offset to line up by ear.
            //
            // Installed here rather than at launch because it needs the track,
            // and that arrives with the project. Read on demand: analysing five
            // minutes to animate eight seconds is work nobody sees, so the clip
            // asks only for the stretch it covers.
            // The URL is captured, not read through the model.
            //
            // `PlaybackModel` is `@MainActor`, so a closure reading
            // `playback.trackURL` hops to the main thread to do it — and the
            // analysis that follows runs there too. Measured, that put 1.5
            // seconds of audio decoding on the main thread on every value
            // typed, even though the evaluation itself was detached: the whole
            // point of moving the work off was undone by one property read.
            let trackURL = playback.trackURL
            // Dropped with the project it belongs to: the cache is keyed by
            // path, so nothing would be wrongly reused — but holding a previous
            // song's analysis costs memory for audio nobody will ask about
            // again.
            SpectrumCache.clear()
            AudioSpectrum.analyse = { range, bands, interval in
                guard let trackURL else { return nil }
                return SpectrumCache.levels(
                    from: trackURL, range: range, bands: bands, interval: interval,
                )
            }

            // Where the selected clip's pixels are, which the canvas measures
            // and the shell cannot see. Read on demand rather than observed:
            // the box changes with every frame the GPU draws.
            shell.selectionBounds = { playback.selectionBounds }

            shell.previewImage = { subject in
                switch subject {
                case let .effect(descriptor): EffectThumbnails.frames(for: descriptor)
                case let .filter(descriptor): EffectThumbnails.frames(for: descriptor)
                case let .preset(preset): EffectThumbnails.frames(for: preset)
                }
            }

            shell.exportHandler = { sprites, projectFolder in
                let prepared = StoryboardExport.prepareUsingAppImages(sprites) { path in
                    // Read straight off the folder being edited. A sprite path
                    // is relative to it, which is exactly how the exported file
                    // will name it again.
                    try? Data(contentsOf: projectFolder.appendingPathComponent(path))
                }
                return try StoryboardExport.write(
                    prepared,
                    toFolder: projectFolder,
                    named: projectFolder.lastPathComponent,
                )
            }
        }
        .onDisappear {
            // Saved on the way out: a project abandoned by closing the window
            // is still a project someone spent time on, and there is no undo to
            // recover it with.
            if shell.hasUnsavedChanges { shell.saveProject() }
            playback.unload()
        }
    }

    /// Points playback at the clip being edited, or back at the whole timeline.
    private func enterKeyframeMode(seekingIntoClip: Bool) {
        guard let node = shell.keyframeNode else {
            playback.loopRange = nil
            return
        }

        let range = node.startTime...max(node.startTime + 1, node.endTime)
        playback.loopRange = range

        // Only when the playhead is outside: opening the mode should not move
        // it away from a moment someone was already looking at.
        if seekingIntoClip, !range.contains(playback.currentTime) {
            playback.seek(to: range.lowerBound)
        }
    }
}
