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

            // An exact height, and clipped to it.
            //
            // `TextEditor` sizes itself to its content and draws outside
            // whatever frame it is handed: given `minHeight`, twenty lines of
            // code rendered straight over the search field, the filter chips
            // and the preset list below — the panel unreadable. It is the same
            // trap as the `ScrollView` that never receives the height it is
            // given, from the other side: a minimum on something that grows is
            // not a bound at all.
            //
            // 996 tests were green while the panel looked like that. A test
            // cannot see a layout, which is the whole reason to open the app.
            TextEditor(text: Binding(
                get: { draft ?? source },
                set: { draft = $0 },
            ))
            .font(Theme.Typography.readout)
            .foregroundStyle(Theme.Palette.primary)
            .scrollContentBackground(.hidden)
            .focused($isFocused)
            // Fills the panel rather than taking a fixed height: it has the
            // whole column now, and code is the one thing here worth every
            // pixel available. Still an explicit frame, not a minimum — the
            // point of the bound is that the editor cannot exceed it.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(Theme.Spacing.tight)
            .background(Theme.Fill.well, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.control)
                    .strokeBorder(
                        isFocused ? Theme.Border.raised : Theme.Border.field,
                        lineWidth: Theme.Size.hairline,
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
            // ⌘↩ rather than ↩, which has to insert a newline: this is code,
            // and a field where Return commits cannot hold a second line.
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
                // Committed on losing focus as well, because clicking away is
                // how a form gets filled in — a value that demands a keystroke
                // to keep is a value that gets lost.
                if !focused { commit() }
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
