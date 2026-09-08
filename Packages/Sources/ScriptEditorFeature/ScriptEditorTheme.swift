import AppKit
import CodeEditorView
import DesignSystem

extension CodeEditorView.Theme {
    /// The editor, dressed as the rest of the app.
    ///
    /// Built here rather than left at the environment's default, which is
    /// `Theme.defaultLight` — a white page in a dark-only app. The library's own
    /// dark theme exists but is declared as a mutable `static var`, which Swift
    /// 6 will not let a view read, so this is also the only reachable way to get
    /// a dark editor at all.
    ///
    /// The syntax colours are the editor's own dark palette, kept because
    /// nothing in this design system names a colour per token category — there
    /// is no `Theme.Palette.keyword`, and inventing nine roles to serve a
    /// highlighter is the design system working for the dependency instead of
    /// What *is* taken from tokens is what the eye reads as belonging to the
    /// app: the current line, the selection and the caret. The rest are written
    /// out, because `Theme.Palette.primary` is `Color.primary` — semantic, and
    /// resolved against whatever appearance is current when converted for a
    /// view the library configures itself.
    static var animateEditorDark: CodeEditorView.Theme {
        CodeEditorView.Theme(
            colourScheme: .dark,
            fontName: "SFMono-Medium",
            fontSize: 12,
            // Explicit rather than `Theme.Palette.primary`, which is
            // `Color.primary` — a semantic colour that resolves against
            // whatever appearance is current. Converted to an `NSColor` for a
            // view the library configures itself, it resolved to black on
            // black. The tokens below are literal colours, so they convert
            // safely.
            textColour: NSColor(white: 0.87, alpha: 1),
            commentColour: NSColor(white: 0.45, alpha: 1),
            stringColour: NSColor(red: 0.99, green: 0.53, blue: 0.44, alpha: 1),
            characterColour: NSColor(red: 0.99, green: 0.53, blue: 0.44, alpha: 1),
            numberColour: NSColor(red: 0.84, green: 0.72, blue: 1.0, alpha: 1),
            identifierColour: NSColor(white: 0.87, alpha: 1),
            operatorColour: NSColor(white: 0.65, alpha: 1),
            keywordColour: NSColor(red: 1.0, green: 0.47, blue: 0.70, alpha: 1),
            symbolColour: NSColor(white: 0.65, alpha: 1),
            typeColour: NSColor(red: 0.51, green: 0.83, blue: 0.98, alpha: 1),
            fieldColour: NSColor(red: 0.51, green: 0.83, blue: 0.98, alpha: 1),
            caseColour: NSColor(red: 0.84, green: 0.72, blue: 1.0, alpha: 1),
            // The page itself, from the surface the panel sits on: an editor a
            // shade off from its own container reads as a pasted-in rectangle.
            backgroundColour: NSColor(white: 0.09, alpha: 1),
            currentLineColour: NSColor(Theme.Fill.hover),
            selectionColour: NSColor(Theme.Fill.selected),
            cursorColour: NSColor(Theme.Palette.accent),
            invisiblesColour: NSColor(white: 0.33, alpha: 1),
        )
    }
}
