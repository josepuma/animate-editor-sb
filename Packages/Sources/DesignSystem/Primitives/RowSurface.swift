import SwiftUI

public extension View {
    /// The surface of a row in a list: nothing at rest, a raised tone under
    /// the pointer, and the accent ring when chosen.
    ///
    /// Shared so every list in the app moves through the same three states.
    /// They used to be written per row — `Fill.selected` in one, `rowSelected`
    /// in the next, `rowHover` in a third — and a panel holding two kinds of
    /// row showed two ideas of what "selected" looks like.
    ///
    /// Selection is the **ring**, not a brighter fill: a fill says "pressed",
    /// the ring says "this one", like every other chosen thing in the app.
    func rowSurface(
        isSelected: Bool = false,
        isHovered: Bool = false,
        radius: CGFloat = Theme.Radius.control,
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        return background {
            shape.fill(isSelected || isHovered ? Theme.Tone.raised : .clear)
        }
        .overlay {
            shape.strokeBorder(isSelected ? Theme.Palette.accent : .clear, lineWidth: Theme.Size.ring)
        }
    }
}
