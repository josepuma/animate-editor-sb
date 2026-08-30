import DesignSystem
import SwiftUI

/// One entry in the catalogue: what it is called, what it is for, and the thing
/// itself.
///
/// The caption matters as much as the specimen. A component nobody can name the
/// purpose of gets reinvented next to itself.
struct Specimen<Content: View>: View {
    private let name: String
    private let note: String?
    private let content: Content

    init(_ name: String, note: String? = nil, @ViewBuilder content: () -> Content) {
        self.name = name
        self.note = note
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
            VStack(alignment: .leading, spacing: Theme.Spacing.hair) {
                Text(name)
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(Theme.Palette.primary)

                if let note {
                    Text(note)
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
                .padding(Theme.Spacing.compact)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Theme.Fill.subtle)
                }
        }
    }
}

/// A titled run of specimens.
struct GallerySection<Content: View>: View {
    private let title: String
    private let subtitle: String?
    private let content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.regular) {
            VStack(alignment: .leading, spacing: Theme.Spacing.hair) {
                Text(title)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.secondary)
                }
            }

            content
        }
    }
}

/// A strip of examples laid out in a row, wrapping as the window narrows.
struct SpecimenRow<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.regular) {
            content
            Spacer(minLength: 0)
        }
    }
}

/// A swatch of one colour token, labelled with the name to type.
struct ColorSwatch: View {
    private let name: String
    private let color: Color
    /// Swatches of translucent white need something behind them to read.
    private let overDark: Bool

    init(_ name: String, _ color: Color, overDark: Bool = false) {
        self.name = name
        self.color = color
        self.overDark = overDark
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .fill(color)
                .frame(width: 76, height: 44)
                .background {
                    if overDark {
                        RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                            .fill(Theme.Palette.stage)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        .strokeBorder(Theme.Border.field, lineWidth: Theme.Size.hairline)
                }

            Text(name)
                .font(Theme.Typography.readout)
                .foregroundStyle(Theme.Palette.tertiary)
        }
    }
}

/// A measured bar showing one spacing or radius step at its real size.
struct MetricBar: View {
    private let name: String
    private let value: CGFloat
    private let isRadius: Bool

    init(_ name: String, _ value: CGFloat, isRadius: Bool = false) {
        self.name = name
        self.value = value
        self.isRadius = isRadius
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            if isRadius {
                RoundedRectangle(cornerRadius: value, style: .continuous)
                    .fill(Theme.Palette.accentMuted)
                    .frame(width: 76, height: 56)
                    .overlay {
                        RoundedRectangle(cornerRadius: value, style: .continuous)
                            .strokeBorder(Theme.Palette.accent, lineWidth: Theme.Size.hairline)
                    }
            } else {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.Palette.accent)
                    .frame(width: max(value, 2), height: 22)
            }

            Text("\(name)  \(Int(value))")
                .font(Theme.Typography.readout)
                .foregroundStyle(Theme.Palette.tertiary)
        }
    }
}
