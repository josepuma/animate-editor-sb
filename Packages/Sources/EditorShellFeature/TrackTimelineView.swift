import DesignSystem
import StoryboardCore
import SwiftUI

/// The timeline: a ruler across the top and one row per track beneath, all
/// sharing a single playhead.
///
/// Track contents are derived from the loaded storyboard rather than authored.
/// Once scripting exists, a track becomes a script and the spans become that
/// script's output.
struct TrackTimelineView: View {
    let shell: EditorShellModel
    let currentTime: Double
    let duration: Double
    let breaks: [BreakPeriod]
    let kiaiSections: [KiaiSection]
    let waveformPeaks: [Float]
    let seek: (Double) -> Void

    /// Rises from 0 to 1 when the waveform arrives, so the marks grow into
    /// place instead of appearing mid-playback.
    @State private var waveformGrowth: Double = 0

    /// Width of the track headers.
    private static let headerWidth: CGFloat = 132
    private static let rulerHeight: CGFloat = 32
    /// Tall enough for a clip pill to carry a thumbnail and a label.
    private static let trackHeight: CGFloat = 52

    /// Total height for `trackCount` rows, so the shell can size the workspace
    /// around a timeline that grows with its content.
    static func height(trackCount: Int) -> CGFloat {
        rulerHeight
            + (trackHeight + Theme.Spacing.tight) * CGFloat(max(trackCount, 1))
            + Theme.Spacing.compact * 2
    }

