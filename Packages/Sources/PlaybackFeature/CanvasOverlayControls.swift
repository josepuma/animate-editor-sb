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
        .opacity(isRevealed ? 1 : 0)
        .offset(y: isRevealed ? 0 : Theme.Spacing.snug)
        .animation(Theme.Motion.standard, value: isRevealed)
        // Hidden controls must not swallow clicks meant for the canvas.
        .allowsHitTesting(isRevealed)
    }

    // ─── Groups ──────────────────────────────────────────────────────────────

    private var aspectRatio: some View {
        Menu {
            Text("osu! storyboards are always 4:3 in a 16:9 frame")
        } label: {
            HStack(spacing: Theme.Spacing.tight) {
                Text("16 : 9")
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Palette.secondary)

                Image(systemName: "chevron.down")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.tertiary)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, Theme.Spacing.compact)
        .frame(height: Theme.Size.pill)
        .capsuleSurface(.overlay)
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
                        Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1.5)
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
        .capsuleSurface(.overlay)
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
                systemImage: "arrow.up.left.and.arrow.down.right",
                size: Theme.Size.controlSmall,
                help: "Fit to window",
            ) {}
        }
        .padding(.horizontal, Theme.Spacing.regular)
        .frame(height: Theme.Size.pill)
        .capsuleSurface(.overlay)
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
                    .fill(.white.opacity(0.18))

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

    private static let trackHeight: CGFloat = 84

    var body: some View {
        VStack(spacing: Theme.Spacing.compact) {
            Image(systemName: "speaker.wave.2.fill")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.tertiary)

            track

            Image(systemName: "speaker.slash.fill")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.tertiary)
        }
        .padding(.vertical, Theme.Spacing.compact)
        .padding(.horizontal, Theme.Spacing.snug)
        .capsuleSurface(.overlay)
        .opacity(isRevealed ? 1 : 0)
        .animation(Theme.Motion.standard, value: isRevealed)
        .allowsHitTesting(isRevealed)
        .onAppear { volume = Double(model.volume) }
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
                    .fill(.white.opacity(0.16))
                    .frame(width: 4)
                    .frame(maxWidth: .infinity)

                Capsule()
                    .fill(.white)
                    .frame(width: 12, height: thumbHeight)
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
