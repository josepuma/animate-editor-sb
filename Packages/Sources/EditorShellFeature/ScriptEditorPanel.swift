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

    /// Says whether there is anything to run, and how.
    ///
    /// Only while the draft differs: a hint that is always on screen is chrome
    /// nobody reads, and the one moment it matters is when there are unsaved
    /// changes sitting in front of you.
    @ViewBuilder
    private var footer: some View {
        if let draft, draft != source {
            Text("⌘S to run")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.warning)
        } else {
            Text("⌘S to run")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.tertiary)
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
