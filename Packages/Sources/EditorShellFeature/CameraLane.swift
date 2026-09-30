import DesignSystem
import StoryboardCore
import SwiftUI

/// The storyboard camera's lane, pinned above every track.
///
/// A lane rather than a button because the camera is **timed**: its keys sit
/// on the same song the clips do, and seeing a push-in land on the drop is the
/// reason to have a camera at all. Pinned at the top because it is above
/// everything — it is the view every track is seen through.
///
/// The lane shows where the keys are; double-clicking it opens the camera's
/// own keyframe mode, the way double-clicking a clip opens its keys. Editing
/// happens there, at full width, not in a strip forty points tall.
struct CameraLaneView: View {
    let camera: StoryboardCamera
    let scale: TimelineScale
    let headerWidth: CGFloat
    let height: CGFloat
    /// Whether a camera edit is still being baked in.
    var isApplying = false
    let open: () -> Void

    @State private var isHovered = false

    private var keyCount: Int {
        CameraProperty.allCases.reduce(0) { $0 + camera[$1].keyframes.count }
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.snug) {
            header
            content
                .frame(width: scale.width)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.clip, style: .continuous))
            Spacer(minLength: 0)
        }
        .frame(height: height)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.clip, style: .continuous)
                .fill(isHovered ? Theme.Fill.rowHover : .clear)
        }
        .contentShape(.rect)
        .onTapGesture(count: 2, perform: open)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Edit Camera Keyframes", systemImage: "video", action: open)
        }
        .animation(Theme.Motion.quick, value: isHovered)
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.snug) {
            Image(systemName: "video")
                .font(Theme.Typography.micro)
                .foregroundStyle(camera.isAtRest ? Theme.Palette.tertiary : Theme.Palette.secondary)

            Text("Camera")
                .font(Theme.Typography.micro)
                .tracking(0.6)
                .foregroundStyle(camera.isAtRest ? Theme.Palette.tertiary : Theme.Palette.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if isApplying {
                ProgressView()
                    .controlSize(.small)
                    .help("Applying the camera")
            }

            IconButton(
                systemImage: "slider.horizontal.3",
                size: Theme.Size.controlTiny,
                prominence: .filled,
                help: keyCount == 0 ? "Animate the camera" : "Edit \(keyCount) camera keyframes",
                action: open,
            )
        }
        .padding(.horizontal, Theme.Spacing.snug)
        .frame(width: headerWidth, alignment: .leading)
    }

    /// Every camera key, where it falls in the song.
    private var content: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: Theme.Radius.clip, style: .continuous)
                .fill(Theme.Fill.subtle)

            // A lane-wide spacer, so the keys are placed against the lane's own
            // width rather than centred inside a box the size of the diamonds.
            Color.clear.frame(width: scale.width, height: height)

            ForEach(CameraProperty.allCases, id: \.self) { property in
                let track = camera[property]
                ForEach(track.keyframes) { key in
                    CameraKeyMark(
                        colour: track.isActive
                            ? CameraKeyframeRows.colour(for: property) : Theme.Palette.tertiary
                    )
                    .offset(x: scale.x(of: key.time) - CameraKeyMark.size / 2)
                    .allowsHitTesting(false)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.tight)
    }
}

/// A camera key on the lane: a small diamond, read-only.
private struct CameraKeyMark: View {
    static let size: CGFloat = 8
    let colour: Color

    var body: some View {
        Rectangle()
            .fill(colour)
            .frame(width: Self.size / 1.414, height: Self.size / 1.414)
            .rotationEffect(.degrees(45))
            .frame(width: Self.size, height: Self.size)
    }
}

/// The camera's keyframe rows: pan and zoom, in song time.
///
/// The same `KeyframeRow` a clip's properties use, so dragging, easing and
/// deleting a key work one way everywhere. The difference is only the clock:
/// a row is told its clip starts at zero and its local time *is* the song's,
/// which is exactly what a camera keyed in song time needs.
struct CameraKeyframeRows: View {
    let shell: EditorShellModel
    let scale: TimelineScale
    let headerWidth: CGFloat
    let isPlaying: Bool
    /// Moves the playhead, in song time — the timeline's own, the one a
    /// clip's keyframe arrows use.
    let seek: (Double) -> Void

