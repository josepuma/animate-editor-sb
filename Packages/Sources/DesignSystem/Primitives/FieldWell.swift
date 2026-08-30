import SwiftUI

/// The dark well every inspector control sits in.
///
/// A shared shape is what makes a column of mixed controls — numbers, menus,
/// colours — read as one form rather than as a pile of widgets.
public struct FieldWell<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.horizontal, Theme.Spacing.snug)
            .padding(.vertical, Theme.Spacing.tight)
            .frame(height: Theme.Size.field)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(Theme.Fill.well)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .strokeBorder(Theme.Border.field, lineWidth: Theme.Size.hairline)
            }
    }
}

/// A titled block of fields, separated from its neighbours by its own surface.
public struct FieldGroup<Content: View>: View {
    private let title: String?
    private let content: Content

    public init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
            if let title {
                Text(title)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.tertiary)
            }
            content
        }
        .padding(Theme.Spacing.compact)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.bar, style: .continuous)
                .fill(Theme.Fill.subtle)
        }
    }
}
