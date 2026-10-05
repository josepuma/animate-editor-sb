import DesignSystem
import SwiftUI

/// A script file, as a card in the scripts panel.
///
/// A script has no picture of its own until it runs, so the card shows **the
/// code**: its first lines, cut off by the card's edge. That is what tells two
/// scripts apart at a glance — a file name is something you read, the shape of
/// the code is something you recognise.
package struct ScriptCard: View {
    /// What happened the last time the script ran.
    package enum Status: Equatable {
        /// Ran, drawing this many sprites.
        case ready(sprites: Int)
        /// Threw, with the engine's message.
        case failed(String)
        /// The file the clip names is not in the beatmap folder.
        case missing
    }

    private let fileName: String
    private let snippet: [String]
    private let status: Status
    private let clipCount: Int
    private let tint: Color
    private let isSelected: Bool
    private let action: () -> Void

    @State private var isHovered = false

    /// - Parameters:
    ///   - snippet: the first few lines of the file, shown faded under the
    ///     header. More than five are clipped.
    ///   - clipCount: how many clips name this file. Shown because editing a
    ///     shared file reloads every one of them, and an edit with more reach
    ///     than expected is the one nobody notices until the second clip looks
    ///     wrong.
    package init(
        fileName: String,
        snippet: [String],
        status: Status,
        clipCount: Int,
        tint: Color,
        isSelected: Bool = false,
        action: @escaping () -> Void = {},
    ) {
        self.fileName = fileName
        self.snippet = snippet
        self.status = status
        self.clipCount = clipCount
        self.tint = tint
        self.isSelected = isSelected
        self.action = action
    }

    package var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)

        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                header
                footer
            }
            .background(Theme.Tone.raised)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(
                    isSelected ? Theme.Palette.accent
                        : (isHovered ? Theme.Border.cardHovered : Theme.Border.card),
                    lineWidth: isSelected ? Theme.Size.ring * 1.5 : Theme.Size.hairline,
                )
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(Theme.Motion.quick, value: isHovered)
    }

    private var header: some View {
        ZStack(alignment: .topLeading) {
            Theme.Tone.well

            VStack(alignment: .leading, spacing: Theme.Spacing.hair) {
                ForEach(Array(snippet.prefix(5).enumerated()), id: \.offset) { _, line in
                    Text(line.isEmpty ? " " : line)
                        .font(Theme.Typography.code)
                        .foregroundStyle(Theme.Palette.secondary)
                        .lineLimit(1)
                }
            }
            .padding(Theme.Spacing.compact)
        }
        .frame(height: Theme.Size.cardArtwork)
        .clipped()
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.snug) {
            // The status as a dot, its detail in the tooltip. A line of
            // "342 sprites" or an engine message on every card was text nobody
            // came to the scripts panel to read; the colour alone says whether
            // something needs a look, and the message is one hover away.
            Circle()
                .fill(statusTint)
                .frame(width: Theme.Spacing.snug, height: Theme.Spacing.snug)
                .help(statusText)

            Text(fileName)
                .font(Theme.Typography.code)
                .foregroundStyle(Theme.Palette.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            if clipCount > 1 {
                Text("×\(clipCount)")
                    .font(Theme.Typography.readout)
                    .foregroundStyle(Theme.Palette.tertiary)
                    .help("Shared by \(clipCount) clips — editing the file reloads all of them")
            }
        }
        .padding(Theme.Spacing.compact)
    }

    private var statusTint: Color {
        switch status {
        case .ready: Theme.Palette.accent
        case .failed: Theme.Palette.danger
        case .missing: Theme.Palette.warning
        }
    }

    private var statusText: String {
        switch status {
        case let .ready(sprites): "\(sprites) sprites"
        case let .failed(message): message
        case .missing: "File not found"
        }
    }
}
