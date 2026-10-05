import DesignSystem
import SwiftUI

/// The key at the playhead — the trailing column of an animatable property.
///
/// One component for the transform's rows and a filter's parameters alike: a
/// diamond has to mean one thing wherever it appears. Filled in the accent when
/// the playhead stands on a key, hollow otherwise; a click plants one.
///
/// Moving to the neighbouring keys is on its menu rather than on arrows beside
/// it. Arrows took three columns, and in a 264-point inspector that left the
/// field too narrow for its own number; the keyframe timeline keeps its arrows,
/// where there is room for them.
///
/// Draws nothing while the property is not animating, but its column is still
/// reserved by the panel's ``PropertyGrid`` — appearing must not shrink the
/// field beside it.
package struct KeyframeDiamond: View {
    private let isAnimating: Bool
    private let isOnKey: Bool
    private let addKey: () -> Void
    private let previous: (() -> Void)?
    private let next: (() -> Void)?

    /// - Parameters:
    ///   - previous: moves the playhead to the key before it, or `nil` when
    ///     there is none — the menu item is then shown disabled rather than
    ///     missing, so the menu keeps its shape.
    ///   - next: the same, for the key after it.
    package init(
        isAnimating: Bool,
        isOnKey: Bool,
        addKey: @escaping () -> Void,
        previous: (() -> Void)? = nil,
        next: (() -> Void)? = nil,
    ) {
        self.isAnimating = isAnimating
        self.isOnKey = isOnKey
        self.addKey = addKey
        self.previous = previous
        self.next = next
    }

    package var body: some View {
        if isAnimating {
            IconButton(
                systemImage: isOnKey ? "diamond.fill" : "diamond",
                size: Theme.Size.controlTiny,
                tint: isOnKey ? Theme.Palette.accent : nil,
                help: isOnKey ? "On a keyframe" : "Add a keyframe here",
                action: addKey,
            )
            .contextMenu {
                Button("Previous Keyframe", systemImage: "chevron.left") { previous?() }
                    .disabled(previous == nil)
                Button("Next Keyframe", systemImage: "chevron.right") { next?() }
                    .disabled(next == nil)
            }
        }
    }
}
