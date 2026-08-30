import DesignSystem
import SwiftUI

/// Inspector controls, shown stacked as they actually appear.
///
/// One at a time they all look fine; in a column, a field one point taller than
/// its neighbour is impossible to miss.
struct FieldsPage: View {
    private enum Easing: String, CaseIterable, Identifiable, Hashable {
        case linear = "Linear"
        case easeIn = "Ease In"
        case easeOut = "Ease Out"
        var id: Self { self }
    }

    private enum Alignment: String, CaseIterable, Identifiable, Hashable {
        case leading, centre, trailing
        var id: Self { self }

        var icon: String {
            switch self {
            case .leading: "align.horizontal.left"
            case .centre: "align.horizontal.center"
            case .trailing: "align.horizontal.right"
            }
        }
    }

    @State private var easing: Easing = .easeOut
    @State private var alignment: Alignment = .centre
    @State private var opacity = 0.8
    @State private var scale = 1.0
    @State private var rotation = 0.0
    @State private var colour = Color(red: 0.55, green: 0.36, blue: 0.96)
    @State private var isAdditive = true

    var body: some View {
        Specimen(
            "A field column",
            note: "A shared well is what makes mixed controls read as one form rather than a pile of widgets.",
        ) {
            VStack(spacing: Theme.Spacing.snug) {
                PropertyRow("Easing") {
                    MenuField(items: Easing.allCases, selection: $easing, label: \.rawValue)
                }
                PropertyRow("Opacity") {
                    SliderField(value: $opacity)
                }
                PropertyRow("Scale") {
                    NumberField(value: $scale, step: 0.1, range: 0...10, format: "%.2f")
                }
                PropertyRow("Rotation") {
                    NumberField(value: $rotation, unit: "°", step: 15, range: -360...360)
                }
                PropertyRow("Colour") {
                    ColorField(color: $colour, hex: "#8C5CF6")
                }
                PropertyRow("Align") {
                    IconSegments(
                        items: Alignment.allCases,
                        selection: $alignment,
                        icon: \.icon,
                        label: \.rawValue,
                    )
                }
                PropertyRow("Layer") {
                    PropertyValue("Foreground")
                }
                PropertyRow("File") {
                    PropertyValue("sb/particles/star.png", monospaced: true)
                }
            }
            .frame(maxWidth: 340)
        }

        Specimen("FieldGroup", note: "A titled block, separated from its neighbours by its own surface.") {
            HStack(alignment: .top, spacing: Theme.Spacing.regular) {
                FieldGroup("Transform") {
                    PropertyRow("Scale") {
                        NumberField(value: $scale, step: 0.1, format: "%.2f")
                    }
                    PropertyRow("Rotate") {
                        NumberField(value: $rotation, unit: "°", step: 15)
                    }
                }
                .frame(width: 280)

                FieldGroup("Blending") {
                    ToggleField("Additive", isOn: $isAdditive)
                    PropertyRow("Opacity") {
                        SliderField(value: $opacity)
                    }
                }
                .frame(width: 280)

                Spacer(minLength: 0)
            }
        }

        Specimen("FieldWell on its own", note: "The container behind every field, for building one that does not exist yet.") {
            FieldWell {
                HStack {
                    Text("Anything")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.secondary)
                    Spacer(minLength: 0)
                }
            }
            .frame(width: 200)
        }
    }
}
