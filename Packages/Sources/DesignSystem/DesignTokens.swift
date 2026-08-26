import SwiftUI

/// The design system's vocabulary.
///
/// Every spacing, radius, size and duration in the app comes from here. Views
/// that reach for raw numbers drift apart as the app grows: this is what keeps
/// a timeline built next month looking like the transport bar built today.
public enum Theme {
    // ─── Spacing ─────────────────────────────────────────────────────────────

    /// A 4pt scale. Steps are named by role rather than size, so a value can be
    /// retuned across the app without renaming every call site.
    public enum Spacing {
        /// 2 — hairline gaps, icon to its own label.
        public static let hair: CGFloat = 2
        /// 4 — tightly related elements.
        public static let tight: CGFloat = 4
        /// 8 — within a control.
        public static let snug: CGFloat = 8
        /// 12 — between controls in a group.
        public static let compact: CGFloat = 12
        /// 16 — the default gap between elements.
        public static let regular: CGFloat = 16
        /// 24 — between groups.
        public static let loose: CGFloat = 24
        /// 32 — between sections.
        public static let section: CGFloat = 32
        /// 48 — page margins and hero areas.
        public static let page: CGFloat = 48
    }

    // ─── Radius ──────────────────────────────────────────────────────────────

    /// Corner radii, paired to the size of what they wrap. A radius that is too
    /// small on a large surface reads as a mistake rather than a style.
    public enum Radius {
        /// 6 — chips and small badges.
        public static let small: CGFloat = 6
        /// 10 — buttons and inline controls.
        public static let control: CGFloat = 10
        /// 14 — floating bars.
        public static let bar: CGFloat = 14
        /// 18 — cards and panels.
        public static let panel: CGFloat = 18
        /// 24 — the largest surfaces, such as the canvas.
        public static let stage: CGFloat = 24
    }

    // ─── Sizing ──────────────────────────────────────────────────────────────

    public enum Size {
        /// 22 — dense icon button, for secondary actions in a crowded bar.
        public static let controlTiny: CGFloat = 22
        /// 28 — compact icon button.
        public static let controlSmall: CGFloat = 28
        /// 34 — standard icon button, the transport's play control.
        public static let control: CGFloat = 34
        /// 44 — primary action, and the minimum comfortable pointer target.
        public static let controlLarge: CGFloat = 44
        /// 1 — hairline separators, independent of screen scale.
        public static let hairline: CGFloat = 1
        /// 14 — height of a divider inside a bar.
        public static let dividerHeight: CGFloat = 14

        /// Heights for horizontal strips of content, such as the timeline.
        ///
        /// The canvas is what the app is for; anything stacked around it earns
        /// its height. These are deliberately tight.
        public enum Strip {
            /// 18 — a scannable summary, such as the whole-track overview.
            public static let overview: CGFloat = 18
            /// 40 — an interactive strip, such as the zoomable beat grid.
            public static let detail: CGFloat = 40
        }

        /// 26 — height of an inspector field, tight enough to stack many.
        public static let field: CGFloat = 26

        /// 44 — height of a floating control cluster.
        ///
        /// Every pill in a row shares this so they line up: letting each one
        /// take its height from its own contents leaves a ragged row, since a
        /// ringed button is taller than a line of text.
        public static let pill: CGFloat = 44
    }

    // ─── Typography ──────────────────────────────────────────────────────────

    /// Roles rather than sizes: `.readout` says what the text is for, so the
    /// same numbers stay consistent everywhere they appear.
    public enum Typography {
        /// Screen titles.
        public static let title = Font.system(size: 30, weight: .semibold, design: .rounded)
        /// Section headings.
        public static let heading = Font.system(.subheadline, design: .rounded, weight: .semibold)
        /// Card and row titles.
        public static let cardTitle = Font.system(.body, design: .rounded, weight: .medium)
        /// Body copy.
        public static let body = Font.callout
        /// Labels inside bars and chips.
        public static let label = Font.system(.caption, design: .rounded, weight: .medium)
        /// The smallest readable text: ruler ticks, secondary settings.
        public static let micro = Font.system(.caption2, design: .rounded, weight: .medium)
        /// Numbers that change every frame — monospaced so they stop jittering.
        public static let readout = Font.system(.caption, design: .monospaced)
        /// Glyphs in icon buttons.
        public static let controlIcon = Font.system(size: 15, weight: .semibold)
        /// A large glyph standing in for empty state, such as a drop target.
        public static let emptyStateIcon = Font.system(size: 34, weight: .light)
    }