    var body: some View {
        GeometryReader { proxy in
            // What the ruler and tracks span, once the panel's own padding, the
            // header column and the gap beside it are taken out.
            let contentWidth = proxy.size.width
                - Theme.Spacing.compact * 2
                - Self.headerWidth
                - Theme.Spacing.snug

            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    HStack(spacing: Theme.Spacing.snug) {
                        tools
                        ruler
                    }
                    tracks
                }

                // Drawn over both, so the line runs unbroken from the ruler
                // down through every track.
                playhead(width: contentWidth, height: proxy.size.height)
                    .offset(x: Self.headerWidth + Theme.Spacing.snug)
                    .allowsHitTesting(false)
            }
            .padding(Theme.Spacing.compact)
        }
        .frame(height: Self.height(trackCount: shell.tracks.count))
        .surface(.panel)
    }

    // ─── Tools ───────────────────────────────────────────────────────────────

    /// Editing tools, in the column above the track headers.
    ///
    /// None of these act yet — sprite editing does not exist — but they sit
    /// where the real controls will, so the strip's proportions are settled.
    private var tools: some View {
        HStack(spacing: Theme.Spacing.tight) {
            IconButton(
                systemImage: "plus",
                size: Theme.Size.controlTiny,
                help: "Add script",
            ) {}

            IconButton(
                systemImage: "scissors",
                size: Theme.Size.controlTiny,
                help: "Split at playhead",
            ) {}

            IconButton(
                systemImage: "slider.horizontal.3",
                size: Theme.Size.controlTiny,
                help: "Track settings",
            ) {}

            IconButton(
                systemImage: "trash",
                size: Theme.Size.controlTiny,
                help: "Delete track",
            ) {}
        }
        .padding(.leading, Theme.Spacing.snug)
        .frame(width: Self.headerWidth, alignment: .leading)
    }

    // ─── Ruler ───────────────────────────────────────────────────────────────

    private var ruler: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Canvas { context, size in
                    drawRuler(in: context, size: size, growth: waveformGrowth)
                }
            }
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        seek(Self.time(atX: value.location.x, width: proxy.size.width, duration: duration))
                    },
            )
        }
        .frame(height: Self.rulerHeight)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(.white.opacity(0.03))
        }
        .onChange(of: waveformPeaks.count, initial: true) { _, count in
            guard count > 0 else {
                waveformGrowth = 0
                return
            }
            withAnimation(.easeOut(duration: 0.6)) { waveformGrowth = 1 }
        }
    }

    /// Draws the ruler: time labels with the audio's dots between them.
    ///
    /// One pass rather than two, because the dots have to know where the labels
    /// land in order to leave gaps for them — a dark plate behind each label
    /// would read as a pill sitting on the ruler.
    private func drawRuler(in context: GraphicsContext, size: CGSize, growth: Double) {
        let interval = Self.labelInterval(duration: duration, width: size.width)
        guard interval > 0, duration > 0 else { return }

        // Inset so the first label and the last mark sit inside the well's
        // rounded corners instead of touching them.
        let inset = Theme.Spacing.compact

        // Place the labels first, keeping the span each one occupies.
        var labels: [(text: GraphicsContext.ResolvedText, centre: CGFloat, span: ClosedRange<CGFloat>)] = []
        var time = 0.0

        while time <= duration {
            let resolved = context.resolve(
                Text(Self.timeLabel(time))
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.secondary),
            )
            let width = resolved.measure(in: size).width
            let ideal = time / duration * size.width
            // Nudge the ends inwards: centred on its own timestamp, the first
            // label would hang off the left edge and read as clipped.
            let centre = min(
                max(ideal, inset + width / 2),
                size.width - inset - width / 2,
            )

            labels.append((
                resolved,
                centre,
                (centre - width / 2 - Theme.Spacing.snug)...(centre + width / 2 + Theme.Spacing.snug),
            ))
            time += interval
        }

        drawDots(in: context, size: size, avoiding: labels.map(\.span), growth: growth)

        for label in labels {
            context.draw(label.text, at: CGPoint(x: label.centre, y: size.height / 2), anchor: .center)
        }
    }

    /// The waveform, drawn as a row of dots that grow into bars with the audio.
    ///
    /// Width stays constant while height follows the peak, so a quiet passage
    /// reads as the ruler's own dotted rhythm and a loud one rises into a
    /// waveform — the two are the same row of marks, not separate decorations.
    private func drawDots(
        in context: GraphicsContext,
        size: CGSize,
        avoiding occupied: [ClosedRange<CGFloat>],
        growth: Double,
    ) {
        let midline = size.height / 2
        let spacing: CGFloat = 9
        let width: CGFloat = 2
        /// Height of a mark with no audio behind it: a plain round dot.
        let minimumHeight = width
        let maximumHeight = size.height * 0.45
        let inset = Theme.Spacing.compact
        var x = inset

        while x < size.width - inset {
            defer { x += spacing }
            guard !occupied.contains(where: { $0.contains(x) }) else { continue }

            // Without a waveform every mark stays a dot, which is the ruler's
            // appearance on its own.
            let peak: Double
            if waveformPeaks.isEmpty {
                peak = 0
            } else {
                let index = min(
                    waveformPeaks.count - 1,
                    Int(Double(x / size.width) * Double(waveformPeaks.count)),
                )
                peak = Double(waveformPeaks[index])
            }

            // `growth` runs 0 to 1 as the waveform arrives, so the marks rise
            // out of the plain dotted ruler rather than appearing at once.
            let full = minimumHeight + CGFloat(peak) * (maximumHeight - minimumHeight)
            let height = minimumHeight + (full - minimumHeight) * CGFloat(growth)

            let shape = Path(
                roundedRect: CGRect(
                    x: x - width / 2,
                    y: midline - height / 2,
                    width: width,
                    height: height,
                ),
                cornerRadius: width / 2,
            )

            // Played marks read bright, upcoming ones stay grey — the waveform
            // doubles as the progress bar rather than needing one of its own.
            // The transition is a short ramp rather than a hard edge, so marks
            // brighten as the playhead reaches them instead of flicking on.
            let playedRatio = Self.playedRatio(
                atX: x,
                width: size.width,
                currentTime: currentTime,
                duration: duration,
            )

            if playedRatio > 0 {
                var glow = context
                glow.addFilter(.blur(radius: 2))
                glow.fill(shape, with: .color(.white.opacity(0.2 * playedRatio)))
            }

            context.fill(
                shape,
                with: .color(.white.opacity(0.18 + 0.6 * playedRatio)),
            )
        }
    }

    /// The time a point along the ruler corresponds to.
    ///
    /// Uses the same inset span the marks are drawn across, so a click lands on
    /// the mark under the pointer.
    static func time(atX x: CGFloat, width: CGFloat, duration: Double) -> Double {
        let inset = Theme.Spacing.compact
        let span = max(1, width - inset * 2)
        let ratio = min(max(0, (x - inset) / span), 1)
        return Double(ratio) * duration
    }

    /// How fully a mark at `x` counts as played, from 0 to 1.
    ///
    /// A ramp a few marks wide rather than a step: switching each mark at the
    /// exact moment the playhead crosses it makes the row flicker.
    static func playedRatio(
        atX x: CGFloat,
        width: CGFloat,
        currentTime: Double,
        duration: Double,
    ) -> Double {
        guard duration > 0, width > 0 else { return 0 }

        let inset = Double(Theme.Spacing.compact)
        let span = Swift.max(1, Double(width) - inset * 2)
        let playheadX = inset + currentTime / duration * span
        let fade: Double = 24

        if Double(x) <= playheadX - fade { return 1 }
        if Double(x) >= playheadX { return 0 }
        return (playheadX - Double(x)) / fade
    }

    // ─── Tracks ──────────────────────────────────────────────────────────────

    private var tracks: some View {
        GeometryReader { proxy in
            let trackWidth = proxy.size.width - Self.headerWidth

            ZStack(alignment: .topLeading) {
                VStack(spacing: Theme.Spacing.tight) {
                    ForEach(shell.tracks) { track in
                        TrackRowView(
                            track: track,
                            isSelected: track.id == shell.selectedTrackID,
                            duration: duration,
                            headerWidth: Self.headerWidth,
                            height: Self.trackHeight,
                            select: { shell.selectedTrackID = track.id },
                            toggleVisibility: { shell.toggleVisibility(of: track.id) },
                            toggleLock: { shell.toggleLock(of: track.id) },
                        )
                    }
                }

                // Regions and the playhead span every row, so they are drawn
                // over the stack rather than inside each one.
                regionOverlay(width: trackWidth)
                    .offset(x: Self.headerWidth)
                    .allowsHitTesting(false)

            }
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let x = value.location.x - Self.headerWidth
                        guard x >= 0 else { return }
                        seek(x / trackWidth * duration)
                    },
            )
        }
        .frame(
            height: (Self.trackHeight + Theme.Spacing.tight)
                * CGFloat(max(shell.tracks.count, 1)),
        )
    }

    private func regionOverlay(width: CGFloat) -> some View {
        Canvas { context, size in
            guard duration > 0 else { return }
            let x = { (time: Double) in time / duration * size.width }

            for period in breaks {
                let start = x(period.startTime)
                context.fill(
                    Path(CGRect(
                        x: start, y: 0,
                        width: x(period.endTime) - start, height: size.height,
                    )),
                    with: .color(.white.opacity(0.05)),
                )
            }

            for section in kiaiSections {
                let start = x(section.startTime)
                context.fill(
                    Path(CGRect(
                        x: start, y: 0,
                        width: x(section.endTime) - start, height: size.height,
                    )),
                    with: .color(Theme.Palette.warning.opacity(0.08)),
                )
            }
        }
    }

    private func playhead(width: CGFloat, height: CGFloat) -> some View {
        // Mapped across the same inset span the ruler's marks use, so the line
        // lands on the mark it is passing rather than beside it.
        let inset = Theme.Spacing.compact
        let span = max(1, width - inset * 2)
        let x = duration > 0 ? inset + currentTime / duration * span : inset

        return ZStack(alignment: .top) {
            Rectangle()
                .fill(Theme.Palette.playhead)
                .frame(width: 1.5)
                .shadow(color: Theme.Palette.playhead.opacity(0.6), radius: 4)

            PlayheadHandle(tint: Theme.Palette.playhead)
                .offset(y: -Theme.Spacing.snug)
        }
        .frame(height: height, alignment: .top)
        .offset(x: x - 1)
    }

    // ─── Formatting ──────────────────────────────────────────────────────────

    /// Label spacing chosen so labels never crowd, using the 1-2-5 progression
    /// chart axes use.
    static func labelInterval(duration: Double, width: CGFloat) -> Double {
        guard duration > 0, width > 0 else { return 0 }
        let targetMs = Double(90 / width) * duration

        let candidates: [Double] = [
            1_000, 2_000, 5_000,
            10_000, 15_000, 30_000,
            60_000, 120_000, 300_000,
        ]
        return candidates.first { $0 >= targetMs } ?? candidates[candidates.count - 1]
    }

    static func timeLabel(_ milliseconds: Double) -> String {
        let totalSeconds = Int(milliseconds / 1000)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

// ─── Track row ───────────────────────────────────────────────────────────────

private struct TrackRowView: View {
    let track: ScriptTrack
    let isSelected: Bool
    let duration: Double
    let headerWidth: CGFloat
    let height: CGFloat
    let select: () -> Void
    let toggleVisibility: () -> Void
    let toggleLock: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.snug) {
            header
            content
        }
        .frame(height: height)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(.white.opacity(isSelected ? 0.05 : isHovered ? 0.025 : 0))
        }
        .contentShape(.rect)
        .onTapGesture(perform: select)
        .onHover { isHovered = $0 }
        .animation(Theme.Motion.quick, value: isSelected)
    }

    /// Track name with its own underline, and the per-track toggles — the
    /// layout the reference uses for a clip lane.
    private var header: some View {
        HStack(spacing: Theme.Spacing.snug) {
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name.uppercased())
                    .font(Theme.Typography.micro)
                    .tracking(0.6)
                    .foregroundStyle(
                        track.isVisible ? Theme.Palette.secondary : Theme.Palette.tertiary,
                    )
                    .lineLimit(1)

                Rectangle()
                    .fill(track.layer.tint)
                    .frame(width: 22, height: 1.5)
            }

            Spacer(minLength: 0)

            HeaderToggle(
                systemImage: track.isVisible ? "eye" : "eye.slash",
                isActive: track.isVisible,
                help: track.isVisible ? "Hide" : "Show",
                action: toggleVisibility,
            )

            HeaderToggle(
                systemImage: track.isLocked ? "lock.fill" : "lock.open",
                isActive: track.isLocked,
                help: track.isLocked ? "Unlock" : "Lock",
                action: toggleLock,
            )
        }
        .padding(.horizontal, Theme.Spacing.snug)
        .frame(width: headerWidth, alignment: .leading)
    }

    /// Spans drawn as clip pills rather than filled rectangles, so a track
    /// reads as content sitting on the timeline.
    private var content: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Theme.Radius.bar, style: .continuous)
                    .fill(.white.opacity(0.03))

                ForEach(Array(track.activeRanges.enumerated()), id: \.offset) { index, range in
                    let start = duration > 0 ? range.lowerBound / duration * width : 0
                    let end = duration > 0 ? range.upperBound / duration * width : 0
                    let spanWidth = max(3, end - start)

                    TrackBlock(
                        tint: track.layer.tint,
                        // A narrow pill has no room for text, and a truncated
                        // label reads as a rendering fault.
                        label: spanWidth > 90 ? spanLabel(index: index) : nil,
                        isDimmed: !track.isVisible,
                    ) {
                        if spanWidth > 56 {
                            SpanThumbnail(tint: track.layer.tint, height: height - 16)
                        }
                    } badge: {
                        if spanWidth > 140 {
                            BlockBadge(systemImage: "photo")
                        }
                    }
                    .frame(width: spanWidth)
                    .offset(x: start)
                }
            }
            .padding(.vertical, Theme.Spacing.tight)
        }
    }

    /// A span covers thousands of sprites, so it is named by what it is rather
    /// than by a file: the layer, and how many spans came before it.
    private func spanLabel(index: Int) -> String {
        track.activeRanges.count > 1
            ? "\(track.name) \(index + 1)"
            : track.name
    }
}

