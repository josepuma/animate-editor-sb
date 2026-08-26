import SwiftUI

// ─── Icon button ─────────────────────────────────────────────────────────────

/// A square icon button — the transport controls, toolbar actions, the timeline
/// tools to come.
public struct IconButton: View {
    public enum Prominence {
        /// Sits on an existing surface.
        case plain
        /// Carries its own glass, for buttons that float over content.
        case surfaced
        /// The primary action in its context.
        case accented
    }

    private let systemImage: String
    private let size: CGFloat
    private let prominence: Prominence
    private let help: String?
    private let action: () -> Void

    @State private var isHovered = false

    public init(
        systemImage: String,
        size: CGFloat = Theme.Size.control,
        prominence: Prominence = .plain,
        help: String? = nil,
        action: @escaping () -> Void,
    ) {
        self.systemImage = systemImage
        self.size = size
        self.prominence = prominence
        self.help = help
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(Theme.Typography.controlIcon)
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background {
            if prominence != .plain {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(prominence == .accented ? Theme.Palette.accent : .clear)
            }
        }
        .modifier(SurfaceIfNeeded(prominence: prominence))
        // A hint of scale is enough feedback on a small target; anything more
        // reads as the button moving rather than responding.
        .scaleEffect(isHovered ? 1.06 : 1)
        .animation(Theme.Motion.quick, value: isHovered)
        .onHover { isHovered = $0 }
        .help(help ?? "")
    }

    private var foreground: Color {
        switch prominence {
        case .accented: .white
        case .plain, .surfaced: isHovered ? Theme.Palette.primary : Theme.Palette.secondary
        }
    }
}

/// Applies glass only to the prominences that need their own surface.
private struct SurfaceIfNeeded: ViewModifier {
    let prominence: IconButton.Prominence

    func body(content: Content) -> some View {
        if prominence == .surfaced {
            content.surface(.inset)
        } else {
            content
        }
    }
}

// ─── Readout ─────────────────────────────────────────────────────────────────

/// A labelled statistic, as used in the stats bar.
public struct Readout: View {
    private let systemImage: String
    private let text: String
    private let tint: Color?
    private let help: String?

    public init(_ text: String, systemImage: String, tint: Color? = nil, help: String? = nil) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
        self.help = help
    }

    public var body: some View {
        Label(text, systemImage: systemImage)
            .font(Theme.Typography.label)
            .foregroundStyle(tint ?? Theme.Palette.secondary)
            .help(help ?? "")
    }
}

// ─── Divider ─────────────────────────────────────────────────────────────────

/// A short vertical rule for separating items inside a bar.
public struct BarDivider: View {
    public init() {}

    public var body: some View {
        Divider().frame(height: Theme.Size.dividerHeight)
    }
}

// ─── Bar ─────────────────────────────────────────────────────────────────────

/// A floating horizontal bar of controls.
///
/// The transport, the stats readout and the room switcher in the reference
/// share this shape, so they share this container.
public struct FloatingBar<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    public init(spacing: CGFloat = Theme.Spacing.regular, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: spacing) {
            content
        }
        .padding(.horizontal, Theme.Spacing.regular)
        .padding(.vertical, Theme.Spacing.compact)
        .surface(.bar)
    }
}

// ─── Card ────────────────────────────────────────────────────────────────────

/// A titled panel: an optional leading status dot, a title, an optional
/// subtitle, a trailing accessory, and content beneath.
public struct Card<Content: View, Accessory: View>: View {
    private let title: String
    private let subtitle: String?
    private let statusTint: Color?
    private let accessory: Accessory
    private let content: Content

    public init(
        title: String,
        subtitle: String? = nil,
        statusTint: Color? = nil,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() },
        @ViewBuilder content: () -> Content,
    ) {
        self.title = title
        self.subtitle = subtitle
        self.statusTint = statusTint
        self.accessory = accessory()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
            HStack(spacing: Theme.Spacing.snug) {
                if let statusTint {
                    Circle()
                        .fill(statusTint)
                        .frame(width: Theme.Spacing.snug, height: Theme.Spacing.snug)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.hair) {
                    Text(title)
                        .font(Theme.Typography.cardTitle)
                        .foregroundStyle(Theme.Palette.primary)

                    if let subtitle {
                        Text(subtitle)
                            .font(Theme.Typography.label)
                            .foregroundStyle(Theme.Palette.secondary)
                    }
                }

                Spacer(minLength: Theme.Spacing.snug)
                accessory
            }

            content
        }
        .padding(Theme.Spacing.regular)
        .surface(.panel)
    }
}
