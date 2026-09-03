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
    /// The playhead, read from the model rather than stored.
    ///
    /// A stored one is a property that changes sixty times a second, and
    /// SwiftUI rebuilds a view when a stored property changes — the whole
    /// timeline, to move one line. The marker reads the observed copy; every
    /// other use here wants the value at the moment of a click or a menu, which
    /// is exactly what an ignored one gives.
    private var currentTime: Double { shell.playheadTime }
    /// Whether the clock is running: a keyframe cannot be placed against a
    /// moving playhead.
    let isPlaying: Bool
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

    /// How much of the storyboard is on screen, and which part.
    ///
    /// Only the magnification and offset are stored; the span they apply to is
    /// read from `timelineRange` on every use. Keeping a copy of the span in
    /// state means it can fall behind — the range arrives in two stages, first
    /// from the sprites and again once the audio is measured — and a window
    /// computed against a stale span puts the ruler and the clips on different
    /// timelines.
    @State private var zoomState = TimelineZoom.State()
    /// The zoom to return to when the keyframe editor closes.
    ///
    /// Zoom is a magnification and an offset, both meaningless against a
    /// different span: carried from a three-minute song into a twenty-second
    /// clip they put the visible window somewhere the clip is not, and every
    /// key drawn against it lands far from the playhead it was placed at.
    @State private var zoomBeforeKeyframes: TimelineZoom.State?
    /// How far the current pan drag had travelled at the last event.
    /// Where the window started when a pan drag began.
    @State private var panOrigin: Double?
    /// When the view was last moved by hand, so the clock does not fight it.
    @State private var lastManualPan: Date = .distantPast

    /// Whether someone is moving the timeline right now.
    ///
    /// A moment's grace after the last scroll rather than only during a drag: a
    /// wheel arrives as a burst of separate events with gaps between them, and
    /// a follow that slipped into one of those gaps undid the scroll that was
    /// still in progress.
    private var isPanning: Bool {
        panOrigin != nil || Date().timeIntervalSince(lastManualPan) < 0.4
    }

    /// The span the timeline actually has to cover.
    ///
    /// `timelineRange` describes the loaded storyboard and its audio, and knows
    /// nothing about effects placed on top. An effect dragged past the end of
    /// the track would fall outside the window, where the row drops it for
    /// being off screen — the block vanishing mid-drag, taking the gesture with
    /// it. With no project open at all the range is `0...1`, so the first
    /// effect placed would never be visible.
    private var fullRange: ClosedRange<Double> {
        // Editing one clip's keys, the timeline *is* that clip. Its keyframes
        // are placed against its own length, so a ruler spanning the whole song
        // leaves them crushed into a few pixels — and lets the playhead wander
        // somewhere the clip does not exist, where every value reads as the one
        // its last key left behind.
        if let node = shell.keyframeNode {
            return node.startTime...max(node.startTime + 1, node.endTime)
        }

        // Measured with the repeats included, so a looped clip's ghost has room
        // on the ruler rather than running off the end of it.
        guard let effects = shell.effects.timeRange(
            playedDuration: { trackID, duration in
                shell.duration(of: duration, on: trackID)
            },
        ) else { return timelineRange }
        let lower = min(timelineRange.lowerBound, effects.lowerBound)
        let upper = max(timelineRange.upperBound, effects.upperBound)
        return lower...upper
    }

    private var zoom: TimelineZoom {
        TimelineZoom(full: fullRange, state: zoomState)
    }

    /// Applies a change to the zoom, keeping only what the view stores.
    private func mutateZoom(_ change: (inout TimelineZoom) -> Void) {
        var updated = zoom
        change(&updated)
        zoomState = updated.state
        // Reported so it can be saved with the project: the view's own state is
        // gone by the time a file is written.
        shell.timelineView = Project.TimelineView(
            magnification: updated.magnification,
            start: updated.start,
        )
    }

    /// What the ruler and rows are drawn against: the visible window, which is
    /// the whole storyboard until someone zooms in.
    private var visibleRange: ClosedRange<Double> {
        zoom.visible
    }

    /// Width of the track headers.
    static let headerWidth: CGFloat = 132
    private static let rulerHeight: CGFloat = 32
    /// Tall enough for a clip pill to carry a thumbnail and a label.
    private static let trackHeight: CGFloat = 52

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
    /// - Parameter isEditingKeyframes: the keyframe editor replaces the lanes
    ///   rather than sitting under them, so it has a height of its own.
    static func height(trackCount: Int, isEditingKeyframes: Bool = false) -> CGFloat {
        let rows = isEditingKeyframes
            ? KeyframeRows.height
            : (trackHeight + Theme.Spacing.tight) * CGFloat(max(trackCount, 1))

        return rulerHeight
            // The gap the stack puts between the ruler and the first row.
            + Theme.Spacing.snug
            + min(rows, maximumRowsHeight)
            // The panel's own inset, top and bottom.
            //
            // Counted once here and once by the padding around the stack, the
            // rows were given less room than the scroll view was told to fill —
            // so the last lane was cut off with nowhere to scroll to. One place
            // decides the height, and the ceiling below is measured against the
            // same number.
            + Theme.Spacing.compact * 2
    }

    /// The room the lanes actually get, once the ruler and the insets have
    /// taken theirs.
    static func rowsHeight(trackCount: Int) -> CGFloat {
        min((trackHeight + Theme.Spacing.tight) * CGFloat(max(trackCount, 1)), maximumRowsHeight)
    }

    /// Rows plus the ruler and the gap between them, which is everything the
    /// inner stack has to fit.
    ///
    /// The panel's frame and this have to agree exactly. Given less than it
    /// needs, the stack does not scroll — it squeezes, and the last lane is
    /// shaved thinner with every track added.
    static func stackHeight(trackCount: Int, isEditingKeyframes: Bool) -> CGFloat {
        let rows = isEditingKeyframes ? KeyframeRows.height : rowsHeight(trackCount: trackCount)
        return rulerHeight + Theme.Spacing.snug + rows
    }

    /// Ceiling on the space the effect rows take, after which they scroll.
    ///
    /// Roughly five rows. Without a ceiling the timeline grows with every
    /// effect placed and eventually squeezes the canvas — which is the thing
    /// the editor is for — off the window.
    private static let maximumRowsHeight: CGFloat = (trackHeight + Theme.Spacing.tight) * 5

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
                // Given exactly what it needs, so it never has to squeeze.
                //
                // Left to take what the reader offered, the stack was handed
                // less than the ruler plus the rows come to — and a stack that
                // does not fit compresses its children rather than scrolling
                // them. Every track added shaved the last lane thinner, which
                // is what "it does not reach the bottom" looked like.
                .frame(
                    height: Self.stackHeight(
                        trackCount: shell.effects.tracks.count,
                        isEditingKeyframes: shell.keyframeNode != nil,
                    ),
                    alignment: .top,
                )

                // Drawn over both, so the line runs unbroken from the ruler
                // down through every track.
                playhead(width: contentWidth, height: proxy.size.height)
                    .offset(x: Self.contentOrigin)
                    .allowsHitTesting(false)
            }
        }
        .padding(Theme.Spacing.compact)
        .frame(height: Self.height(
            trackCount: shell.effects.tracks.count,
            isEditingKeyframes: shell.keyframeNode != nil,
        ), alignment: .top)
        .onChange(of: shell.keyframeNodeID) { _, newValue in
            if newValue != nil {
                // Entering: the clip fills the view, which is the whole point
                // of the mode.
                zoomBeforeKeyframes = zoomState
                zoomState = TimelineZoom.State()
            } else if let restored = zoomBeforeKeyframes {
                // Leaving: back to wherever the timeline was.
                zoomState = restored
                zoomBeforeKeyframes = nil
            }
        }
        .surface(.panel)
        // Scrolling sideways anywhere on the timeline pans it, not only over
        // the ruler — the lanes are most of what is on screen, and a gesture
        // that only works on a strip at the top is one nobody finds.
        .onScrollPan { delta in
            // Only a real movement counts as a hand on the timeline.
            //
            // A trackpad keeps sending events with tiny deltas as a gesture
            // decays, and marking every one of them left the view permanently
            // "being panned" — measured, `panning` was true on all 79 calls, so
            // the playhead was never followed again after a single scroll.
            guard abs(delta) >= 0.5 else { return }
            lastManualPan = Date()
            mutateZoom { zoom in
                // A finger moving right shows what is to the *left*, the same
                // direction a page scrolls under a hand.
                zoom.pan(by: -Double(delta) * zoom.windowDuration / 600)
            }
        }
        // One place decides what a new project does to the view.
        //
        // Two `onChange` handlers on the same value ran in an order nobody
        // chose: the one restoring the saved window and the one resetting to
        // the whole track, each undoing the other depending on which went last.
        .onChange(of: shell.projectFolder, initial: true) { _, _ in
            if let view = shell.timelineView {
                zoomState = TimelineZoom.State(
                    magnification: view.magnification,
                    start: view.start,
                )
            } else {
                // A project with nothing saved starts whole, which is what a
                // new span deserves — a window onto the last one means nothing
                // here.
                zoomState = TimelineZoom.State()
            }
        }
        .onChange(of: currentTime) { _, time in
            // Not while a hand is moving the view.
            //
            // Following on every frame *and* scrolling at the same time is two
            // things writing the window at once: the view lurched between where
            // the hand put it and where the clock wanted it. Whoever is holding
            // the timeline wins until they let go.
            guard !isPanning else { return }
            // Pages only once the playhead leaves the window.
            //
            // Scrolling somewhere else leaves the view there: a hand that moved
            // the timeline was looking at something, and yanking it back the
            // moment the gesture ends throws that away. The view holds until
            // the playhead crosses the edge of what is on screen, which is what
            // a video editor does.
            mutateZoom { $0.follow(time) }
        }
    }

    // ─── Tools ───────────────────────────────────────────────────────────────

    /// Editing tools, in the column above the track headers.
    ///
    /// None of these act yet — sprite editing does not exist — but they sit
    /// where the real controls will, so the strip's proportions are settled.
    ///
    /// `+` is real now: two effects can only overlap on separate lanes, so
    /// making one has to be reachable without placing an effect first.
    private var tools: some View {
        HStack(spacing: Theme.Spacing.tight) {
            if let node = shell.keyframeNode {
                // A way back, and a name: a mode with no visible exit is a mode
                // people get stuck in.
                //
                // The same `IconButton` the rest of the strip uses, so it sits
                // on the row's centre line — a plain `Button` takes its own
                // height from its label and lands a few points off, which in a
                // row of identical controls is the one thing the eye catches.
                IconButton(
                    systemImage: "chevron.left",
                    size: Theme.Size.controlTiny,
                    help: "Back to tracks",
                ) { shell.keyframeNodeID = nil }

                Text(node.name)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.secondary)
                    .lineLimit(1)

                BarDivider()
            }

            IconButton(
                systemImage: "plus",
                size: Theme.Size.controlTiny,
                help: shell.keyframeNode == nil ? "New track" : "Add keyframe at playhead",
            ) {
                if shell.keyframeNode == nil { shell.addTrack() }
            }

            IconButton(
                systemImage: "scissors",
                size: Theme.Size.controlTiny,
                help: "Split at playhead",
            ) {}

            // Editing tools on one side, view controls on the other: zoom
            // changes what is looked at rather than what is there, and the rule
            // says so without a label.
            BarDivider()

            IconButton(
                systemImage: "minus.magnifyingglass",
                size: Theme.Size.controlTiny,
                isActive: zoom.canZoomOut,
                help: "Zoom out",
            ) {
                mutateZoom { $0.zoomOut(around: currentTime) }
            }
            .disabled(!zoom.canZoomOut)

            IconButton(
                systemImage: "plus.magnifyingglass",
                size: Theme.Size.controlTiny,
                isActive: zoom.canZoomIn,
                help: "Zoom in",
            ) {
                mutateZoom { $0.zoomIn(around: currentTime) }
            }
            .disabled(!zoom.canZoomIn)
        }
        .padding(.leading, Theme.Spacing.snug)
        .frame(width: Self.headerWidth, alignment: .leading)
        .animation(Theme.Motion.quick, value: zoom.magnification)
    }

    // ─── Ruler ───────────────────────────────────────────────────────────────

    private func ruler(width: CGFloat) -> some View {
        let scale = TimelineScale(range: visibleRange, width: width)

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
        // Held-shift drags the view instead of the playhead — the same
        // distinction a video editor draws between scrubbing and panning.
        //
        // Measured from where the drag began, against the window it began in.
        // Differencing each event put the clamp in the middle of a running
        // total: at either end it trimmed the step while the total moved on, so
        // the pointer had to travel back over that slack before the view
        // answered again.
        .simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .modifiers(.shift)
                .onChanged { value in
                    guard width > 0 else { return }
                    let origin = panOrigin ?? zoom.start
                    if panOrigin == nil { panOrigin = zoom.start }

                    let travelled = Double(value.translation.width) / Double(width)
                    mutateZoom {
                        $0.state.start = origin - $0.windowDuration * travelled
                    }
                }
                .onEnded { _ in panOrigin = nil },
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
        let scale = TimelineScale(range: visibleRange, width: size.width)
        let interval = Self.labelInterval(duration: scale.duration, width: size.width)
        guard interval > 0 else { return }

        // Inset so the first label and the last mark sit inside the well's
        // rounded corners instead of touching them.
        let inset = Theme.Spacing.compact

        // Place the labels first, keeping the span each one occupies.
        var labels: [(text: GraphicsContext.ResolvedText, centre: CGFloat, span: ClosedRange<CGFloat>)] = []
        // Ticks land on round times rather than on the span's own start, so a
        // storyboard opening at -420ms still shows 0:00 where the track begins.
        var time = (visibleRange.lowerBound / interval).rounded(.down) * interval

        while time <= visibleRange.upperBound {
            defer { time += interval }

            // A tick rounded down from a negative start can land before the
            // span begins. Nudging it inwards instead of dropping it stacks it
            // on top of the next one, which is what turns the left end of the
            // ruler into overlapping text.
            guard time >= visibleRange.lowerBound else { continue }

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
                range: visibleRange,
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

    /// One clip's keyframes, across the whole width.
    ///
    /// Built here rather than inline: assembled in place, the closure list grows
    /// past what the type-checker will infer in reasonable time.
    private func keyframeEditor(_ node: EffectNode, contentWidth: CGFloat) -> some View {
        KeyframeRows(
            node: node,
            scale: TimelineScale(range: visibleRange, width: contentWidth),
            headerWidth: Self.headerWidth,
            // Clamped into the clip.
            //
            // The playhead is brought inside when the mode opens, but that runs
            // after the first render — and on that frame the rows were handed a
            // negative local time, which drew every key against a moment the
            // clip does not contain. Clamped at the source, no frame can see
            // one.
            // The **observed** playhead, so the diamond fills and empties as the
            // clock moves past a key.
            //
            // `currentTime` reads the ignored copy, which is right for anything
            // that must not redraw with the clock — and wrong here: the diamond
            // is a readout of where the playhead *is*, so a value frozen at the
            // last redraw left it stuck on whatever it said when the row was
            // drawn. The observed copy exists for exactly this.
            localTime: min(
                max(0, shell.observedPlayheadTime - node.startTime),
                node.duration,
            ),
            // Read when the click happens, not when the row was drawn.
            //
            // `localTime` below is computed in the body from `playheadTime`,
            // which is deliberately unobserved so the clock does not rebuild
            // the timeline sixty times a second. The cost is that the value
            // baked into the row is whatever it was at the last redraw — so a
            // key planted from a button landed wherever the playhead had been,
            // usually at zero. The same trap the paste shortcut hit.
            playheadNow: {
                min(max(0, shell.playheadTime - node.startTime), node.duration)
            },

            isPlaying: isPlaying,
            addKeyframe: { property, time in
                shell.beginAnimating(property, on: node.id, at: time)
            },
            moveKeyframe: { property, id, time in
                shell.moveKeyframe(id, in: property, to: time, on: node.id)
            },
            removeKeyframe: { property, id in
                shell.removeKeyframe(id, from: property, on: node.id)
            },
            setEasing: { property, id, easing in
                shell.setKeyframeEasing(easing, for: id, in: property, on: node.id)
            },
            setEnabled: { property, isEnabled in
                shell.setAnimationEnabled(
                    isEnabled,
                    for: property,
                    on: node.id,
                    keeping: currentTime - node.startTime,
                )
            },
            clear: { property in
                shell.clearKeyframes(
                    for: property,
                    on: node.id,
                    keeping: currentTime - node.startTime,
                )
            },
            selectedKey: shell.selectedKeyframe.map { ($0.property, $0.keyframeID) },
            selectKey: { property, id in
                shell.selectedKeyframe = EditorShellModel.KeyframeSelection(
                    nodeID: node.id,
                    property: property,
                    keyframeID: id,
                )
            },
        )
    }

    /// One lane, with everything it is allowed to change.
    ///
    /// Built here rather than inline in the loop: assembled in place, the
    /// closure list grows past what the type-checker will infer in reasonable
    /// time.
    private func row(_ track: EffectTrack, contentWidth: CGFloat) -> some View {
        let index = shell.effects.tracks.firstIndex { $0.id == track.id } ?? 0

        let actions = TrackActions(
            moveNode: { shell.moveEffect($0, to: $1) },
            resizeNode: { shell.resizeEffect($0, startTime: $1, duration: $2) },
            removeNode: { shell.removeEffect($0) },
            duplicateNode: { shell.duplicateEffect($0) },
            copyNode: { id in
                shell.selectedNodeID = id
                shell.copySelectedEffect()
            },
            paste: { shell.pasteEffect(at: currentTime, on: track.id) },
            canPaste: shell.copiedNode != nil,
            moveNodeToTrack: { shell.moveEffect($0, toTrack: $1) },
            removeTrack: { shell.removeTrack(track.id) },
            rename: { shell.renameTrack(track.id, to: $0) },
            applyFilter: { nodeID, type in
                guard let descriptor = shell.filters.descriptor(for: type) else { return }
                shell.addFilter(descriptor, to: nodeID)
            },
            addImage: { path, time in
                shell.addImage(at: path, time: max(0, time), on: track.id)
            },
            openKeyframes: { id in
                // Selecting it too, not only opening its keyframes.
                //
                // Double-clicking a clip in a freshly opened project left
                // nothing selected, so the inspector fell back to the lane and
                // showed a track's heading over the effect's own parameters.
                // Working on a clip's keyframes is working on that clip.
                shell.selectedNodeID = id
                shell.keyframeNodeID = id
            },
            raise: { shell.raiseTrack(track.id) },
            lower: { shell.lowerTrack(track.id) },
            canRaise: shell.effects.canRaiseTrack(track.id),
            canLower: shell.effects.canLowerTrack(track.id),
            otherTracks: shell.effects.tracks.filter { $0.id != track.id },
            previewDrop: { trackID, nodeID, range in
                guard let trackID, let nodeID, let range else {
                    shell.dropPreview = nil
                    return
                }
                shell.dropPreview = EditorShellModel.DropPreview(
                    nodeID: nodeID,
                    trackID: trackID,
                    range: range,
                )
            },
            trackID: { rows in
                guard rows != 0 else { return nil }
                // Subtracted, not added: the list is drawn front to back, so a
                // row further down the screen is *earlier* in the document.
                let target = index - rows
                guard shell.effects.tracks.indices.contains(target) else { return nil }
                return shell.effects.tracks[target].id
            },
        )

        return TrackRowView(
            track: track,
            isSelected: track.id == shell.selectedTrackID,
            shell: shell,
            scale: TimelineScale(range: visibleRange, width: contentWidth),
            headerWidth: Self.headerWidth,
            height: Self.trackHeight,
            select: {
                shell.selectedTrackID = track.id
                shell.selectedNodeID = nil
            },
            selectNode: { shell.selectedNodeID = $0 },
            toggleVisibility: { shell.toggleVisibility(of: track.id) },
            toggleLock: { shell.toggleLock(of: track.id) },
            actions: actions,
            playedDuration: { shell.duration(of: $0.duration, on: $0.id) },
            tailDuration: { shell.tail(of: $0.id) },
            passDuration: { shell.passDuration(of: $0.id) },
            passCount: { shell.passCount(of: $0.id) },
            filterIcons: { node in
                node.filters.map {
                    shell.filters.descriptor(for: $0.type)?.systemImage ?? "wand.and.stars"
                }
            },
            dropPreview: shell.dropPreview?.trackID == track.id ? shell.dropPreview : nil,
        )
    }

    /// - Parameter contentWidth: measured once by the body. A reader of its own
    ///   here would report whatever the enclosing stack offered rather than the
    ///   span the ruler was drawn against, and the two would disagree.
    private func tracks(contentWidth: CGFloat) -> some View {
        // The scroll view sits directly in this stack.
        //
        // Wrapped in a `ZStack` holding a `VStack` holding it, the height asked
        // for never arrived: measured, it was given 56 points — one row, which
        // is a scroll view's own minimum — while being told to take 280. Each
        // wrapper offered its child the ideal size rather than the one demanded,
        // and by the time the request reached the scroll view there was nothing
        // left of it.
        ZStack(alignment: .topLeading) {
                // Scrolled rather than grown: the timeline has a ceiling so a
                // project with many effects cannot squeeze the canvas — the
                // thing the editor exists for — off the window.
                ScrollView(.vertical) {
                    VStack(spacing: Theme.Spacing.tight) {
                        if let node = shell.keyframeNode {
                            keyframeEditor(node, contentWidth: contentWidth)
                        } else {
                            // Keyed on the revision as well as the id.
                            //
                            // `EffectTrack` is a value, and the row holds a
                            // copy of it. Identified by id alone, SwiftUI reuses
                            // the view when a clip's duration changes — the id
                            // is the same — and the row goes on drawing the
                            // span it was built with. The clip in the timeline
                            // then disagrees with the inspector beside it.
                            // Front to back, the way a layer list reads
                            // everywhere — and the way the layers panel already
                            // showed them. Drawing document order here put the
                            // same track at the top of one list and the bottom
                            // of the other.
                            ForEach(shell.effects.tracks.reversed()) { track in
                                row(track, contentWidth: contentWidth)
                                    .id("\(track.id)-\(shell.effectsRevision)")
                            }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                // A fixed height, not a ceiling.
                //
                // `maxHeight` permits a height without asking for one, so the
                // scroll view sized itself to its content and had nothing left
                // to scroll — six lanes of 336pt drawn inside a view that had
                // grown to 336pt. Told exactly how tall to be, it keeps the
                // overflow and scrolls it.
                .frame(height: Self.rowsHeight(trackCount: shell.effects.tracks.count))

                // No audio row.
                //
                // The waveform is already drawn into the ruler, where it doubles
                // as the progress bar — a second copy below the lanes said the
                // same thing again and took a row's height from the clips,
                // which are the only thing here anyone can act on.

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
                    let scale = TimelineScale(range: visibleRange, width: contentWidth)
                    seek(scale.time(atX: value.location.x - Self.contentOrigin))
                },
        )
        .frame(height: Self.rowsHeight(trackCount: shell.effects.tracks.count))
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
            let scale = TimelineScale(range: visibleRange, width: size.width)
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
        PlayheadMarker(shell: shell, range: visibleRange, width: width, height: height)
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

/// One lane of the timeline: a header, and every effect placed along it.
///
/// A lane holds many clips rather than being one. One row per effect turns a
/// project with thirty of them into thirty rows nobody can scan, and leaves no
/// way to say that these four belong together.
struct TrackRowView: View {
    let track: EffectTrack
    let isSelected: Bool
    /// Read from the model rather than received.
    ///
    /// Handed down as a property, a click rebuilt the whole timeline — every
    /// row, block, thumbnail and badge — because the parent read the selection
    /// to pass it. Read here, only the rows whose own answer changed are
    /// rebuilt.
    let shell: EditorShellModel
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
    let selectNode: (EffectNode.ID) -> Void
    let toggleVisibility: () -> Void
    let toggleLock: () -> Void
    let actions: TrackActions
    /// How long a clip actually runs, once its own filters are applied.
    let playedDuration: (EffectNode) -> Double
    /// How far the same pass keeps drawing past its block.
    let tailDuration: (EffectNode) -> Double
    /// One pass, tail included — the period a loop repeats on.
    let passDuration: (EffectNode) -> Double
    /// How many passes play in total.
    let passCount: (EffectNode) -> Int
    /// The glyphs for a clip's filters, for the badges on it.
    let filterIcons: (EffectNode) -> [String]
    /// Where a clip dragged from elsewhere would land, when this lane is the
    /// destination.
    let dropPreview: EditorShellModel.DropPreview?

    @State private var isHovered = false
    /// Which clip the pointer is over, so only its ears appear.
    @State private var hoveredNodeID: EffectNode.ID?
    /// The clip a filter from the library is hovering over.
    @State private var targetedNodeID: EffectNode.ID?
    /// Whether an asset is hovering over this lane.
    @State private var isAssetTargeted = false
    /// How many rows this lane has already been moved during a reorder drag.
    @State private var reorderedRows = 0
    /// The lane a drag has crossed into, applied when it ends.
    @State private var pendingTrackID: EffectTrack.ID?
    /// The name as it is being typed, committed on return or on leaving.
    @State private var editedName: String?
    @FocusState private var isNamingFocused: Bool
    /// The clip's span while a drag is in flight.
    ///
    /// Held locally so the row redraws at pointer speed. Committing on every
    /// change would re-evaluate the effect — thousands of sprites — for each
    /// pixel of movement.
    @State private var draft: (id: EffectNode.ID, range: ClosedRange<Double>)?
    /// The span the current drag started from.
    ///
    /// A gesture reports its translation from where it began, so every frame
    /// has to be measured against that same starting span. Measuring against
    /// the previous frame's draft applies the whole translation again on each
    /// event, and the clip accelerates off the timeline.
    @State private var dragOrigin: ClosedRange<Double>?
    /// The last click, for counting doubles without making singles wait.
    @State private var lastClick: (id: EffectNode.ID, at: Date) = ("", .distantPast)

    var body: some View {
        HStack(spacing: Theme.Spacing.snug) {
            header
            content
                .frame(width: scale.width)
                // Clipped to its own lane: zoomed in, a clip can begin before
                // the left edge and end past the right, and without this it
                // draws straight over the header beside it.
                .clipShape(
                    RoundedRectangle(cornerRadius: Theme.Radius.bar, style: .continuous),
                )

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
        // Assets land on the lane rather than on a clip: dropping one *makes* a
        // clip, so there is nothing to aim at yet. Where it lands in time comes
        // from where it was let go.
        // Assets only. Filters land on clips — they belong to a clip now, so
        // a lane has nothing to do with one.
        .dropDestination(for: String.self) { items, location in
            guard let asset = items.compactMap(AssetTransfer.parse).first else { return false }
            let x = location.x - headerWidth - Theme.Spacing.snug
            actions.addImage(asset.path, scale.time(atX: x))
            return true
        } isTargeted: { isAssetTargeted = $0 }
        .overlay {
            if isAssetTargeted {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .strokeBorder(track.tint, style: StrokeStyle(
                        lineWidth: Theme.Size.ring,
                        dash: [5, 3],
                    ))
                    .allowsHitTesting(false)
            }
        }
        .contextMenu { rowMenu }
        .animation(Theme.Motion.quick, value: isSelected)
        .animation(Theme.Motion.quick, value: isHovered)
        .animation(Theme.Motion.quick, value: isAssetTargeted)
    }

    /// Fainter than the shared row fills on purpose: a track row is several
    /// times the height of a list row, and the same opacity over that much area
    /// reads as a lit panel rather than as a highlighted row.
    private var rowFill: Color {
        if isSelected { return Theme.Fill.rowSelected }
        return isHovered ? Theme.Fill.rowHover : .clear
    }

    /// Track name with its own underline, and the per-track toggles.
    private var header: some View {
        HStack(spacing: Theme.Spacing.snug) {
            VStack(alignment: .leading, spacing: 2) {
                // Renamed in place: a lane's name is the one thing about it
                // worth changing often, and a dialog for a single field is a
                // dialog nobody opens.
                TextField("", text: Binding(
                    get: { editedName ?? track.name },
                    set: { editedName = $0 },
                ))
                .textFieldStyle(.plain)
                .font(Theme.Typography.micro)
                .tracking(0.6)
                .foregroundStyle(
                    track.isVisible ? Theme.Palette.secondary : Theme.Palette.tertiary,
                )
                .lineLimit(1)
                .focused($isNamingFocused)
                .onSubmit(commitName)
                .onChange(of: isNamingFocused) { _, focused in
                    if !focused { commitName() }
                }
                .onExitCommand {
                    editedName = nil
                    isNamingFocused = false
                }

                HStack(spacing: Theme.Spacing.hair) {
                    Rectangle()
                        .fill(track.tint)
                        .frame(width: Theme.Size.controlTiny, height: Theme.Size.ring)

                }
            }

            Spacer(minLength: 0)

            // A grip for reordering the lane itself, dragged the way its clips
            // are. The menu still has Bring Forward and Send Backward: a drag
            // is faster across several rows, a menu is exact for one step.
            Image(systemName: "line.3.horizontal")
                .font(Theme.Typography.micro)
                .foregroundStyle(isHovered ? Theme.Palette.secondary : Theme.Palette.tertiary)
                .contentShape(.rect)
                .gesture(reorderGesture)
                .onHover { hovering in
                    if hovering { NSCursor.openHand.push() } else { NSCursor.pop() }
                }

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

    /// Every clip on this lane, drawn as pills against the lane's own strip.
    private var content: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: Theme.Radius.bar, style: .continuous)
                .fill(Theme.Fill.subtle)

            ForEach(track.nodes) { node in
                clip(node)
            }

            ghost
        }
        .padding(.vertical, Theme.Spacing.tight)
        // Which clip is under the pointer is measured across the whole lane
        // rather than asked of each clip.
        //
        // The ears are revealed by a clip's hover but sit *outside* it, so a
        // per-clip `onHover` ended the moment the pointer crossed onto one —
        // the ear vanished from under the cursor on its way there, visible and
        // impossible to grab. Measuring here treats a clip and its ears as one
        // region, with no seam between them to fall through.
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case let .active(location):
                hoveredNodeID = nodeID(atX: location.x)
            case .ended:
                hoveredNodeID = nil
            }
        }
        // The ears fade in with the hover rather than appearing at once, which
        // at the speed a pointer crosses a timeline reads as flicker.
        .animation(Theme.Motion.quick, value: hoveredNodeID)
        .animation(Theme.Motion.quick, value: targetedNodeID)
        // The ghost fades too, so crossing a lane boundary reads as a preview
        // settling in rather than as something blinking on.
        .animation(Theme.Motion.quick, value: dropPreview)
    }

    /// An outline of where a clip dragged from another lane would land.
    ///
    /// Dimming the clip being dragged says where it is leaving from; without
    /// this there is nothing saying where it arrives, and the move only becomes
    /// visible once the mouse is already up.
    @ViewBuilder
    private var ghost: some View {
        if let preview = dropPreview,
           preview.trackID == track.id,
           let span = VisibleSpan.spans(of: [preview.range], scale: scale).first
        {
            RoundedRectangle(cornerRadius: Theme.Radius.bar, style: .continuous)
                .strokeBorder(track.tint, style: StrokeStyle(
                    lineWidth: Theme.Size.ring,
                    dash: [4, 3],
                ))
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.bar, style: .continuous)
                        .fill(track.tint.opacity(0.15))
                }
                .frame(width: span.width)
                .offset(x: span.start)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    /// The clip at a horizontal position, counting its ears as part of it.
    ///
    /// A drag in flight keeps its clip: the pointer runs ahead of the pill it
    /// is dragging, and losing the hover mid-drag would take the ears away
    /// while they are being used.
    private func nodeID(atX x: CGFloat) -> EffectNode.ID? {
        if let draft { return draft.id }

        for node in track.nodes {
            guard let span = span(of: node) else { continue }
            let from = span.start - Self.earWidth
            let to = span.start + span.width + Self.earWidth
            if x >= from, x <= to { return node.id }
        }
        return nil
    }

    /// The span a clip is drawn at: its draft while dragging, otherwise its own.
    private func span(of node: EffectNode) -> VisibleSpan? {
        let range = draft?.id == node.id ? draft!.range : node.timeRange
        return VisibleSpan.spans(of: [range], scale: scale).first
    }

    @ViewBuilder
    private func clip(_ node: EffectNode) -> some View {
        // What the repeats and the tail add, drawn behind the clip — and
        // **outside** the block's own visibility test.
        //
        // A loop leaves the block where it was while the effect plays for
        // several times as long, so zooming until the first pass scrolls off
        // the left used to take every later pass with it: the guard was on the
        // parent's span, and the repeats were nested under it. They crop
        // themselves through `VisibleSpan` already, so what is on screen is
        // drawn whether or not the clip that spawned it still is.
        tailGhost(node)
        repeatGhost(node)

        if let span = span(of: node) {
            let width = span.width

            TrackBlock(
                tint: track.tint,
                // A narrow pill has no room for text, and a truncated label
                // reads as a rendering fault.
                label: width > 90 ? node.name : nil,
                isDimmed: !track.isVisible,
                isSelected: node.id == shell.selectedNodeID,
            ) {
                if width > 56 {
                    SpanThumbnail(tint: track.tint, height: height - 16)
                }
            } badge: {
                // A badge per filter, so a clip's look is legible from the
                // timeline. Without them a filter applied is only visible after
                // selecting the clip — and one you cannot see is one you forget
                // you applied.
                if width > 140 {
                    HStack(spacing: Theme.Spacing.hair) {
                        ForEach(Array(filterIcons(node).enumerated()), id: \.offset) { _, icon in
                            BlockBadge(systemImage: icon)
                        }
                        if filterIcons(node).isEmpty {
                            BlockBadge(systemImage: "sparkles")
                        }
                    }
                }
            }
            .frame(width: width)
            .offset(x: span.start)
            // Faded while it is on its way to another lane, so the drag says
            // where the clip is going before it gets there — otherwise the
            // change only appears on release, which reads as an accident.
            .opacity(isLeaving(node) ? 0.35 : 1)
            // Clicking a clip selects it, so the inspector follows what was
            // pointed at. Without this, only dragging selected — and on a lane
            // with several clips there was no way to pick one to edit.
            //
            // One gesture that counts its own clicks, rather than two that
            // race.
            //
            // A plain `.onTapGesture` beside a `count: 2` one cannot resolve
            // until the double-click interval has passed without a second
            // click, so every selection sat waiting for a click that was never
            // coming — half a second of nothing on every clip, which read as
            // the editor being slow to think. Giving selection a
            // high-priority press instead fixed that and broke the other half:
            // a winning gesture swallows the first click of a double, so
            // keyframes could no longer be opened at all.
            //
            // Selecting on press settles both. The press reports at once,
            // because selecting is what pressing a clip already means; a second
            // click arriving soon after opens keyframes, and re-selecting the
            // same clip in between costs nothing.
            //
            // A press and not a `DragGesture(minimumDistance: 0)`: that one
            // claims the drag from the very first pixel, so it beat the move
            // gesture to its 3pt threshold and clips could no longer be dragged
            // along their lane at all. A long press of zero duration reports
            // the same moment without competing for the drag.
            // Double click counted inside the move gesture, not beside it.
            //
            // A `count: 2` tap alongside another gesture holds the event while
            // it waits for a second click — so the selection was registered at
            // once and the view settled only when that wait timed out. Measured
            // in pairs: 1ms then 269ms, 1ms then 247ms, over and over. The
            // second number is the double-click interval, and it is what the
            // delay felt like.
            .gesture(moveGesture(node))
            .contextMenu { clipMenu(node) }

            // The drop target is a layer of its own, above the clip.
            //
            // On the clip itself it never fired: a `DragGesture` and a
            // `dropDestination` on one view compete, and the gesture wins — the
            // clip could be dragged and would not accept anything. As a
            // separate view it is hit tested on its own, and it carries no
            // gesture to lose to.
            //
            // A filter is dropped *onto the thing it will change*, which is
            // where a hand aims. It still applies to the whole lane, since that
            // is where filters live.
            filterTarget(node, span: span)

            // Siblings in the stack rather than overlays on the clip. An
            // overlay shares its host's place in the hit test, and the clip's
            // own drag gesture — the one that wraps it — wins every time,
            // leaving the edges dead.
            if hoveredNodeID == node.id {
                ear(node, edge: .leading, span: span)
                ear(node, edge: .trailing, span: span)
            }
        }
    }

    /// An invisible drop layer sitting over one clip.
    @ViewBuilder
    private func filterTarget(_ node: EffectNode, span: VisibleSpan) -> some View {
        // `Color.clear` takes no hit testing of its own, so the clip beneath
        // keeps its click and its drag; a `dropDestination` still registers the
        // region with the drag session, which is the one thing this layer is
        // for.
        Color.clear
            .frame(width: span.width)
            .frame(maxHeight: .infinity)
            .offset(x: span.start)
            // Strings rather than a custom type: see `FilterTransfer` for why
            // an exported `UTType` cannot work in a SwiftPM executable.
            .dropDestination(for: String.self) { items, _ in
                guard let filter = items.compactMap(FilterTransfer.parse).first else {
                    return false
                }
                actions.applyFilter(node.id, filter.type)
                return true
            } isTargeted: { targetedNodeID = $0 ? node.id : nil }
            .overlay {
                if targetedNodeID == node.id {
                    RoundedRectangle(cornerRadius: Theme.Radius.bar, style: .continuous)
                        .strokeBorder(.white, style: StrokeStyle(
                            lineWidth: Theme.Size.ring,
                            dash: [4, 3],
                        ))
                        .background {
                            RoundedRectangle(cornerRadius: Theme.Radius.bar, style: .continuous)
                                .fill(.white.opacity(0.25))
                        }
                        .frame(width: span.width)
                        .offset(x: span.start)
                        .allowsHitTesting(false)
                }
            }
    }

    /// The stretch the clip is still drawing after its block ends.
    ///
    /// A particle lives its whole life from wherever it was born, so an emitter
    /// releasing up to the last instant is on screen for seconds afterwards —
    /// measured, about three on every compound preset. Without this the block
    /// finishes while the effect plays on, and the one thing a timeline exists
    /// to show is wrong.
    ///
    /// Drawn as a **continuation**, flush against the block, rather than as a
    /// separate box: it is the same pass still finishing, not another one
    /// starting. Repeats get the detached boxes, and telling the two apart at a
    /// glance is the point.
    ///
    /// Not part of the block itself, though — the block is what a drag resizes
    /// and what keyframes are measured against, so growing it would make
    /// dragging move something other than what is shown.
    @ViewBuilder
    private func tailGhost(_ node: EffectNode) -> some View {
        // Worked out before the builder, not inside it: a `@ViewBuilder` body
        // is not ordinary statement scope, and bindings declared in a branch
        // there leave the compiler reporting a type failure on whatever comes
        // next — six rounds chasing an error in the `ForEach` that was never
        // there.
        let spans = tailSpans(node)

        ForEach(spans) { ghost in
            // Square where it meets the clip, rounded where it ends, and
            // fading out along the way.
            //
            // Four rounded corners made it read as a second block, which is
            // exactly what a repeat looks like — and the whole reason the
            // two are drawn differently is that they mean different things.
            // A flush edge says "this is still the same clip"; the fade says
            // "and it is dying out".
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: Theme.Radius.bar,
                topTrailingRadius: Theme.Radius.bar,
                style: .continuous,
            )
            .fill(
                LinearGradient(
                    colors: [track.tint.opacity(0.3), track.tint.opacity(0.04)],
                    startPoint: .leading,
                    endPoint: .trailing,
                ),
            )
            // Slid back under the clip's rounded end, so the two meet with no
            // seam.
            //
            // A gap is exactly what says "separate thing" — which is what a
            // repeat is, and a tail is not. The overlap is in points because
            // the corner radius is: expressed in milliseconds it would be a
            // different size at every zoom level.
            .frame(width: ghost.width + Theme.Radius.bar)
            .offset(x: ghost.start - Theme.Radius.bar)
            .allowsHitTesting(false)
        }
    }

    /// Where the tail sits on screen, if there is one.
    private func tailSpans(_ node: EffectNode) -> [VisibleSpan] {
        let tail = tailDuration(node)
        guard tail > 1 else { return [] }

        // One per pass, not one at the end.
        //
        // A loop waits for a pass to finish dying before starting the next, so
        // every iteration has a tail — and left undrawn those became plain gaps
        // between the repeat ghosts, which says "nothing here" where the answer
        // is "still finishing". Drawing each one makes a looped clip read the
        // way it plays: block, fade, block, fade.
        //
        // Placed from the pass length rather than from the played total, which
        // already counts the final tail: measuring from there put it a whole
        // tail beyond where it belongs.
        let pass = passDuration(node)
        let ranges = (0 ..< passCount(node)).map { index -> ClosedRange<Double> in
            let from = node.startTime + pass * Double(index) + node.duration
            return from ... (from + tail)
        }
        return VisibleSpan.spans(of: ranges, scale: scale)
    }

    /// The stretch a looped clip covers beyond its own block.
    @ViewBuilder
    private func repeatGhost(_ node: EffectNode) -> some View {
        // One block per pass, not one long block covering them all.
        //
        // A single stretch says how much longer the clip runs and nothing else:
        // not how many times it repeats, not where each pass begins, and not
        // that a gap sits between them. Drawn as separate blocks the loop reads
        // the way it plays — and the gaps are visible as gaps rather than as
        // part of the clip.
        // The pass length and the count come from the model, not from
        // dividing the total by the clip.
        //
        // That division only held while a pass *was* the clip. Once the
        // particle tail joined the loop's period it started reporting one
        // pass too many, at a stride short of the real one — measured on a
        // Portal ×3, three ghosts where there are two, each 1667ms adrift.
        let stride = passDuration(node)
        let passes = passCount(node) - 1

        if passes >= 1, stride > 0 {
            // Clipped to the window, like the clip itself.
            //
            // Drawn from raw times, a pass was placed and sized in the
            // timeline's own scale — and zoomed in that is enormous: at 64×, a
            // six-second body is six thousand points wide and the tenth
            // repetition sits tens of thousands of points off to the right.
            // Passing the ranges through `VisibleSpan` throws away the ones off
            // screen and trims the ones that cross the edge, which is what
            // keeps a zoomed-in timeline drawable.
            let ranges = (1...passes).map { pass -> ClosedRange<Double> in
                let from = node.startTime + stride * Double(pass)
                return from...(from + node.duration)
            }

            ForEach(VisibleSpan.spans(of: ranges, scale: scale), id: \.index) { ghost in
                RoundedRectangle(cornerRadius: Theme.Radius.bar, style: .continuous)
                    .fill(track.tint.opacity(0.12))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.bar, style: .continuous)
                            .strokeBorder(track.tint.opacity(0.4), style: StrokeStyle(
                                lineWidth: Theme.Size.hairline,
                                dash: [3, 3],
                            ))
                    }
                    .frame(width: ghost.width)
                    .offset(x: ghost.start)
                    .allowsHitTesting(false)
            }
        }
    }

    // ─── Resizing ────────────────────────────────────────────────────────────

    /// A grab handle just outside one edge of a clip.
    ///
    /// Outside, not within. Sitting inside the pill, two handles and a
    /// draggable middle share whatever width the clip has — so they had to be
    /// hidden below a threshold, and at the default zoom a four-second effect
    /// on a three-minute track is under it. Resizing was simply absent until
    /// you zoomed in, which is not where anyone starts.
    @ViewBuilder
    private func ear(_ node: EffectNode, edge: HorizontalEdge, span: VisibleSpan) -> some View {
        if !track.isLocked {
            // Tucked inside when there is no room outside: the lane is clipped,
            // so an ear on a clip against either edge would be cut in half.
            let outside = edge == .leading
                ? span.start - Self.earWidth
                : span.start + span.width
            let inside = edge == .leading
                ? span.start
                : span.start + span.width - Self.earWidth
            let margin: CGFloat = 1
            let fitsOutside = edge == .leading
                ? outside >= margin
                : outside + Self.earWidth <= scale.width - margin

            // The clip's own colour, at its own radius: the ear reads as the
            // same piece extending past its edge rather than as a separate
            // control resting against it.
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .fill(track.tint.opacity(0.55))
                .frame(width: Self.earWidth)
                .padding(.vertical, Theme.Spacing.compact)
                .contentShape(.rect)
                .offset(x: fitsOutside ? outside : inside)
                .gesture(resizeGesture(node, edge: edge))
                .onHover { hovering in
                    // The cursor is the only thing telling a resize edge apart
                    // from the body that moves the whole clip.
                    if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                }
                .transition(.opacity)
        }
    }

    /// Big enough to grab without aiming. Fixed rather than proportional: an
    /// ear that shrank with the clip would be unusable exactly where it is
    /// needed most.
    private static let earWidth: CGFloat = 10

    /// Shortest clip a drag can leave behind, so one cannot be shrunk to a
    /// sliver too small to grab again.
    private static let minimumDuration: Double = 100

    private func moveGesture(_ node: EffectNode) -> some Gesture {
        // Starts at zero so a still click reaches `onEnded`, which is where
        // selection is decided. The travel threshold has not gone away — it
        // moved into `onChanged` below, so a press that has not travelled yet
        // still moves nothing.
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !track.isLocked else { return }
                // Below the threshold this is still a click that has not made
                // up its mind; moving here would make every click nudge the
                // clip it selected.
                guard abs(value.translation.width) >= Self.clickSlop
                    || abs(value.translation.height) >= Self.clickSlop
                else { return }
                let origin = beginDrag(node)

                // Converted through the scale rather than tracked in pixels: at
                // any zoom but 1:1 the two disagree and the clip drifts away
                // from the pointer.
                let shift = scale.duration(ofWidth: value.translation.width)
                let length = origin.upperBound - origin.lowerBound
                let start = max(0, origin.lowerBound + shift)
                draft = (node.id, start...(start + length))

                // Which lane the pointer has crossed into, if any.
                //
                // One gesture doing two things is normally a gesture people
                // undo — but dragging a clip between lanes is what every video
                // editor does, and it is what a hand reaches for before it
                // reads a menu. The threshold is what keeps them apart: an
                // ordinary horizontal drag never travels far enough vertically
                // to count.
                pendingTrackID = actions.trackID(rowsCrossed(value.translation.height))
                actions.previewDrop(pendingTrackID, node.id, start...(start + length))
            }
            .onEnded { value in
                // A drag that never travelled is a click, so this is also where
                // selection happens.
                //
                // It belongs to the gesture that already owns the press rather
                // than to a gesture of its own. A second `.onTapGesture` beside
                // the `count: 2` one cannot resolve until the double-click
                // interval has elapsed, which put half a second of nothing
                // between clicking a clip and the inspector following — and
                // every gesture tried instead (a high-priority press, a
                // simultaneous zero-distance drag, a zero-duration long press)
                // claimed the drag from the first pixel and stopped clips being
                // draggable at all.
                if abs(value.translation.width) < Self.clickSlop,
                   abs(value.translation.height) < Self.clickSlop
                {
                    selectNode(node.id)

                    // A second click on the same clip, soon enough after the
                    // first, opens its keyframes. Counted here rather than left
                    // to a `count: 2` tap, which would make every single click
                    // wait to find out whether it was one.
                    let now = Date()
                    if lastClick.id == node.id,
                       now.timeIntervalSince(lastClick.at) < Self.doubleClickInterval
                    {
                        actions.openKeyframes(node.id)
                        lastClick = (node.id, .distantPast)
                    } else {
                        lastClick = (node.id, now)
                    }
                }
                commit(.move)
            }
    }

    /// How far the pointer may travel and still count as a click.
    ///
    /// Matched to the move gesture's own threshold: below it nothing has moved
    /// yet, so releasing there was never a drag.
    private static let clickSlop: CGFloat = 3

    /// How long a second click still counts as a double.
    ///
    /// The system's own interval, so a double click here means what it means
    /// everywhere else on the machine.
    private static var doubleClickInterval: TimeInterval { NSEvent.doubleClickInterval }

    /// Dragging the grip moves the lane through the draw order.
    ///
    /// Committed as it crosses each row rather than on release: a lane moving
    /// under the pointer is the feedback, and a list that only rearranges when
    /// the mouse comes up leaves the drag saying nothing.
    private var reorderGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let rows = rowsCrossed(value.translation.height)
                guard rows != reorderedRows else { return }

                // Only the step just taken, since earlier ones are already
                // applied — the translation is measured from where the drag
                // began, not from the last event.
                let step = rows - reorderedRows
                for _ in 0..<abs(step) {
                    // Down the screen is earlier in the document.
                    if step > 0 { actions.lower() } else { actions.raise() }
                }
                reorderedRows = rows
            }
            .onEnded { _ in reorderedRows = 0 }
    }

    /// Whether this clip is being dragged onto a different lane.
    private func isLeaving(_ node: EffectNode) -> Bool {
        pendingTrackID != nil && draft?.id == node.id
    }

    /// How many lanes up or down the pointer has travelled.
    ///
    /// Measured against the row's own height, so the clip changes lane at the
    /// moment it visually reaches one, and needs more than half a row of
    /// deliberate vertical movement before anything happens.
    private func rowsCrossed(_ verticalTranslation: CGFloat) -> Int {
        let rowPitch = height + Theme.Spacing.tight
        return Int((verticalTranslation / rowPitch).rounded())
    }

    private func resizeGesture(_ node: EffectNode, edge: HorizontalEdge) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard !track.isLocked else { return }
                let origin = beginDrag(node)
                let shift = scale.duration(ofWidth: value.translation.width)

                switch edge {
                case .leading:
                    // Clamped against the far edge so dragging past it does not
                    // invert the clip into a negative duration.
                    let start = min(
                        max(0, origin.lowerBound + shift),
                        origin.upperBound - Self.minimumDuration,
                    )
                    draft = (node.id, start...origin.upperBound)
                case .trailing:
                    let end = max(
                        origin.upperBound + shift,
                        origin.lowerBound + Self.minimumDuration,
                    )
                    draft = (node.id, origin.lowerBound...end)
                }
            }
            .onEnded { _ in commit(.resize) }
    }

    /// Records where a drag started, and selects what is being dragged.
    ///
    /// Grabbing a clip selects it, so the inspector follows what the pointer is
    /// working on — dragging one thing while editing another is the confusing
    /// case.
    private func beginDrag(_ node: EffectNode) -> ClosedRange<Double> {
        if let dragOrigin { return dragOrigin }
        dragOrigin = node.timeRange
        if node.id != shell.selectedNodeID { selectNode(node.id) }
        return node.timeRange
    }

    private func commitName() {
        defer {
            editedName = nil
            // Handing focus back: a field that keeps it goes on swallowing
            // keystrokes meant for the app, and space is play/pause.
            isNamingFocused = false
        }
        guard let editedName, editedName != track.name else { return }
        actions.rename(editedName)
    }

    private enum EditKind { case move, resize }

    /// Writes the draft back to the model once the drag ends.
    private func commit(_ kind: EditKind) {
        defer {
            draft = nil
            dragOrigin = nil
            pendingTrackID = nil
            actions.previewDrop(nil, nil, nil)
        }
        guard let draft else { return }

        switch kind {
        case .move:
            actions.moveNode(draft.id, draft.range.lowerBound)
            // The lane change goes last: moving between tracks re-homes the
            // node, and applying the time to a node that has already moved
            // would have to find it again.
            if let pendingTrackID {
                actions.moveNodeToTrack(draft.id, pendingTrackID)
            }
        case .resize:
            actions.resizeNode(
                draft.id,
                draft.range.lowerBound,
                draft.range.upperBound - draft.range.lowerBound,
            )
        }
    }

    // ─── Menus ───────────────────────────────────────────────────────────────

    /// Right-click on the lane itself.
    @ViewBuilder
    private var rowMenu: some View {
        Button("Bring Forward", systemImage: "square.3.layers.3d.top.filled", action: actions.raise)
            .disabled(!actions.canRaise)
        Button("Send Backward", systemImage: "square.3.layers.3d.bottom.filled", action: actions.lower)
            .disabled(!actions.canLower)

        Divider()

        Button(track.isVisible ? "Hide" : "Show", action: toggleVisibility)
        Button(track.isLocked ? "Unlock" : "Lock", action: toggleLock)

        Divider()

        Divider()

        if actions.canPaste {
            Button("Paste", systemImage: "doc.on.clipboard", action: actions.paste)
                .keyboardShortcut("v", modifiers: .command)

            Divider()
        }

        Button("Delete Track", systemImage: "trash", role: .destructive, action: actions.removeTrack)
    }

    /// Right-click on one clip.
    @ViewBuilder
    private func clipMenu(_ node: EffectNode) -> some View {
        // Moving between lanes is a menu rather than a vertical drag: dragging
        // a clip already means moving it in time, and one gesture that does two
        // things depending on which way it went is a gesture people undo.
        if !actions.otherTracks.isEmpty {
            Menu("Move to Track") {
                ForEach(actions.otherTracks, id: \.id) { other in
                    Button(other.name) { actions.moveNodeToTrack(node.id, other.id) }
                }
            }
            Divider()
        }

        // The shortcuts are also on the menu: one nobody knows about does not
        // exist, and a menu is where people look for the key.
        Button("Copy", systemImage: "doc.on.doc") { actions.copyNode(node.id) }
            .keyboardShortcut("c", modifiers: .command)

        Button("Duplicate", systemImage: "plus.square.on.square") {
            actions.duplicateNode(node.id)
        }
        .keyboardShortcut("d", modifiers: .command)

        Divider()

        Button("Delete Effect", systemImage: "trash", role: .destructive) {
            actions.removeNode(node.id)
        }
        .keyboardShortcut(.delete, modifiers: [])
    }
}

