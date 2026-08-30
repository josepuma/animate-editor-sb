import DesignSystem
import StoryboardCore
import SwiftUI

/// The left panel: whatever the rail has selected.
struct SidePanelView: View {
    /// Fixed width, so the shell can size the workspace around the canvas.
    static let width: CGFloat = 240

    @Bindable var shell: EditorShellModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
            SectionHeader(shell.sidePanel.title)

            switch shell.sidePanel {
            case .assets: assets
            case .scripts: scripts
            case .layers: layers
            case .timing: timing
            }
        }
        .padding(Theme.Spacing.compact)
        .frame(width: Self.width, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .surface(.panel)
    }

    // ─── Assets ──────────────────────────────────────────────────────────────

    private var assets: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
            ChipPicker(
                items: AssetItem.Kind.allCases,
                selection: $shell.assetFilter,
                label: \.title,
            )

            if shell.visibleAssets.isEmpty {
                ComingSoon(
                    title: "No assets",
                    detail: "Images referenced by the storyboard appear here.",
                    systemImage: "photo.on.rectangle.angled",
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.tight) {
                        ForEach(shell.visibleAssets) { asset in
                            AssetRow(asset: asset)
                        }
                    }
                }
            }
        }
    }

    // ─── Scripts ─────────────────────────────────────────────────────────────

    private var scripts: some View {
        ComingSoon(
            title: "Scripting",
            detail: "Write TypeScript to generate sprites. Not implemented yet.",
            systemImage: "curlybraces",
        )
    }

    // ─── Layers ──────────────────────────────────────────────────────────────

    private var layers: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.tight) {
                ForEach(shell.tracks) { track in
                    TrackRow(
                        track: track,
                        isSelected: track.id == shell.selectedTrackID,
                        select: { shell.selectedTrackID = track.id },
                        toggleVisibility: { shell.toggleVisibility(of: track.id) },
                        toggleLock: { shell.toggleLock(of: track.id) },
                    )
                }
            }
        }
    }

    // ─── Timing ──────────────────────────────────────────────────────────────

    private var timing: some View {
        ComingSoon(
            title: "Timing points",
            detail: "Edit BPM and offset. Not implemented yet.",
            systemImage: "metronome",
        )
    }
}

// ─── Rows ────────────────────────────────────────────────────────────────────

private struct AssetRow: View {
    let asset: AssetItem
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.snug) {
            Image(systemName: asset.isMissing ? "exclamationmark.triangle" : "photo")
                .font(Theme.Typography.micro)
                .foregroundStyle(
                    asset.isMissing ? Theme.Palette.warning : Theme.Palette.tertiary,
                )
                .frame(width: Theme.Size.controlTiny)

            VStack(alignment: .leading, spacing: 0) {
                Text(asset.name)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if asset.isMissing {
                    Text("Missing")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.warning)
                }
            }

            Spacer(minLength: Theme.Spacing.tight)

            Text("\(asset.useCount)")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.tertiary)
                .help("Used by \(asset.useCount) sprites")
        }
        .padding(.horizontal, Theme.Spacing.snug)
        .padding(.vertical, Theme.Spacing.tight)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .fill(isHovered ? Theme.Fill.hover : .clear)
        }
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .help(asset.path)
    }
}

private struct TrackRow: View {
    let track: ScriptTrack
    let isSelected: Bool
    let select: () -> Void
    let toggleVisibility: () -> Void
    let toggleLock: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.snug) {
            Circle()
                .fill(track.layer.tint)
                .frame(width: Theme.Spacing.snug, height: Theme.Spacing.snug)

            VStack(alignment: .leading, spacing: 0) {
                Text(track.name)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(
                        track.isVisible ? Theme.Palette.secondary : Theme.Palette.tertiary,
                    )
                    .lineLimit(1)

                Text("\(track.spriteCount) sprites")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.tertiary)
            }

            Spacer(minLength: Theme.Spacing.tight)

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
        .padding(.vertical, Theme.Spacing.tight)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .fill(fill)
        }
        .contentShape(.rect)
        .onTapGesture(perform: select)
        .onHover { isHovered = $0 }
        .animation(Theme.Motion.quick, value: isSelected)
        .animation(Theme.Motion.quick, value: isHovered)
    }

    /// Selection wins over hover, so pointing at the selected row does not dim
    /// it back down.
    private var fill: Color {
        if isSelected { return Theme.Fill.selected }
        return isHovered ? Theme.Fill.hover : .clear
    }
}
