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
            language: .javaScript(),
            layout: CodeEditor.LayoutConfiguration(showMinimap: false, wrapText: true),
        )
        // The theme is left at the environment's own default rather than set.
        //
        // The library exposes its dark theme as a mutable `static var`, which
        // Swift 6 strict concurrency will not let a view read at all — and its
        // `Theme` is not `Sendable`, so it cannot be cached in a `static let`
        // either. The default already resolves to a dark scheme, and this app
        // is dark-only, so the simplest reading is also the correct one.
        //
        // Building a theme from design-system tokens would need a colour per
        // token category — nine roles this project does not have — which is the
        // design system serving the dependency rather than the app.
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
