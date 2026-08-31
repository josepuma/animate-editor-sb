import DesignSystem
import SwiftUI

/// Playback controls floating over the canvas, revealed on hover.
///
/// Keeping them on the canvas rather than in a bar below leaves the whole
/// bottom of the window to the timeline, and matches how video editors present
/// preview controls.
struct CanvasOverlayControls: View {
    @Bindable var model: PlaybackModel

    var body: some View {
        HStack(spacing: Theme.Spacing.compact) {
            aspectRatio
            transport
            tools
        }
    }

    // ─── Groups ──────────────────────────────────────────────────────────────

    /// Switches the stage between the wide and narrow frames.
    ///
    /// A button rather than a `Menu`: on macOS a menu is an AppKit control
    /// underneath, and an AppKit view ignores the `.opacity` SwiftUI applies to
    /// its container — it draws straight through, so the pill stayed visible
    /// with the controls hidden and dragged the whole row into view with it.
    /// With two states there is nothing to choose from anyway.
    private var aspectRatio: some View {
        Button {
            model.isWidescreen.toggle()
        } label: {
            HStack(spacing: Theme.Spacing.tight) {
                Text(model.isWidescreen ? "16 : 9" : "4 : 3")
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Palette.secondary)

                // Marked when it disagrees with the beatmap, so an override is
                // visible rather than mistaken for what the map asked for.
                if model.isWidescreen != model.beatmapIsWidescreen {
                    Circle()
                        .fill(Theme.Palette.warning)
                        .frame(width: Theme.Spacing.tight, height: Theme.Spacing.tight)
                }
            }
            .padding(.horizontal, Theme.Spacing.compact)
            .frame(height: Theme.Size.pill)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .capsuleSurface(.bar)
        .help(aspectRatioHelp)
    }

    private var aspectRatioHelp: String {
        let target = model.isWidescreen ? "4:3" : "16:9"
        let asAuthored = model.isWidescreen == model.beatmapIsWidescreen

        return asAuthored
            ? "Switch to \(target) — this beatmap was authored for \(model.isWidescreen ? "16:9" : "4:3")"
            : "Switch back to \(target), as the beatmap asks for"
    }

    private var transport: some View {
        HStack(spacing: Theme.Spacing.compact) {
            IconButton(
                systemImage: "backward.fill",
                size: Theme.Size.controlSmall,
                help: "Back 5 seconds",
            ) {
                model.seek(to: model.currentTime - 5000)
            }

            // The primary action gets a ring, as in the reference: it is the
            // one control worth finding without looking.
            Button(action: model.togglePlayback) {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Palette.primary)
                    .frame(width: Theme.Size.control, height: Theme.Size.control)
                    .overlay {
                        Circle().strokeBorder(Theme.Border.handle, lineWidth: Theme.Size.ring)
                    }
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            .help(model.isPlaying ? "Pause" : "Play")

            IconButton(
                systemImage: "forward.fill",
                size: Theme.Size.controlSmall,
                help: "Forward 5 seconds",
            ) {
                model.seek(to: model.currentTime + 5000)
            }

            HStack(spacing: Theme.Spacing.tight) {
                Text(model.timecode)
                    .font(Theme.Typography.readout)
                    .foregroundStyle(Theme.Palette.primary)
                Text("/")
                    .font(Theme.Typography.readout)
                    .foregroundStyle(Theme.Palette.tertiary)
                Text(model.durationTimecode)
                    .font(Theme.Typography.readout)
                    .foregroundStyle(Theme.Palette.tertiary)
            }

            ScrubBar(model: model)
                .frame(width: 150)
        }
        .padding(.horizontal, Theme.Spacing.regular)
        .frame(height: Theme.Size.pill)
        .capsuleSurface(.bar)
    }

    private var tools: some View {
        HStack(spacing: Theme.Spacing.compact) {
            IconButton(
                systemImage: "square.grid.2x2",
                size: Theme.Size.controlSmall,
                help: "Toggle grid",
            ) {}

            IconButton(
                systemImage: "slider.horizontal.3",
                size: Theme.Size.controlSmall,
                help: "Canvas settings",
            ) {}

            IconButton(
                systemImage: model.isCanvasFullScreen
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right",
                size: Theme.Size.controlSmall,
                help: model.isCanvasFullScreen ? "Exit full screen" : "Full screen",
                action: toggleFullScreen,
            )
            // Escape leaves, as it does everywhere else on the platform: a
            // full-screen view whose only way out is a button that fades with
            // the rest of the controls is a trap. Bound only while full
            // screen, so Escape does not enter it from the editor.
            .modifier(EscapeToExit(isActive: model.isCanvasFullScreen))
        }
        .padding(.horizontal, Theme.Spacing.regular)
        .frame(height: Theme.Size.pill)
        .capsuleSurface(.bar)
    }

}

