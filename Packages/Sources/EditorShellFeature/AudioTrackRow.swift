import DesignSystem
import SwiftUI

/// The track's own row on the timeline: its waveform, drawn where it plays.
///
/// A row rather than part of the ruler, because the audio is content the
/// storyboard is written against — and once it has a row of its own, where the
/// music ends is visible against where the sprites keep going.
///
/// Denser than the ruler's dotted marks: those double as a progress bar and
/// have to stay legible at 18pt, while this is the waveform itself, read for
/// its shape.
struct AudioTrackRow: View {
    let peaks: [Float]
    /// Where the audio sits within the timeline's span, which can be wider.
    let scale: TimelineScale
    let audioDuration: Double
    let headerWidth: CGFloat
    let height: CGFloat

    /// Grows from 0 to 1 when the peaks arrive, so the bars rise into place
    /// rather than appearing mid-playback.
    ///
    /// Driven by `hasGrown` through an animatable value rather than set inside
    /// a `withAnimation`: the row is rebuilt on every frame of playback, and a
    /// `Canvas` reading the state directly redraws from whatever it holds now —
    /// which is the value before the animation, every time.
    @State private var hasGrown = false

    var body: some View {
        HStack(spacing: Theme.Spacing.snug) {
            header
            content
                .frame(width: scale.width)
                // Clipped to its own lane, like the clip rows: zoomed in, the
                // waveform runs past both edges of the space it belongs in.
                .clipShape(
                    RoundedRectangle(cornerRadius: Theme.Radius.bar, style: .continuous),
                )

            Spacer(minLength: 0)
        }
        .frame(height: height)
        // `task` rather than `onChange`: the row is created the moment the
        // peaks exist, so there is no later change to react to — a handler
        // waiting for one leaves the bars at their floor height, which reads
        // as a row of dots rather than a waveform.
        .task(id: peaks.count) {
            hasGrown = !peaks.isEmpty
        }
    }

    /// How tall the bars are drawn, from nothing to full height.
    private var growth: Double {
        hasGrown ? 1 : 0
    }

    // ─── Header ──────────────────────────────────────────────────────────────

    private var header: some View {
        HStack(spacing: Theme.Spacing.snug) {
            VStack(alignment: .leading, spacing: 2) {
                Text("AUDIO")
                    .font(Theme.Typography.micro)
                    .tracking(0.6)
                    .foregroundStyle(Theme.Palette.secondary)
                    .lineLimit(1)

                Rectangle()
                    .fill(Theme.TrackPalette.blue)
                    .frame(width: Theme.Size.controlTiny, height: Theme.Size.ring)
            }

            Spacer(minLength: 0)

            Image(systemName: "waveform")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.tertiary)
                .frame(width: Theme.Size.controlTiny, height: Theme.Size.controlTiny)
        }
        .padding(.horizontal, Theme.Spacing.snug)
        .frame(width: headerWidth, alignment: .leading)
    }

    // ─── Waveform ────────────────────────────────────────────────────────────

    private var content: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: Theme.Radius.bar, style: .continuous)
                .fill(Theme.Fill.subtle)

            Canvas { context, size in
                draw(in: context, size: size)
            }
            // Scaled rather than redrawn at each step: a `Canvas` renders with
            // whatever the state holds at that moment and does not interpolate,
            // so growing the bars from inside the drawing would need the value
            // animated by something the canvas cannot see.
            .scaleEffect(y: growth, anchor: .center)
            .animation(.easeOut(duration: Theme.Motion.deliberateDuration), value: hasGrown)
            // Spans the whole lane rather than only the audio's own stretch:
            // the drawing skips bars that fall outside the track, so where the
            // music ends reads as empty lane instead of a shortened canvas —
            // and the bars land wherever their moment does, at any zoom.
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.bar, style: .continuous))
        }
        .padding(.vertical, Theme.Spacing.tight)
    }

    /// Draws the waveform as a run of rounded bars mirrored about the midline.
    ///
    /// Each bar asks the scale which moment it stands for, rather than dividing
    /// the peaks evenly across the width. Spread evenly the whole track is drawn
    /// into whatever space is given, so zooming in shows the same picture
    /// stretched instead of a closer look at that stretch of music.
    private func draw(in context: GraphicsContext, size: CGSize) {
        guard !peaks.isEmpty, size.width > 0, audioDuration > 0 else { return }

        let barWidth: CGFloat = 3
        let gap: CGFloat = 3
        let stride = barWidth + gap
        let barCount = max(1, Int(size.width / stride))
        let midline = size.height / 2
        // Leaves the bars short of the row's own edge, so the tallest peak does
        // not read as clipped.
        let maxHeight = size.height - Theme.Spacing.snug

        // How much of the track one bar covers, in milliseconds.
        let visible = scale.range
        let visibleDuration = visible.upperBound - visible.lowerBound
        let msPerBar = visibleDuration / Double(barCount)

        for index in 0..<barCount {
            let x = CGFloat(index) * stride
            // The moment this bar stands for, mapped back through the same
            // scale the clips and the ruler use.
            let time = visible.lowerBound + Double(index) * msPerBar
            guard time >= 0, time <= audioDuration else { continue }

            // The peaks arrive already curved: the extractor takes the square
            // root when it normalises, for the same reason level meters are
            // drawn on a curve. Applying it again here compresses the top of
            // the range into itself and every bar ends up the same height.
            let amplitude = CGFloat(peak(from: time, through: time + msPerBar))
            let barHeight = max(barWidth, amplitude * maxHeight)

            let bar = Path(
                roundedRect: CGRect(
                    x: x,
                    y: midline - barHeight / 2,
                    width: barWidth,
                    height: barHeight,
                ),
                cornerRadius: barWidth / 2,
            )
            context.fill(bar, with: .color(Theme.TrackPalette.blue.opacity(0.85)))
        }
    }

    /// The loudest peak between two moments in the track.
    ///
    /// The maximum rather than the average: averaging smooths a track towards
    /// its own mean, and what makes a waveform readable is the difference
    /// between a hit and the space around it.
    private func peak(from start: Double, through end: Double) -> Double {
        let count = Double(peaks.count)
        let first = Int(start / audioDuration * count)
        let last = Int(end / audioDuration * count)

        let lower = min(max(first, 0), peaks.count - 1)
        // At least one peak: zoomed far in a bar covers less than a bucket, and
        // an empty slice would draw nothing where there is music.
        let upper = min(max(last, lower + 1), peaks.count)

        return Double(peaks[lower..<upper].max() ?? 0)
    }
}
