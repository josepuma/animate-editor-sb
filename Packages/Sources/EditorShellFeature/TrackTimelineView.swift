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
    /// The span the timeline covers.
    ///
    /// Not just the track's length: a storyboard can open before the first note
    /// and run past the last, and an editor has to show both.
    let timelineRange: ClosedRange<Double>
    /// Where the audio itself ends, for the row that draws it.
    let audioDuration: Double
    let breaks: [BreakPeriod]
    let kiaiSections: [KiaiSection]
    let waveformPeaks: [Float]
    let seek: (Double) -> Void

    /// Rises from 0 to 1 when the waveform arrives, so the marks grow into
    /// place instead of appearing mid-playback.
    @State private var waveformGrowth: Double = 0

    /// Width of the track headers.
    static let headerWidth: CGFloat = 132
    private static let rulerHeight: CGFloat = 32
    /// Tall enough for a clip pill to carry a thumbnail and a label.
    private static let trackHeight: CGFloat = 52
    /// Shorter than a clip row: the waveform is reference, not content to edit.
    private static let audioTrackHeight: CGFloat = 40

    /// What the ruler and every track row span, given the width inside the
    /// panel's padding.
    ///
    /// One formula rather than one per caller: the header column and the gap
    /// beside it come off the width in three places — the ruler, the rows and
    /// the playhead — and a version that forgets the gap puts the blocks eight
    /// points out of step with the scale above them.
    static func contentWidth(in innerWidth: CGFloat) -> CGFloat {
        max(0, innerWidth - contentOrigin)
    }

    /// Where that content starts, measured from the panel's own edge.
    static var contentOrigin: CGFloat {
        headerWidth + Theme.Spacing.snug
    }

    /// Total height for `trackCount` rows, so the shell can size the workspace
    /// around a timeline that grows with its content.
    static func height(trackCount: Int) -> CGFloat {
        rulerHeight
            // The gap the stack puts between the ruler and the first row.
            + Theme.Spacing.snug
            // The audio row, which is always there once a track is loaded.
            + audioTrackHeight + Theme.Spacing.tight
            + (trackHeight + Theme.Spacing.tight) * CGFloat(max(trackCount, 1))
            + Theme.Spacing.compact * 2
    }

    var body: some View {
        // The padding goes outside the reader, so `proxy.size` is the space the
        // content actually gets. Inside, the reader still reports the full
        // panel and every span measured from it runs long.
        GeometryReader { proxy in
            let contentWidth = Self.contentWidth(in: proxy.size.width)

            ZStack(alignment: .topLeading) {
                // The ruler is a band of its own, so it needs more room beneath
                // it than the track rows need between them — flush against the
                // first row, it reads as part of that row rather than as the
                // scale the rows are measured against.
                VStack(spacing: Theme.Spacing.snug) {
                    HStack(spacing: Theme.Spacing.snug) {
                        tools
                        // Given the same span the rows get, rather than left to
                        // take what the stack has over: the two are compared by
                        // eye every time the playhead crosses a block, so they
                        // cannot be allowed to disagree by a rounding.
                        ruler(width: contentWidth)
                            .frame(width: contentWidth, height: Self.rulerHeight)
                            .background {
                                RoundedRectangle(
                                    cornerRadius: Theme.Radius.control,
                                    style: .continuous,
                                )
                                .fill(Theme.Fill.subtle)
                            }
                    }
                    tracks(contentWidth: contentWidth)
                }

                // Drawn over both, so the line runs unbroken from the ruler
                // down through every track.
                playhead(width: contentWidth, height: proxy.size.height)
                    .offset(x: Self.contentOrigin)
                    .allowsHitTesting(false)
            }
        }
        .padding(Theme.Spacing.compact)
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

    private func ruler(width: CGFloat) -> some View {
        let scale = TimelineScale(range: timelineRange, width: width)

        return ZStack(alignment: .leading) {
            Canvas { context, size in
                drawRuler(in: context, size: size, growth: waveformGrowth)
            }
        }
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    seek(scale.time(atX: value.location.x))
                },
        )
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
        let scale = TimelineScale(range: timelineRange, width: size.width)
        let interval = Self.labelInterval(duration: scale.duration, width: size.width)
        guard interval > 0 else { return }

        // Inset so the first label and the last mark sit inside the well's
        // rounded corners instead of touching them.
        let inset = Theme.Spacing.compact

        // Place the labels first, keeping the span each one occupies.
        var labels: [(text: GraphicsContext.ResolvedText, centre: CGFloat, span: ClosedRange<CGFloat>)] = []
        // Ticks land on round times rather than on the span's own start, so a
        // storyboard opening at -420ms still shows 0:00 where the track begins.
        var time = (timelineRange.lowerBound / interval).rounded(.down) * interval

        while time <= timelineRange.upperBound {
            defer { time += interval }

            // A tick rounded down from a negative start can land before the
            // span begins. Nudging it inwards instead of dropping it stacks it
            // on top of the next one, which is what turns the left end of the
            // ruler into overlapping text.
            guard time >= timelineRange.lowerBound else { continue }

            let resolved = context.resolve(
                Text(Self.timeLabel(time))
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.secondary),
            )
            let width = resolved.measure(in: size).width
            let ideal = scale.x(of: time)
            // Nudge the ends inwards: centred on its own timestamp, the first
            // label would hang off the left edge and read as clipped.
            let centre = min(
                max(ideal, inset + width / 2),
                size.width - inset - width / 2,
            )

            // A label pushed onto its neighbour is worse than one left out.
            if let previous = labels.last, centre - previous.centre < width {
                continue
            }

            labels.append((
                resolved,
                centre,
                (centre - width / 2 - Theme.Spacing.snug)...(centre + width / 2 + Theme.Spacing.snug),
            ))
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
                range: timelineRange,
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
    /// The time a point along the ruler corresponds to.
    ///
    /// Measured against the full width, the same span the clips and the
    /// playhead use: clicking has to leave the playhead where the pointer was,
    /// and the ruler's inset is a detail of how its dots are drawn rather than
    /// a different timeline.
    static func time(atX x: CGFloat, width: CGFloat, range: ClosedRange<Double>) -> Double {
        TimelineScale(range: range, width: width).time(atX: x)
    }

    /// How fully a mark at `x` counts as played, from 0 to 1.
    ///
    /// A ramp a few marks wide rather than a step: switching each mark at the
    /// exact moment the playhead crosses it makes the row flicker.
    static func playedRatio(
        atX x: CGFloat,
        width: CGFloat,
        currentTime: Double,
        range: ClosedRange<Double>,
    ) -> Double {
        // A span with no length has nothing to be part-way through, so nothing
        // counts as played rather than everything before an arbitrary point.
        guard width > 0, range.upperBound > range.lowerBound else { return 0 }

        let playheadX = Double(TimelineScale(range: range, width: width).x(of: currentTime))
        let fade: Double = 24

        if Double(x) <= playheadX - fade { return 1 }
        if Double(x) >= playheadX { return 0 }
        return (playheadX - Double(x)) / fade
    }

    // ─── Tracks ──────────────────────────────────────────────────────────────

    /// - Parameter contentWidth: measured once by the body. A reader of its own
    ///   here would report whatever the enclosing stack offered rather than the
    ///   span the ruler was drawn against, and the two would disagree.
    private func tracks(contentWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: Theme.Spacing.tight) {
                ForEach(shell.tracks) { track in
                    TrackRowView(
                        track: track,
                        isSelected: track.id == shell.selectedTrackID,
                        scale: TimelineScale(range: timelineRange, width: contentWidth),
                        headerWidth: Self.headerWidth,
                        height: Self.trackHeight,
                        select: { shell.selectedTrackID = track.id },
                        toggleVisibility: { shell.toggleVisibility(of: track.id) },
                        toggleLock: { shell.toggleLock(of: track.id) },
                    )
                }

                // The soundtrack sits under the layers it is written against,
                // the way a video editor puts audio beneath its video tracks.
                if !waveformPeaks.isEmpty {
                    AudioTrackRow(
                        peaks: waveformPeaks,
                        scale: TimelineScale(range: timelineRange, width: contentWidth),
                        audioDuration: audioDuration,
                        headerWidth: Self.headerWidth,
                        height: Self.audioTrackHeight,
                    )
                }
            }

            // Regions and the playhead span every row, so they are drawn
            // over the stack rather than inside each one.
            if Self.showsRegions {
                regionOverlay(width: contentWidth)
                    .offset(x: Self.contentOrigin)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let scale = TimelineScale(range: timelineRange, width: contentWidth)
                    seek(scale.time(atX: value.location.x - Self.contentOrigin))
                },
        )
        .frame(
            height: (Self.trackHeight + Theme.Spacing.tight)
                * CGFloat(max(shell.tracks.count, 1))
                + (waveformPeaks.isEmpty ? 0 : Self.audioTrackHeight + Theme.Spacing.tight),
        )
    }

    /// Whether break and kiai bands are painted across the tracks.
    ///
    /// Off for now: they belong to the beatmap's gameplay rather than to the
    /// storyboard being edited, and tinting every lane behind the clips costs
    /// more clarity than the information is worth here. Kept rather than
    /// deleted because the parser already supplies both, so turning them back
    /// on is one flag.
    private static let showsRegions = false

    private func regionOverlay(width: CGFloat) -> some View {
        Canvas { context, size in
            let scale = TimelineScale(range: timelineRange, width: size.width)
            let x = { (time: Double) in scale.x(of: time) }

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
        // Mapped across the full span the clips are drawn on, not the ruler's
        // inset one. The inset exists to keep the ruler's dots off its rounded
        // corners; borrowing it here would park the playhead twelve points to
        // the right of the block it is entering, and the block is what the eye
        // checks it against.
        let x = TimelineScale(range: timelineRange, width: width).x(of: currentTime)

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
        // Signed, because a storyboard can open before the track does and
        // `-0:03` is the honest label for what sits there. Formatting the
        // magnitude and prefixing it keeps `-0:03` from printing as `0:-3`.
        let totalSeconds = Int(abs(milliseconds) / 1000)
        let sign = milliseconds < 0 ? "-" : ""

        return String(format: "%@%d:%02d", sign, totalSeconds / 60, totalSeconds % 60)
    }
}