// ─── Track actions ───────────────────────────────────────────────────────────

/// What a lane can do to itself and to what is on it.
///
/// Passed as closures rather than the model itself: a row that held the model
/// could reach anything, and this states exactly what a timeline row is allowed
/// to change.
struct TrackActions {
    let moveNode: (EffectNode.ID, Double) -> Void
    let resizeNode: (EffectNode.ID, Double, Double) -> Void
    let removeNode: (EffectNode.ID) -> Void
    /// Copies a clip, placing the copy right after it.
    let duplicateNode: (EffectNode.ID) -> Void
    let copyNode: (EffectNode.ID) -> Void
    /// Pastes the copied clip onto this lane, at the playhead.
    let paste: () -> Void
    let canPaste: Bool
    let moveNodeToTrack: (EffectNode.ID, EffectTrack.ID) -> Void
    let removeTrack: () -> Void
    let rename: (String) -> Void
    /// Applies a filter dropped onto one of this lane's clips.
    let applyFilter: (EffectNode.ID, String) -> Void
    /// Places an image dropped from the assets panel, at a time on this lane.
    let addImage: (String, Double) -> Void
    /// Opens the timeline on one clip's keyframes.
    let openKeyframes: (EffectNode.ID) -> Void
    let raise: () -> Void
    let lower: () -> Void
    let canRaise: Bool
    let canLower: Bool
    /// The lanes a clip could be moved to — every track but this one.
    let otherTracks: [EffectTrack]
    /// Shows where a dragged clip would land, on whichever lane that is.
    ///
    /// Routed through the model because the preview is drawn by the
    /// destination row, and a row cannot draw into its neighbour.
    let previewDrop: (EffectTrack.ID?, EffectNode.ID?, ClosedRange<Double>?) -> Void
    /// The lane `rows` away from this one, or `nil` when there is none there.
    ///
    /// Rows are counted the way the timeline draws them — the list is reversed
    /// for display, so dragging up moves *later* in the document.
    let trackID: (Int) -> EffectTrack.ID?
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

extension TrackColour {
    /// What each name looks like.
    ///
    /// The mapping lives here rather than in Core, which has no business
    /// knowing what blue is.
    var colour: Color {
        switch self {
        case .blue: Theme.TrackPalette.blue
        case .violet: Theme.TrackPalette.violet
        case .pink: Theme.TrackPalette.pink
        case .teal: Theme.TrackPalette.teal
        case .amber: Theme.TrackPalette.amber
        case .green: Theme.TrackPalette.green
        case .red: Theme.TrackPalette.red
        }
    }
}

extension EffectTrack {
    /// The colour this track draws in: its own, or its layer's until one is
    /// chosen.
    var tint: Color { colour?.colour ?? layer.tint }
}

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




// ─── Playhead ────────────────────────────────────────────────────────────────

/// The line that follows the clock.
///
/// A view of its own, reading the time from the model rather than receiving it.
///
/// Drawn inside the timeline's body, the moving clock rebuilt that body — every
/// row, block, ruler tick and waveform mark — sixty times a second, to move one
/// line a couple of points. Measured at 25 to 35 rebuilds a second while
/// playing, and the fps matched. Here only this view answers the clock, and the
/// rest of the timeline is rebuilt when something about it actually changes.
private struct PlayheadMarker: View {
    let shell: EditorShellModel
    let range: ClosedRange<Double>
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        // Mapped across the full span the clips are drawn on, not the ruler's
        // inset one. The inset exists to keep the ruler's dots off its rounded
        // corners; borrowing it here would park the playhead twelve points to
        // the right of the block it is entering, and the block is what the eye
        // checks it against.
        let x = TimelineScale(range: range, width: width).x(of: shell.observedPlayheadTime)

        ZStack(alignment: .top) {
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
}
