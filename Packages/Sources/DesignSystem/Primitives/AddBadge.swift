import SwiftUI

/// The "add this" mark at the end of a library row: a quiet plus at rest, a
/// lit accent disc under the pointer.
///
/// Lit only on hover because a column of bright discs is a column of buttons,
/// and the row itself is the thing being chosen. The disc appears where the
/// hand already is, as the answer to "what happens if I click".
public struct AddBadge: View {
    private let isHighlighted: Bool

    public init(isHighlighted: Bool) {
        self.isHighlighted = isHighlighted
    }

    public var body: some View {
        Image(systemName: "plus")
            .font(.system(size: (Theme.Size.controlTiny * 0.5).rounded(), weight: .bold))
            .foregroundStyle(isHighlighted ? Theme.Palette.onAccent : Theme.Palette.tertiary)
            .frame(width: Theme.Size.controlTiny, height: Theme.Size.controlTiny)
            .background(Circle().fill(isHighlighted ? Theme.Palette.accent : Theme.Tone.well))
            .animation(Theme.Motion.quick, value: isHighlighted)
    }
}
