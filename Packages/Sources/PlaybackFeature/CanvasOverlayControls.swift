import DesignSystem
import SwiftUI

/// Playback controls floating over the canvas, revealed on hover.
///
/// Keeping them on the canvas rather than in a bar below leaves the whole
/// bottom of the window to the timeline, and matches how video editors present
/// preview controls.
struct CanvasOverlayControls: View {
    @Bindable var model: PlaybackModel
    let isRevealed: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.compact) {
            aspectRatio
            transport
            tools
        }
    }

    // ─── Groups ──────────────────────────────────────────────────────────────

    /// The canvas ratio, as a readout.
    ///
    /// Plain text rather than a `Menu`: on macOS a menu is an AppKit control
    /// underneath, and an AppKit view ignores the `.opacity` SwiftUI applies to
    /// its container — it draws straight through, so the pill stayed visible
    /// with the controls hidden and dragged the whole row into view with it.
    ///
    /// Nothing is lost: osu! storyboards are always 4:3 inside a 16:9 frame, so
    /// there was never a second option to pick.
    private var aspectRatio: some View {
        Text("16 : 9")
            .font(Theme.Typography.label)
            .foregroundStyle(Theme.Palette.secondary)
            .padding(.horizontal, Theme.Spacing.compact)
            .frame(height: Theme.Size.pill)
            .revealed(isRevealed)
            .help("osu! storyboards are always 4:3 in a 16:9 frame")
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
        .revealed(isRevealed)
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
        .revealed(isRevealed)
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
            let progress = model.duration > 0
                ? model.currentTime / model.duration
                : 0

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
                        model.seek(to: ratio * model.duration)
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
    let isRevealed: Bool

    @State private var volume: Double = 1
    /// What to restore on unmute, so silencing is reversible rather than a
    /// one-way trip back to full.
    @State private var volumeBeforeMute: Double = 1

    private static let trackHeight: CGFloat = 84

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
        VStack(spacing: Theme.Spacing.compact) {
            Image(systemName: "speaker.wave.2.fill")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.tertiary)

            track

            // Silencing is what the pointer reaches for here, so the lower
            // glyph is a control rather than a label for the track's floor.
            IconButton(
                systemImage: volume > 0 ? "speaker.slash.fill" : "speaker.wave.2.fill",
                size: Theme.Size.controlTiny,
                help: volume > 0 ? "Mute" : "Unmute",
                action: toggleMute,
            )
        }
        .padding(.vertical, Theme.Spacing.compact)
        .padding(.horizontal, Theme.Spacing.snug)
        .revealed(isRevealed)
        .onAppear { volume = Double(model.volume) }
        // Only the mute jump is animated; a drag already follows the pointer,
        // and animating that would make the thumb lag behind it.
        .animation(Theme.Motion.quick, value: volume == 0)
    }

    /// A capsule track with a pill thumb, drawn rather than built from `Slider`
    /// so it matches the overlay instead of the platform's control styling.
    private var track: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let thumbHeight: CGFloat = 18
            let travel = height - thumbHeight

            ZStack(alignment: .top) {
                Capsule()
                    .fill(Theme.Fill.groove)
                    .frame(width: Theme.Size.grooveThickness)
                    .frame(maxWidth: .infinity)

                Capsule()
                    .fill(.white)
                    .frame(width: Theme.Size.playheadHandleWidth, height: thumbHeight)
                    // Full volume sits at the top, so the offset is inverted.
                    .offset(y: travel * (1 - volume))
                    .elevated(Theme.Elevation.low)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let position = (value.location.y - thumbHeight / 2) / travel
                        volume = min(max(0, 1 - position), 1)
                        model.setVolume(Float(volume))
                    },
            )
        }
        .frame(width: Theme.Size.controlTiny, height: Self.trackHeight)
    }
}
