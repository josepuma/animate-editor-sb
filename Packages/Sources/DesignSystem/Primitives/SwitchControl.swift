import SwiftUI

/// An on/off switch, for the value column of a row.
///
/// A switch rather than a checkbox: it says on and off at a glance from across
/// the panel, which is what an inspector's toggles are scanned for. A bare
/// `Toggle` on macOS is a checkbox, which is how two of them slipped into the
/// inspector beside the switch `ToggleField` already drew — one recipe, so
/// there is nothing left to forget.
///
/// Leading, where every other field's value starts: a switch at the far edge
/// of the row reads as belonging to another column.
public struct SwitchControl: View {
    @Binding private var isOn: Bool

    public init(isOn: Binding<Bool>) {
        _isOn = isOn
    }

    public var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(Theme.Palette.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
