import SwiftUI

/// Builds the code editor: a binding to the source, and what running means.
///
/// A closure carried through the environment rather than a generic threaded
/// through the view hierarchy. The canvas arrives as a `@ViewBuilder` because
/// it is one parameter on one view; an editor three levels down would put a
/// type parameter on `EditorShellView`, `SidePanelView` and every signature
/// between them — for a view built once.
///
/// It is not on `EditorShellModel` either, deliberately: that type imports
/// `CoreGraphics`, `Foundation` and Core, and nothing else. Keeping SwiftUI out
/// of it is what lets its tests run with no view involved, and a view seam is
/// not worth spending that on.
public typealias ScriptEditorBuilder = (Binding<String>, @escaping () -> Void) -> AnyView

public extension EnvironmentValues {
    /// The code editor the host provides, if it provides one.
    ///
    /// Absent, the panel says so rather than falling back to a plain text box
    /// — a text field where an editor belongs is exactly what this replaced,
    /// and offering it again would hide a broken build behind something that
    /// looks like it works.
    @Entry var scriptEditor: ScriptEditorBuilder?
}

public extension View {
    /// Provides the code editor to the shell.
    func scriptEditor(_ build: @escaping ScriptEditorBuilder) -> some View {
        environment(\.scriptEditor, build)
    }
}