    // ─── Colour ──────────────────────────────────────────────────────────────

    /// Text and status colours.
    ///
    /// Text follows the system so the app respects appearance and accessibility
    /// settings; the accent and track colours are chosen rather than inherited,
    /// because the system palette desaturates in dark mode and content colours
    /// need to stay vivid against a near-black stage.
    public enum Palette {
        /// Primary text.
        public static let primary = Color.primary
        /// Supporting text and inactive glyphs.
        public static let secondary = Color.secondary
        /// The least prominent text, such as paths under a title.
        public static let tertiary = Color.secondary.opacity(0.7)
        /// Selection, the playhead and active controls.
        public static let accent = Color(red: 0.55, green: 0.36, blue: 0.96)
        /// A softer accent for fills behind content.
        public static let accentMuted = Color(red: 0.55, green: 0.36, blue: 0.96).opacity(0.22)
        /// The playhead, in its own colour so it never reads as just another
        /// accented control.
        public static let playhead = Color(red: 0.98, green: 0.55, blue: 0.22)
        /// Something needs attention but still works.
        public static let warning = Color(red: 0.98, green: 0.68, blue: 0.25)
        /// Something failed.
        public static let danger = Color(red: 0.94, green: 0.36, blue: 0.40)
        /// Behind the storyboard canvas: osu! composites over black, and any
        /// other colour tints every partly transparent sprite.
        public static let stage = Color.black
    }

    /// Colours identifying content, chosen to stay distinct from each other
    /// and legible on a dark surface.
    public enum TrackPalette {
        public static let blue = Color(red: 0.36, green: 0.60, blue: 0.98)
        public static let violet = Color(red: 0.62, green: 0.42, blue: 0.98)
        public static let pink = Color(red: 0.95, green: 0.42, blue: 0.72)
        public static let teal = Color(red: 0.24, green: 0.78, blue: 0.76)
        public static let amber = Color(red: 0.98, green: 0.68, blue: 0.25)
        public static let green = Color(red: 0.38, green: 0.82, blue: 0.52)
        public static let red = Color(red: 0.94, green: 0.42, blue: 0.42)
    }

    // ─── Motion ──────────────────────────────────────────────────────────────

    public enum Motion {
        /// Hover and focus feedback, fast enough to feel attached to the cursor.
        public static let quick = Animation.easeOut(duration: 0.12)
        /// Panels appearing and disappearing.
        public static let standard = Animation.easeInOut(duration: 0.22)
        /// Layout changes large enough to need following by eye.
        public static let deliberate = Animation.easeInOut(duration: 0.35)
    }

    // ─── Elevation ───────────────────────────────────────────────────────────

    /// Drop shadows that lift content off its surface.
    ///
    /// On a near-black stage a shadow reads as depth rather than as a grey
    /// smudge, which is what separates a floating block from a painted
    /// rectangle.
    public enum Elevation {
        public struct Shadow: Sendable {
            public let color: Color
            public let radius: CGFloat
            public let y: CGFloat
        }

        /// Content sitting on a panel: track blocks, chips.
        public static let low = Shadow(color: .black.opacity(0.35), radius: 4, y: 2)
        /// Panels over the stage.
        public static let medium = Shadow(color: .black.opacity(0.45), radius: 12, y: 4)
        /// Popovers and dragged content.
        public static let high = Shadow(color: .black.opacity(0.55), radius: 24, y: 8)
    }
}
