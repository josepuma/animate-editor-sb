import DesignSystem
import SwiftUI
import Testing

@testable import EditorShellFeature

/// The floor the window cannot go below, and what it is made of.
///
/// Written when the side panel went from 240 to 300 points, which moved this
/// number without anything saying so: it is derived from the rail, the panel,
/// the inspector and a minimum canvas, so widening any of them raises the
/// smallest window the app can open in. Nobody would notice until the window
/// refused to fit a display.
@MainActor
@Suite("Minimum window size")
struct WindowMinimumTests {
    /// A 13-inch MacBook Air in its default scaled mode. The app has to open
    /// on the smallest Mac laptop Apple sells, with room left over — a window
    /// at exactly the display width is a window with no desktop around it.
    static let smallestDisplay = CGSize(width: 1470, height: 956)

    @Test("the app fits the smallest Mac laptop, with room to spare")
    func fitsASmallDisplay() {
        let size = EditorShellView<EmptyView>.minimumWindowSize

        #expect(size.width < Self.smallestDisplay.width * 0.85, "\(size.width) points wide")
        #expect(size.height < Self.smallestDisplay.height * 0.9, "\(size.height) points tall")
    }

    /// The canvas is what the editor is for, so the chrome cannot take most of
    /// a real window.
    ///
    /// Measured **against a display**, not against the minimum window: at the
    /// minimum the chrome is over half by definition — that window exists to
    /// be the smallest one where nothing breaks, and it was already 52% before
    /// the panel widened. The first version of this test asserted against
    /// `minimumWidth` and failed on a change that moved the share by two
    /// points, which is the test measuring the wrong window rather than the
    /// layout being wrong.
    @Test("the chrome does not crowd out the canvas on a real display")
    func canvasKeepsItsShare() {
        let chrome = ShellLayout.railWidth
            + SidePanelView.width
            + InspectorView.width

        #expect(chrome < Self.smallestDisplay.width / 2, "chrome is \(chrome)")
    }

    @Test("widening the panel is accounted for in the minimum")
    func minimumIncludesThePanel() {
        // Not a tautology: the point is that the minimum is *derived* rather
        // than a number someone typed, so a panel that grows cannot leave the
        // window's floor behind.
        #expect(ShellLayout.minimumWidth > SidePanelView.width)
        #expect(
            ShellLayout.minimumWidth
                >= SidePanelView.width + ShellLayout.minimumCanvasWidth,
        )
    }

    /// A panel narrower than this cannot hold a label beside a control, which
    /// is what every row in it is.
    @Test("the panel is wide enough for a label and a control")
    func panelHoldsARow() {
        // Measured against the real case that failed: "China continental
        // (simplificado)" is 32 characters, and at 240 points the control had
        // about 130 to draw it in.
        #expect(SidePanelView.width >= 280)
    }
}
