import SwiftUI

public extension View {
    /// Lifts the view off its surface with a drop shadow.
    func elevated(_ shadow: Theme.Elevation.Shadow = Theme.Elevation.low) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, y: shadow.y)
    }
}
