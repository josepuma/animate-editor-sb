import DesignSystem
import StoryboardCore
import SwiftUI

/// What a selected script clip shows in the side panel.
///
/// Not an editor. The code is written in whatever editor the author already
/// uses — one that has their keybindings, their extensions and a real language
/// service — and this panel is the door to it plus the things the file cannot
/// tell you: which file a clip reads, how many clips share it, and what the
/// last run had to say.
///
/// The in-app editor it replaces was a compromise all the way down: regex
/// highlighting, a completion panel found by searching the app's windows for
/// one of the right shape, a `TextEditor` that drew outside its own frame, and
/// a theme that had to be forced because the default was a white page in a
/// dark-only app. It also cost the package its only external dependency.
struct ScriptPanel: View {
    let shell: EditorShellModel
    let nodeID: EffectNode.ID

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
            SectionHeader(shell.effects[nodeID]?.name ?? "Script")

            if let file = shell.effects[nodeID]?.scriptFile {
                fileRow(file)
                openButton
                if sharingCount > 1 { sharingNote }
            } else {
                // A script clip with no file is a clip whose source has not
                // been written out yet, or whose reference did not survive
                // decoding. Said plainly rather than shown as an empty editor.
                ComingSoon(
                    title: "No script file",
                    detail: "This clip does not name a file yet.",
                    systemImage: "doc.badge.gearshape",
                )
            }

            diagnostics

            Spacer(minLength: 0)
        }
    }

    /// Which file this clip reads.
    private func fileRow(_ file: ScriptFile) -> some View {
        PropertyRow("File") {
            Readout(file.fileName, systemImage: "doc.text")
        }
    }

    /// Full width, because it is the only action on the panel.
    ///
    /// A capsule sized to its label reads as one option among several; this
    /// panel has exactly one thing to do, and a button that fills the column
    /// says so — and lines up with the field above it, which is where the eye
    /// already is.
    private var openButton: some View {
        Button("Open in Editor", systemImage: "arrow.up.forward.app") {
            shell.openScriptExternally(nodeID)
        }
        .buttonStyle(.themed(.primary, size: .regular))
        .frame(maxWidth: .infinity)
        .disabled(!shell.canOpenScript(nodeID))
    }

    /// How many clips read this same file.
    ///
    /// Worth saying, because editing the file changes all of them — and a
    /// change with more reach than expected is the kind nobody spots until the
    /// second clip looks wrong.
    private var sharingCount: Int {
        guard let file = shell.effects[nodeID]?.scriptFile else { return 0 }
        return shell.effects.nodes.count { $0.scriptFile == file }
    }

    private var sharingNote: some View {
        Text("Shared by \(sharingCount) clips — editing the file changes all of them.")
            .font(Theme.Typography.micro)
            .foregroundStyle(Theme.Palette.secondary)
    }

    /// What the last run had to say.
    ///
    /// The one thing the external editor genuinely cannot show: it can flag a
    /// type error, but only the app knows the script threw at sprite 900 or hit
    /// the ceiling.
    @ViewBuilder
    private var diagnostics: some View {
        if let report = shell.scriptReport?(nodeID), !report.isEmpty {
            SectionHeader("Last Run")

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Theme.Spacing.hair) {
                    // Errors first, whatever order they arrived in: a failure
                    // buried under twenty log lines is a failure nobody reads.
                    ForEach(Array(report.diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                        OutputLine(text: describe(diagnostic), tone: .error)
                    }

                    ForEach(Array(report.logs.enumerated()), id: \.offset) { _, line in
                        OutputLine(text: line.message, tone: tone(of: line.level))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: Theme.Size.scriptOutput)
        }
    }

    private func tone(of level: ScriptRuntime.LogLine.Level) -> OutputLine.Tone {
        switch level {
        case .log: .plain
        case .warn: .warning
        case .error: .error
        }
    }

    /// A diagnostic in the words somebody can act on.
    private func describe(_ diagnostic: ScriptRuntime.Diagnostic) -> String {
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
