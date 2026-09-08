import CodeEditorView
import DesignSystem
import LanguageSupport
import StoryboardCore
import SwiftUI

/// A code editor for a storyboard script.
///
/// The only view in the project that touches the editor dependency, which is
/// why it lives in its own target: the shell receives it by `@ViewBuilder` the
/// same way it receives the canvas, so nothing else has to build against a
/// syntax highlighter.
///
/// It replaced a plain `TextEditor`, which was not an editor at all — no
/// highlighting, no line numbers, no bracket matching. This has all three,
/// plus inline markers for the diagnostics a script produces, shown on the
/// line that caused them rather than in a list underneath.
public struct ScriptCodeEditor: View {
    /// The source, as edited. Committed by the caller, not written through.
    @Binding private var text: String

    /// What to do when the author asks for the script to run.
    private let run: () -> Void

    /// Problems to mark, by line.
    private let diagnostics: [ScriptDiagnosticMark]

    /// Answers the editor's questions about the API a script can call.
    ///
    /// Held in `@State` so it survives a rebuild: the editor opens the document
    /// against it once, and a service replaced mid-session would be asked about
    /// a document it was never told about.
    @State private var language = ScriptLanguageService()

    /// Asks the editor to show completions.
    ///
    /// Captured because nothing in the library triggers them on a character.
    /// `LanguageService.completionTriggerCharacters` is declared in the
    /// protocol and **read by nobody** — verified with a search across the
    /// package: the only mention is its own declaration. So a typed `.` reached
    /// no one, and the popup only ever appeared for the ⌥⎋ shortcut. This
    /// closure is the same action that shortcut runs.
    @State private var showCompletions: (() -> Void)?

    @State private var position = CodeEditor.Position()
    @State private var messages: Set<TextLocated<Message>> = []
    @FocusState private var isFocused: Bool

    public init(
        text: Binding<String>,
        diagnostics: [ScriptDiagnosticMark] = [],
        run: @escaping () -> Void,
    ) {
        _text = text
        self.diagnostics = diagnostics
        self.run = run
    }

    public var body: some View {
        CodeEditor(
            text: $text,
            position: $position,
            messages: $messages,
            language: .javaScript(language),
                        // No wrapping, and no minimap.
            //
            // Wrapping is what made the narrow panel unusable — `.move(Ease.
            // outQuad, born, born + 900,` broken across three lines, with the
            // indentation of the continuation meaning nothing. Code is written
            // in lines and read by their shape; scrolling sideways for the
            // occasional long one costs less than losing that shape on every
            // line. The minimap is a stripe nobody can read that spends width
            // the code needs.
            layout: CodeEditor.LayoutConfiguration(showMinimap: false, wrapText: false),
            setActions: { actions in
                // Assigned to state from a callback the library invokes during
                // layout, so it is deferred: writing state while a view is
                // being built is a change SwiftUI has already passed.
                let show = actions.completions
                Task { @MainActor in showCompletions = show }
            },
        )
        // Set explicitly, because the environment's default is
        // `Theme.defaultLight` — a white page in a dark-only app. I left it at
        // the default and wrote in a comment that it "already resolves to
        // dark"; it does not, and the screenshot showed it.
        .environment(\.codeEditorTheme, .animateEditorDark)
        .focused($isFocused)
        // ⌘S runs the script.
        //
        // Claimed here rather than at window level, and it has to be: the
        // window already binds ⌘S to saving the project, with no guard for a
        // field having focus — so inside the editor it saved the document
        // without committing the code that was just typed. Caught here first,
        // the two agree: the source lands on the node, and saving the project
        // is what putting it there means, since the script lives in the
        // document.
        //
        // `.onKeyPress` rather than a hidden `Button` with a shortcut: a
        // shortcut is window-wide however it is declared, so it would fire
        // while the canvas has focus too.
        .onKeyPress(.init("s"), phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            run()
            return .handled
        }
        // A dot opens the completion list.
        //
        // Reported as broken and it was: typing `.` under `sprite(Image.soft)`
        // offered nothing. The service answered correctly the whole time — five
        // items, measured — because the editor never asked. Nothing in the
        // library consumes `completionTriggerCharacters`, so this does it.
        //
        // `.ignored` so the dot is still typed: handling it would open the list
        // for a character that never arrived, and the completion would replace
        // text that does not include the dot it was triggered by.
        //
        // Deferred by one turn of the loop, because the list is computed from
        // the document and at this moment the dot is not in it yet.
        .onKeyPress(.init("."), phases: .down) { _ in
            Task { @MainActor in
                await Task.yield()
                showCompletions?()
            }
            return .ignored
        }
        .onChange(of: diagnostics, initial: true) { _, marks in
            messages = Set(marks.map(\.located))
        }
        // A minimap on a panel this narrow is a stripe nobody can read that
        // costs a fifth of the width the code needs. Off, not configurable —
        // one setting for a thing nobody would turn on is a setting.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One problem to mark in the editor, at a line.
///
/// A value type of its own rather than the editor library's `Message`, so the
/// shell can describe a problem without importing the editor — which is the
/// whole reason this target exists.
public struct ScriptDiagnosticMark: Equatable, Sendable {
    public enum Severity: Sendable, Equatable {
        case error
        case warning
    }

    public let line: Int
    public let severity: Severity
    public let summary: String

    public init(line: Int, severity: Severity, summary: String) {
        self.line = line
        self.severity = severity
        self.summary = summary
    }

    var located: TextLocated<Message> {
        TextLocated(
            location: TextLocation(zeroBasedLine: max(0, line - 1), column: 0),
            entity: Message(
                category: severity == .error ? .error : .warning,
                length: 1,
                summary: summary,
                description: nil,
            ),
        )
    }
}
