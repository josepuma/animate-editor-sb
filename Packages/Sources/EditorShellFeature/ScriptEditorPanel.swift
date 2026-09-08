import DesignSystem
import StoryboardCore
import SwiftUI

/// Where a script's code is written.
///
/// In the side panel rather than as a timeline mode, so the code and the canvas
/// are visible at once — which is how a script is actually tuned: write, look,
/// adjust. A full-width mode gives more room for code and covers the timeline,
/// so you lose track of where you are in the song while writing.
///
/// The editor itself is **injected**, not built here. A real code editor means
/// a syntax highlighter, and this target is arrangement — it receives the
/// editor exactly as the shell receives the canvas, so the shell stays
/// buildable and testable with no editor dependency in it.
struct ScriptEditorPanel: View {
    let shell: EditorShellModel
    let nodeID: EffectNode.ID

    /// What is shown while typing, committed on ⌘S or on leaving the editor.
    ///
    /// The same draft-then-commit as every other field here, and not a nicety:
    /// a keystroke that wrote through would recompile the script and
    /// re-evaluate the document per letter, and half-typed code fails to parse
    /// — so the panel would flash errors about code nobody has finished
    /// writing.
    @State private var draft: String?

    @Environment(\.scriptEditor) private var scriptEditor

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
            header

            if let build = scriptEditor {
                build(
                    Binding(
                        get: { draft ?? source },
                        set: { draft = $0 },
                    ),
                    commit,
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.control)
                        .strokeBorder(Theme.Border.field, lineWidth: Theme.Size.hairline)
                }

                footer
            } else {
                // Said plainly rather than falling back to a text box. A plain
                // field where an editor belongs is exactly what this replaced,
                // and offering it again would hide a broken build behind
                // something that looks like it works.
                ComingSoon(
                    title: "No editor",
                    detail: "The code editor was not provided by the host.",
                    systemImage: "exclamationmark.triangle",
                )
            }
        }
        // Keyed to the clip, so selecting another script does not leave the
        // previous one's draft sitting in the editor.
        .onChange(of: nodeID) { _, _ in draft = nil }
        // ⌘S belongs to the editor while the editor is here.
        //
        // Registered rather than bound to a second button: two buttons with
        // the same shortcut means one of them wins, and the one that won was
        // the shell's — which declined because a field had focus, so nothing
        // happened at all.
        //
        // Re-registered on every draft change, not once in `onAppear`. A
        // closure over `commit` captures the `self` it was made with, and
        // `draft` is `@State` — so the version registered when the panel
        // appeared reads `nil` forever and ⌘S would have saved nothing. Same
        // bug wearing a different hat.
        .onChange(of: draft, initial: true) { _, _ in
            shell.runScriptHandler = commit
        }
        .onDisappear { shell.runScriptHandler = nil }
    }

    private var header: some View {
        SectionHeader(shell.effects[nodeID]?.name ?? "Script") {
            HStack(spacing: Theme.Spacing.tight) {
                if let count = shell.effects[nodeID]?.scriptParameters.count, count > 0 {
                    Text("\(count) control\(count == 1 ? "" : "s")")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.tertiary)
                }

                // The API reference, opened in its own window.
                //
                // A button rather than a menu item, because the question it
                // answers — "what can I call here" — arrives while somebody is
                // typing, and a menu is not where they are looking. In its own
                // window so the code stays visible beside it: a reference that
                // covers the thing being written is a reference nobody keeps
                // open.
                IconButton(
                    systemImage: "questionmark.circle",
                    size: Theme.Size.controlTiny,
                    help: "Scripting reference",
                ) {
                    shell.openScriptReference?()
                }

                // A way back to the library.
                //
                // The editor takes the whole panel, so without this the only
                // route to placing another effect is deselecting the clip on
                // the canvas — a control that hides another control with no
                // door out is a dead end.
                IconButton(
                    systemImage: "xmark",
                    size: Theme.Size.controlTiny,
                    help: "Back to the library",
                ) {
                    shell.selectedNodeID = nil
                }
            }
        }
    }

    /// The ⌘S hint, and whatever the last run had to say.
    ///
    /// On one row rather than a panel of its own, and scrollable, so output
    /// costs the code no height. A console that takes a third of the panel is
    /// a console somebody closes, and then the next error goes unseen for the
    /// same reason it was unseen before.
    @ViewBuilder
    private var footer: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.compact) {
            Text("⌘S to run")
                .font(Theme.Typography.micro)
                .foregroundStyle(
                    draft != nil && draft != source
                        ? Theme.Palette.warning
                        : Theme.Palette.tertiary,
                )
                .fixedSize()

            if let report = shell.scriptReport?(nodeID), !report.isEmpty {
                Divider().frame(height: Theme.Size.dividerHeight)

                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.hair) {
                        // Errors first, whatever order they arrived in: a
                        // failure buried under twenty log lines is a failure
                        // nobody reads.
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
        case .noSource: "Nothing to run yet."
        case let .compileFailed(message): message
        case let .runtimeFailed(message): message
        case let .spritesTruncated(produced, kept):
            "\(produced) sprites asked for; \(kept) kept — a storyboard cannot carry more."
        case let .commandsTruncated(produced, kept):
            "\(produced) commands asked for; \(kept) kept — a storyboard cannot carry more."
        }
    }

    private var source: String {
        shell.effects[nodeID]?.scriptSource ?? ""
    }

    /// Puts the draft on the node, which is what makes the script run.
    ///
    /// Saving and running are one action deliberately. The script lives in the
    /// document, so committing it *is* changing the project — and a script that
    /// needed saving and then running separately would be two keystrokes for
    /// one intention, with a window in between where the file and the canvas
    /// disagree.
    private func commit() {
        guard let edited = draft else { return }
        shell.setScriptSource(edited, on: nodeID)
        shell.saveProject()
        draft = nil
    }
}
