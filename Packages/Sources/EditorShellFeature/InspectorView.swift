import DesignSystem
import StoryboardCore
import SwiftUI

/// The right panel: properties of whatever is selected.
///
/// Sprite editing is not implemented, so the fields shown here are read-only
/// facts about the selected track. They are laid out the way the editable
/// version will be.
struct InspectorView: View {
    /// Fixed width, so the shell can size the workspace around the canvas.
    static let width: CGFloat = 240

    let shell: EditorShellModel
    let playback: PlaybackSnapshot

    /// The bits of playback state the inspector needs, passed in rather than
    /// depended on: this panel belongs to the shell, not to playback.
    struct PlaybackSnapshot {
        let currentTime: Double
        let duration: Double
        let drawnCount: Int
        let spriteCount: Int
        let bpm: Double?
    }

    var body: some View {
        ScrollView {
            content
        }
        .scrollBounceBehavior(.basedOnSize)
        .fixedSize(horizontal: false, vertical: true)
        .padding(Theme.Spacing.compact)
        .frame(width: Self.width)
        .surface(.panel)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.regular) {
            if let track = shell.selectedTrack {
                trackSection(track)
            }

            playbackSection

            SectionHeader("Sprite")
            ComingSoon(
                title: "No selection",
                detail: "Selecting a sprite on the canvas will show its commands here.",
                systemImage: "cursorarrow.rays",
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ─── Sections ────────────────────────────────────────────────────────────

    private func trackSection(_ track: ScriptTrack) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
            SectionHeader("Track") {
                Circle()
                    .fill(track.layer.tint)
                    .frame(width: Theme.Spacing.snug, height: Theme.Spacing.snug)
            }

            PropertyRow("Name") {
                PropertyValue(track.name)
            }
            PropertyRow("Layer") {
                PropertyValue(track.layer.rawValue)
            }
            PropertyRow("Sprites") {
                PropertyValue("\(track.spriteCount)", monospaced: true)
            }
            PropertyRow("Spans") {
                PropertyValue("\(track.activeRanges.count)", monospaced: true)
            }
        }
    }

    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
            SectionHeader("Playback")

            PropertyRow("Time") {
                PropertyValue(Self.timecode(playback.currentTime), monospaced: true)
            }
            PropertyRow("Length") {
                PropertyValue(Self.timecode(playback.duration), monospaced: true)
            }
            if let bpm = playback.bpm, bpm > 0 {
                PropertyRow("Tempo") {
                    PropertyValue(String(format: "%.0f BPM", bpm), monospaced: true)
                }
            }
            PropertyRow("On screen") {
                PropertyValue(
                    "\(playback.drawnCount) of \(playback.spriteCount)",
                    monospaced: true,
                )
            }
        }
    }

    private static func timecode(_ milliseconds: Double) -> String {
        let totalSeconds = Int(milliseconds / 1000)
        let hundredths = Int(milliseconds.truncatingRemainder(dividingBy: 1000) / 10)
        return String(format: "%d:%02d.%02d", totalSeconds / 60, totalSeconds % 60, hundredths)
    }
}
