import AppKit
import EditorShellFeature
import ImageIO
import PlaybackFeature
import StoryboardCore
import StoryboardPersistence
import StoryboardRendering
import SwiftUI
import UniformTypeIdentifiers

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
            // Asked for at draw time, not read here: reading it in this body
            // rebuilds the whole window on every selection. It was passed as a
            // literal `false` for exactly that reason, which left the locked
            // frame implemented and never shown — a clip that refuses to move
            // looked identical to one that is broken.
            isClipLocked: { shell.isSelectionLocked },
            clipOrigin: { shell.clipOrigin },
            onClipDrag: { drag in
                shell.applyCanvasDrag(
                    dx: drag.dx, dy: drag.dy,
                    scaleX: drag.scaleX, scaleY: drag.scaleY,
                    isStretch: drag.isStretch,
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
            // Held in a box the analyser reads, not captured as a value.
            //
            // This block runs when the folder opens, and the audio loads
            // *after* that — so capturing `playback.trackURL` here captured
            // `nil`, once and forever. Every analysis then returned nothing and
            // the bars fell back to their placeholder wave, which looks like
            // music badly enough that it took a while to notice.
            //
            // A box rather than reading the model again: `PlaybackModel` is
            // `@MainActor`, so a closure touching it hops to the main thread —
            // and the audio decoding that follows would run there too.
            let audioURL = AudioTrackBox()
            // Dropped with the project it belongs to: the cache is keyed by
            // path, so nothing would be wrongly reused — but holding a previous
            // song's analysis costs memory for audio nobody will ask about
            // again.
            SpectrumCache.clear()
            AudioSpectrum.analyse = { range, bands, interval in
                guard let trackURL = audioURL.url else { return nil }
                return SpectrumCache.levels(
                    from: trackURL, range: range, bands: bands, interval: interval,
                )
            }

            // Where the selected clip's pixels are, which the canvas measures
            // and the shell cannot see. Read on demand rather than observed:
            // the box changes with every frame the GPU draws.
            shell.selectionBounds = { playback.selectionBounds }

            // Thumbnails for the assets panel.
            //
            // Downsampled while decoding rather than after: a beatmap
            // background is thousands of pixels wide, and a grid of them
            // decoded at full size is tens of megabytes held to draw squares a
            // hundred points across.
            // What the folder holds, which is what an assets panel is asked.
            //
            // The list used to come from the sprites being drawn — a different
            // question, and the wrong one: a file sitting in the folder waiting
            // to be placed never showed up, and the app's own built-in
            // particles did.
            let folderAssets = try? BeatmapFolder(url: folder)
            if let folderAssets {
                shell.loadFolderAssets(
                    folderAssets.files(withExtensions: ["png", "jpg", "jpeg"]),
                )
            }

            // Bringing an image into the project.
            //
            // Copied rather than referenced, because osu! reads only what sits
            // in the beatmap folder: an asset linked from elsewhere works in
            // the editor and arrives broken in the game — which looks finished
            // right up until it ships.
            //
            // Into `sb/`, where a storyboard's images live by convention. The
            // folder's root holds the beatmap itself — the `.osu` files, the
            // audio, the background — and dropping art beside them mixes what
            // the map is with what the storyboard draws.
            shell.importAssets = { destination in
                let panel = NSOpenPanel()
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = true
                panel.allowedContentTypes = [.png, .jpeg]
                panel.prompt = "Import"
                panel.message = "Choose images to copy into \(destination.title)"

                guard panel.runModal() == .OK else { return [] }

                // The destination the author chose, made if it is not there.
                let subfolder = destination.relativeFolder
                let target = subfolder.isEmpty
                    ? folder
                    : folder.appendingPathComponent(subfolder, isDirectory: true)
                try? FileManager.default.createDirectory(
                    at: target, withIntermediateDirectories: true,
                )

                var imported: [String] = []
                for source in panel.urls {
                    let name = source.lastPathComponent
                    let copy = target.appendingPathComponent(name)

                    // An existing file is left alone.
                    //
                    // Overwriting is the one outcome nobody can undo here, and
                    // the same name is far more often the same picture than a
                    // deliberate replacement. Already-there counts as imported:
                    // the author asked for that file to be usable, and it is.
                    if !FileManager.default.fileExists(atPath: copy.path) {
                        guard (try? FileManager.default.copyItem(at: source, to: copy)) != nil
                        else { continue }
                    }
                    imported.append(subfolder.isEmpty ? name : "\(subfolder)/\(name)")
                }
                return imported
            }

            // Filled once the track has loaded, which is after this runs.
            // The audio arrives after the project opens, so whatever already
            // evaluated without it has to be asked again.
            //
            // The URL alone was not enough: Audio Bars had run once, on an
            // empty analyser, and its placeholder wave was cached like any
            // other result. Touching any parameter fixed it — which is how the
            // bug read as "the effect is broken until you poke it".
            playback.onTrackLoaded = { [weak shell] url in
                audioURL.url = url
                shell?.beat = playback.timing.map { BeatGrid(timing: $0) }
                shell?.inputsChanged()
            }
            audioURL.url = playback.trackURL

            shell.assetThumbnail = { path in
                // Resolved through the folder's own index, not by joining the
                // path onto the URL. The index is case-insensitive and knows
                // about Windows separators — a beatmap written on Windows names
                // `SB\Particle.PNG`, and a hand-built URL misses it.
                guard let url = folderAssets?.fileURL(forRelativePath: path) else { return nil }
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 256,
                ] as CFDictionary)
            }

            shell.previewImage = { subject in
                switch subject {
                case let .effect(descriptor): EffectThumbnails.frames(for: descriptor)
                case let .filter(descriptor): EffectThumbnails.frames(for: descriptor)
                case let .preset(preset): EffectThumbnails.frames(for: preset)
                }
            }

            // The clock lives in the playback feature and features do not
            // import each other, so the window joins them — the same seam that
            // already carries export, thumbnails and the selection bounds.
            shell.seekHandler = { playback.seek(to: $0) }

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


/// Holds the audio track's URL for the spectrum analyser.
///
/// The analyser is installed when a folder opens and the audio arrives later,
/// so the URL cannot be captured by value. A box rather than reading
/// `PlaybackModel` on demand: that type is `@MainActor`, and a closure touching
/// it hops to the main thread — taking a second of audio decoding with it.
final class AudioTrackBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: URL?

    var url: URL? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