// ─── Track row ───────────────────────────────────────────────────────────────

private struct TrackRowView: View {
    let track: ScriptTrack
    let isSelected: Bool
    /// The span and width the clips are drawn against, measured once by the
    /// timeline.
    ///
    /// Passed in rather than measured here: `content` is a `GeometryReader`,
    /// which takes whatever it is offered, and the stack around it has no width
    /// of its own — so the row would grow past the panel's right edge.
    let scale: TimelineScale
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
                .frame(width: scale.width)

            Spacer(minLength: 0)
        }
        .frame(height: height)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(rowFill)
        }
        .contentShape(.rect)
        .onTapGesture(perform: select)
        .onHover { isHovered = $0 }
        .animation(Theme.Motion.quick, value: isSelected)
        .animation(Theme.Motion.quick, value: isHovered)
    }

    /// Fainter than the shared row fills on purpose: a track row is several
    /// times the height of a list row, and the same opacity over that much area
    /// reads as a lit panel rather than as a highlighted row.
    private var rowFill: Color {
        if isSelected { return Theme.Fill.rowSelected }
        return isHovered ? Theme.Fill.rowHover : .clear
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
                    .frame(width: Theme.Size.controlTiny, height: Theme.Size.ring)
            }

            Spacer(minLength: 0)

            IconButton(
                systemImage: track.isVisible ? "eye" : "eye.slash",
                size: Theme.Size.controlTiny,
                prominence: .filled,
                isActive: track.isVisible,
                help: track.isVisible ? "Hide" : "Show",
                action: toggleVisibility,
            )

            IconButton(
                systemImage: track.isLocked ? "lock.fill" : "lock.open",
                size: Theme.Size.controlTiny,
                prominence: .filled,
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
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: Theme.Radius.bar, style: .continuous)
                .fill(Theme.Fill.subtle)

            ForEach(Array(track.activeRanges.enumerated()), id: \.offset) { index, range in
                let start = scale.x(of: range.lowerBound)
                let spanWidth = max(3, scale.x(of: range.upperBound) - start)

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

    /// A span covers thousands of sprites, so it is named by what it is rather
    /// than by a file: the layer, and how many spans came before it.
    private func spanLabel(index: Int) -> String {
        track.activeRanges.count > 1
            ? "\(track.name) \(index + 1)"
            : track.name
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