// ─── Header toggle ───────────────────────────────────────────────────────────

private struct HeaderToggle: View {
    let systemImage: String
    let isActive: Bool
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(Theme.Typography.micro)
                .foregroundStyle(isActive ? Theme.Palette.secondary : Theme.Palette.tertiary)
                .frame(width: Theme.Size.controlTiny, height: Theme.Size.controlTiny)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        .fill(.white.opacity(isHovered ? 0.12 : 0.06))
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovered = $0 }
        .animation(Theme.Motion.quick, value: isHovered)
    }
}

// ─── Span thumbnail ──────────────────────────────────────────────────────────

/// Stands in for a clip's preview image.
///
/// A span is thousands of sprites rather than one file, so there is no single
/// frame to show; this keeps the shape of the reference's layout until sprite
/// previews exist.
private struct SpanThumbnail: View {
    let tint: Color
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [.black.opacity(0.45), tint.opacity(0.35)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing,
                ),
            )
            .overlay {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(width: height * 1.5, height: height)
    }
}

// ─── Layer colours ───────────────────────────────────────────────────────────

extension Layer {
    /// A colour per layer, so a track is identifiable at a glance in both the
    /// list and the timeline.
    var tint: Color {
        switch self {
        case .background: Theme.TrackPalette.blue
        case .fail: Theme.TrackPalette.red
        case .pass: Theme.TrackPalette.green
        case .foreground: Theme.TrackPalette.violet
        case .overlay: Theme.TrackPalette.pink
        }
    }
}