    /// The header, plus one row per property while the group is open.
    /// Shared with whoever sizes the timeline: a height worked out apart from
    /// what gets drawn is a height that eventually disagrees.
    static func rowCount(isExpanded: Bool) -> Int {
        1 + (isExpanded ? CameraProperty.allCases.count : 0)
    }

    /// Pan in the position colour and zoom in the scale colour — what each
    /// one does to the picture.
    static func colour(for property: CameraProperty) -> Color {
        switch property {
        case .x, .y, .z: Theme.KeyframePalette.position
        case .zoom, .focal: Theme.KeyframePalette.scale
        case .rotation: Theme.KeyframePalette.rotation
        case .fog: Theme.KeyframePalette.opacity
        }
    }

    var body: some View {
        let camera = shell.camera
        // The **observed** playhead. The arrows work out the previous and next
        // key from it, and the diamond fills when it sits on one: read from
        // the unobserved copy, the rows never heard that the playhead moved,
        // so after the first jump "next" was worked out from where the
        // playhead used to be and pointed at the key it had just landed on.
        // The arrows looked dead. A clip's keyframe rows already read this
        // copy, for exactly this reason.
        let now = shell.observedPlayheadTime

        VStack(spacing: Theme.Spacing.hair) {
            KeyframeGroupHeader(
                title: "Camera",
                systemImage: "video",
                animatedCount: CameraProperty.allCases.filter { !camera[$0].isEmpty }.count,
                isExpanded: shell.isCameraGroupExpanded,
                toggle: { shell.isCameraGroupExpanded.toggle() },
            )

            if shell.isCameraGroupExpanded {
                ForEach(CameraProperty.allCases, id: \.self) { property in
                    KeyframeRow(
                        title: property.title,
                        track: camera[property],
                        // Song time: the "clip" starts at zero and lasts the song.
                        nodeStart: 0,
                        scale: scale,
                        headerWidth: headerWidth,
                        localTime: now,
                        playheadNow: { shell.playheadTime },
                        isPlaying: isPlaying,
                        addKeyframe: { time in
                            shell.setCameraKeyframe(camera.value(property, at: time), for: property, at: time)
                        },
                        moveKeyframe: { shell.moveCameraKeyframe($0, in: property, to: $1) },
                        removeKeyframe: { shell.removeCameraKeyframe($0, from: property) },
                        setEasing: { shell.setCameraKeyframeEasing($1, for: $0, in: property) },
                        setEnabled: {
                            shell.setCameraAnimationEnabled($0, for: property, keeping: shell.playheadTime)
                        },
                        clear: { shell.clearCameraKeyframes(for: property, keeping: shell.playheadTime) },
                        selectedKeyID: shell.selectedCameraKeyframe?.property == property
                            ? shell.selectedCameraKeyframe?.keyframeID : nil,
                        selectKey: { shell.selectedCameraKeyframe = .init(property: property, keyframeID: $0) },
                        goToKey: { key in
                            seek(key.time)
                            shell.selectedCameraKeyframe = .init(property: property, keyframeID: key.id)
                        },
                        value: camera.value(property, at: now),
                        setValue: { value in
                            // With animation on, typing plants a key at the
                            // playhead; off, it moves where the camera rests — the
                            // same distinction every other field here makes.
                            if camera[property].isActive {
                                shell.setCameraKeyframe(value, for: property, at: shell.playheadTime)
                            } else {
                                shell.setCameraValue(value, for: property)
                            }
                        },
                        unit: property.unit,
                        step: property.step,
                        range: property.range,
                        keyColour: Self.colour(for: property),
                    )
                }
            }
        }
    }
}
