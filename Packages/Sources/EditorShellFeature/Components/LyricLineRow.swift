import DesignSystem
import SwiftUI

/// One transcribed line: when, how sure, how long, and what was heard.
package struct LyricLineRow: View {
    private let text: String
    /// Where the line starts, in milliseconds.
    private let start: Double
    /// How long it runs, in milliseconds.
    private let duration: Double
    /// Whether it ran long enough to want splitting by hand.
    private let isOverlong: Bool
    /// Whether the transcription was unsure of it. Decided by the caller, which
    /// owns the threshold.
    private let needsReview: Bool
    private let isPlaced: Bool
    private let seek: () -> Void
    private let place: () -> Void

    @State private var isHovered = false

    package init(
        text: String,
        start: Double,
        duration: Double,
        isOverlong: Bool,
        needsReview: Bool,
        isPlaced: Bool,
        seek: @escaping () -> Void,
        place: @escaping () -> Void,
    ) {
        self.text = text
        self.start = start
        self.duration = duration
        self.isOverlong = isOverlong
        self.needsReview = needsReview
        self.isPlaced = isPlaced
        self.seek = seek
        self.place = place
    }

    package var body: some View {
        HStack(spacing: Theme.Spacing.snug) {
            // Placed already, so a second pass over the list shows what is
            // done — which is what makes placing one at a time workable.
            ZStack {
                Circle()
                    .fill(isPlaced ? Theme.Palette.accent : Theme.Tone.well)
                Image(systemName: isPlaced ? "checkmark" : "music.note")
                    .font(.system(size: (Theme.Size.controlTiny * 0.42).rounded(), weight: .bold))
                    .foregroundStyle(isPlaced ? Theme.Palette.onAccent : Theme.Palette.tertiary)
            }
            .frame(width: Theme.Size.controlTiny, height: Theme.Size.controlTiny)

            Button(action: seek) {
                HStack(spacing: Theme.Spacing.snug) {
                    // In a pill, so the column of times reads as a column of
                    // times rather than as the first word of every line.
                    Text(timestamp)
                        .font(Theme.Typography.readout)
                        .foregroundStyle(Theme.Palette.secondary)
                        .padding(.horizontal, Theme.Spacing.snug)
                        .padding(.vertical, Theme.Spacing.hair)
                        .background(Capsule(style: .continuous).fill(Theme.Tone.well))

                    if needsReview {
                        Circle()
                            .fill(Theme.Palette.warning)
                            .frame(width: Theme.Size.indicator * 2, height: Theme.Size.indicator * 2)
                            .help("The transcription was unsure of this line")
                    }

                    Text(text)
                        .font(Theme.Typography.label)
                        .foregroundStyle(textColour)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    // Said on the row rather than only in the header: this is
                    // the line to split by hand, and it has to be findable.
                    if isOverlong {
                        Text("\(Int(duration / 100) / 10)s")
                            .font(Theme.Typography.readout)
                            .foregroundStyle(Theme.Palette.warning)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Button(action: place) {
                AddBadge(isHighlighted: isHovered && !isPlaced)
            }
            .buttonStyle(.plain)
            .help("Place this line with the movement above")
        }
        .padding(.horizontal, Theme.Spacing.snug)
        .frame(height: Theme.Size.control)
        .rowSurface(isHovered: isHovered)
        .onHover { isHovered = $0 }
        .animation(Theme.Motion.quick, value: isHovered)
    }

    /// Amber for a line to check, which is what this project already uses to
    /// mean "look at this".
    private var textColour: Color {
        if needsReview { return Theme.Palette.warning }
        return isPlaced ? Theme.Palette.secondary : Theme.Palette.primary
    }

    /// `m:ss.mmm`, the shape the transport reads.
    private var timestamp: String {
        let total = Int(start.rounded())
        return String(format: "%d:%02d.%03d", total / 60_000, (total / 1000) % 60, total % 1000)
    }
}