extension CanvasOverlayControls {
    /// Fills the screen, not just the window.
    ///
    /// Two things at once: the shell drops everything but the picture, and the
    /// window takes over the display. Either alone falls short of what the
    /// control promises — panels around a full-screen window, or a bare canvas
    /// still boxed inside the desktop.
    private func toggleFullScreen() {
        model.isCanvasFullScreen.toggle()

        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }

        if model.isCanvasFullScreen != window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
    }
}

/// Binds Escape only while there is something to escape from.
private struct EscapeToExit: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if isActive {
            content.keyboardShortcut(.escape, modifiers: [])
        } else {
            content
        }
    }
}

// ─── Scrub bar ───────────────────────────────────────────────────────────────

/// A slim progress bar that seeks on drag.
///
/// A plain `Slider` brings a knob and platform styling that fight the overlay's
/// look, so this draws the two states it needs and nothing more.
private struct ScrubBar: View {
    @Bindable var model: PlaybackModel
    @State private var isHovered = false

    var body: some View {
        GeometryReader { proxy in
            // Measured against the timeline rather than the track: a storyboard
            // that opens before the music would otherwise show negative
            // progress, and one that outlasts it would fill the bar early.
            let range = model.timelineRange
            let span = max(range.upperBound - range.lowerBound, 1)
            let progress = min(max((model.currentTime - range.lowerBound) / span, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.Fill.groove)

                Capsule()
                    .fill(Theme.Palette.primary)
                    .frame(width: proxy.size.width * progress)
            }
            .frame(height: isHovered ? 6 : 4)
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .onHover { isHovered = $0 }
            .animation(Theme.Motion.quick, value: isHovered)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let ratio = min(max(0, value.location.x / proxy.size.width), 1)
                        model.seek(to: range.lowerBound + ratio * span)
                    },
            )
        }
        .frame(height: Theme.Size.controlTiny)
    }
}

// ─── Volume ──────────────────────────────────────────────────────────────────

/// A vertical volume slider, as the reference places beside the preview.
struct CanvasVolumeControl: View {
    @Bindable var model: PlaybackModel

    @State private var volume: Double = 1
    /// What to restore on unmute, so silencing is reversible rather than a
    /// one-way trip back to full.
    @State private var volumeBeforeMute: Double = 1

    private static let trackLength: CGFloat = 84

    private func toggleMute() {
        if volume > 0 {
            volumeBeforeMute = volume
            volume = 0
        } else {
            volume = volumeBeforeMute > 0 ? volumeBeforeMute : 1
        }
        model.setVolume(Float(volume))
    }

    var body: some View {
        // A row, matching the bar it now sits in. Standing upright made sense
        // floating over a tall canvas; in a horizontal strip it was a column
        // among pills.
        HStack(spacing: Theme.Spacing.compact) {
            IconButton(
                systemImage: volume > 0 ? "speaker.wave.2.fill" : "speaker.slash.fill",
                size: Theme.Size.controlTiny,
                help: volume > 0 ? "Mute" : "Unmute",
                action: toggleMute,
            )

            track
        }
        .padding(.horizontal, Theme.Spacing.regular)
        // Matches the pills beside it, so the row reads as one band.
        .frame(height: Theme.Size.pill)
        .capsuleSurface(.bar)
        .onAppear { volume = Double(model.volume) }
        // Only the mute jump is animated; a drag already follows the pointer,
        // and animating that would make the thumb lag behind it.
        .animation(Theme.Motion.quick, value: volume == 0)
    }

    /// A capsule track with a pill thumb, drawn rather than built from `Slider`
    /// so it matches the overlay instead of the platform's control styling.
    private var track: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let thumbWidth: CGFloat = 18
            let travel = width - thumbWidth

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.Fill.groove)
                    .frame(height: Theme.Size.grooveThickness)
                    .frame(maxHeight: .infinity)

                Capsule()
                    .fill(.white)
                    .frame(width: thumbWidth, height: Theme.Size.playheadHandleWidth)
                    .offset(x: travel * volume)
                    .elevated(Theme.Elevation.low)
            }
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let position = (value.location.x - thumbWidth / 2) / travel
                        volume = min(max(0, position), 1)
                        model.setVolume(Float(volume))
                    },
            )
        }
        .frame(width: Self.trackLength, height: Theme.Size.controlTiny)
    }
}
