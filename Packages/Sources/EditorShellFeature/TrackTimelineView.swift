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
    let seek: (Double) -> Void

    /// Width of the track headers.
    private static let headerWidth: CGFloat = 132
    private static let rulerHeight: CGFloat = 26
    /// Tall enough for a clip pill to carry a thumbnail and a label.
    private static let trackHeight: CGFloat = 52

    /// Total height for `trackCount` rows, so the shell can size the workspace
    /// around a timeline that grows with its content.
    static func height(trackCount: Int) -> CGFloat {
        rulerHeight
            + (trackHeight + Theme.Spacing.tight) * CGFloat(max(trackCount, 1))
            + Theme.Spacing.snug * 2
    }

    var body: some View {
        VStack(spacing: 0) {
            ruler
            tracks
        }
        .padding(Theme.Spacing.snug)
        .surface(.panel)
    }

    // ─── Ruler ───────────────────────────────────────────────────────────────

    private var ruler: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Self.headerWidth)

            GeometryReader { proxy in
                Canvas { context, size in
                    drawRuler(in: context, size: size)
                }
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            seek(value.location.x / proxy.size.width * duration)
                        },
                )
            }
        }
        .frame(height: Self.rulerHeight)
    }

    private func drawRuler(in context: GraphicsContext, size: CGSize) {
        let interval = Self.labelInterval(duration: duration, width: size.width)
        guard interval > 0, duration > 0 else { return }

        let midline = size.height / 2
        var time = 0.0

        while time <= duration {
            let x = time / duration * size.width

            let label = context.resolve(
                Text(Self.timeLabel(time))
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.secondary),
            )
            let labelSize = label.measure(in: size)
            context.draw(label, at: CGPoint(x: x, y: midline), anchor: .center)

            // Dots bridging the gap to the next label, which is what gives the
            // ruler its rhythm without adding another row of ticks.
            let gapStart = x + labelSize.width / 2 + Theme.Spacing.snug
            let gapEnd = x + interval / duration * size.width
                - labelSize.width / 2 - Theme.Spacing.snug

            if gapEnd > gapStart {
                let spacing: CGFloat = 6
                var dotX = gapStart
                while dotX < gapEnd {
                    context.fill(
                        Path(ellipseIn: CGRect(x: dotX, y: midline - 1, width: 2, height: 2)),
                        with: .color(.white.opacity(0.18)),
                    )
                    dotX += spacing
                }
            }

            time += interval
        }
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

                playhead(width: trackWidth, height: proxy.size.height)
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
        let x = duration > 0 ? currentTime / duration * width : 0

        return ZStack(alignment: .top) {
            Rectangle()
                .fill(Theme.Palette.accent)
                .frame(width: 2)
                .elevated(Theme.Elevation.low)

            PlayheadHandle()
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
