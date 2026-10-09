import SwiftUI

/// A labelled switch, as one row of a group of fields.
///
/// Built on `PropertyRow`, so its label sits in the same column, the same size
/// and the same tone as every field's around it. It had its own label — a
/// brighter one, at the row's left edge — and a column of fields with one
/// checkbox among them read as two forms interleaved.
///
/// The switch itself is `SwitchControl`, so a row that is not a `ToggleField`
/// draws the same one.
public struct ToggleField: View {
    private let label: String
    @Binding private var isOn: Bool

    public init(_ label: String, isOn: Binding<Bool>) {
        self.label = label
        _isOn = isOn
    }

    public var body: some View {
        PropertyRow(label) {
            SwitchControl(isOn: $isOn)
        }
    }
}
