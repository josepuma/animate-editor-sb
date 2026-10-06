import DesignSystem
import StoryboardCore
import SwiftUI

/// What a script clip's last run had to say: its errors, then its logs.
///
/// In the inspector, under its own tab that only script clips have. The card
/// in the Scripts tab carries a dot and a tooltip; this is where the whole
/// message and every `console.log` line are read — the thing an author looks
/// at while iterating on code in the editor beside the app.
package struct ScriptOutputView: View {
    private let report: ScriptRuntime.Report?
    private let isRunning: Bool

    /// - Parameter isRunning: whether the clip is being evaluated now. Shown so
    ///   a save in the code editor is visibly picked up — output that stays
    ///   unchanged for a moment after saving reads as the app ignoring it.
    package init(report: ScriptRuntime.Report?, isRunning: Bool) {
        self.report = report
        self.isRunning = isRunning
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
            if isRunning {
                HStack(spacing: Theme.Spacing.snug) {
                    ProgressView().controlSize(.small)
                    Text("Running…")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.tertiary)
                }
            }

            if let report, !report.diagnostics.isEmpty || !report.logs.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.hair) {
                    // Errors first, whatever order they arrived in: a failure
                    // buried under twenty log lines is a failure nobody reads.
                    ForEach(Array(report.diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                        OutputLine(text: Self.describe(diagnostic), tone: .error)
                    }

                    ForEach(Array(report.logs.enumerated()), id: \.offset) { _, line in
                        OutputLine(text: line.message, tone: Self.tone(of: line.level))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if !isRunning {
                // Said rather than left blank: an empty tab reads as broken.
                ComingSoon(
                    title: "No output",
                    detail: "Errors and console.log lines from this clip's last run show here.",
                    systemImage: "text.alignleft",
                )
            }
        }
    }

    private static func tone(of level: ScriptRuntime.LogLine.Level) -> OutputLine.Tone {
        switch level {
        case .log: .plain
        case .warn: .warning
        case .error: .error
        }
    }

    /// A diagnostic in the words somebody can act on.
    private static func describe(_ diagnostic: ScriptRuntime.Diagnostic) -> String {
        switch diagnostic {
        case .noRuntime: "No scripting runtime — this is a broken build, not your script."
        case .noSource: "This clip's file is missing or empty."
        case let .compileFailed(message): message
        case let .runtimeFailed(message): message
        case let .spritesTruncated(produced, kept):
            "\(produced) sprites asked for; \(kept) kept — a storyboard cannot carry more."
        case let .commandsTruncated(produced, kept):
            "\(produced) commands asked for; \(kept) kept — a storyboard cannot carry more."
        }
    }
}
