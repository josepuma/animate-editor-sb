import DesignSystem
import StoryboardCore
import SwiftUI

/// Where a script's code is written.
///
/// In the side panel rather than as a timeline mode, so the code and the canvas
/// are visible at once — which is how a script is actually tuned: write, look,
/// adjust. A full-width mode gives more room for code and covers the timeline,
/// so you lose track of where you are in the song while writing.
struct ScriptEditorPanel: View {
    let shell: EditorShellModel
    let nodeID: EffectNode.ID

    /// What is shown while typing, committed on ⌘↩ or on leaving the editor.
    ///
    /// The same draft-then-commit as every other field in this app, and here it
    /// is not a nicety: a keystroke that wrote through would recompile the
    /// script and re-evaluate the document per letter, and half-typed code
    /// fails to parse — so the diagnostics panel would flash errors about code
    /// nobody has finished writing.
    @State private var draft: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
            header

            FieldWell(isFocused: isFocused) {
                TextEditor(text: Binding(
                    get: { draft ?? source },
                    set: { draft = $0 },
                ))
                .font(Theme.Typography.readout)
                .foregroundStyle(Theme.Palette.primary)
                .scrollContentBackground(.hidden)
                .focused($isFocused)
                .frame(minHeight: Theme.Size.scriptEditor)
                // ⌘↩ rather than ↩, which has to insert a newline: this is
                // code, and a field where Return commits cannot hold a second
                // line.
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    commit()
                    return .handled
                }
                .onExitCommand {
                    draft = nil
                    isFocused = false
                }
                .onChange(of: isFocused) { _, focused in
                    // Committed on losing focus as well, because clicking away
                    // is how a form gets filled in — a value that demands a
                    // keystroke to keep is a value that gets lost.
                    if !focused { commit() }
                }
            }

            if let draft, draft != source {
                Text("⌘↩ to run")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.tertiary)
            }
        }
        // Keyed to the clip, so selecting another script does not leave the
        // previous one's draft sitting in the editor.
        .onChange(of: nodeID) { _, _ in draft = nil }
    }

    /// The section heading, with the control count as its accessory.
    ///
    /// Through `SectionHeader`'s own accessory slot rather than an `HStack`
    /// beside it: the primitive already holds that recipe, and a second copy is
    /// how two headings in one window end up a step apart.
    private var header: some View {
        SectionHeader("Script") {
            if let count = shell.effects[nodeID]?.scriptParameters.count, count > 0 {
                Text("\(count) control\(count == 1 ? "" : "s")")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.tertiary)
            }
        }
    }

    private var source: String {
        shell.effects[nodeID]?.scriptSource ?? ""
    }

    private func commit() {
        defer {
            draft = nil
            isFocused = false
        }
        guard let edited = draft else { return }
        shell.setScriptSource(edited, on: nodeID)
    }
}
