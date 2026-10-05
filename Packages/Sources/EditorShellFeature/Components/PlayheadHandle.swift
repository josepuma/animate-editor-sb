import DesignSystem
import SwiftUI

/// The draggable head of a playhead, sitting above its line.
package struct PlayheadHandle: View {
    private let tint: Color

    package init(tint: Color = Theme.Palette.accent) {
        self.tint = tint
    }

    package var body: some View {
        Capsule()
            .fill(tint)
            .frame(width: Theme.Size.playheadHandleWidth, height: Theme.Size.dividerHeight)
            .overlay {
                Capsule().strokeBorder(Theme.Border.handle, lineWidth: Theme.Size.hairline)
            }
            .elevated(Theme.Elevation.medium)
    }
}
