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
        /// 18 — the canvas and other full-bleed surfaces.
        ///
        /// Matches `.panel` on purpose: the canvas sits beside the panels
        /// rather than on them, so a rounder corner on the one surface sharing
        /// their edge reads as belonging to a different family. It keeps its
        /// own name because it answers a different question — the two are equal
        /// today, not the same thing.
        public static let stage: CGFloat = 18

        /// The radius a shape needs to sit concentrically inside another.
        ///
        /// Two rounded rectangles are only parallel when the inner radius is
        /// the outer one less the gap between them. Pick the inner radius from
        /// the scale instead and the curves diverge: the inner corner reads as
        /// too square or too round against its own socket, which is the kind of
        /// wrongness that is obvious without being nameable.
        public static func nested(in outer: CGFloat, inset: CGFloat) -> CGFloat {
            max(outer - inset, 0)
        }
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
        /// 10 — width of the playhead's grab handle.
        public static let playheadHandleWidth: CGFloat = 10
        /// 4 — thickness of a scrubber or slider groove.
        public static let grooveThickness: CGFloat = 4
        /// 1.5 — a ring drawn around a control, thicker than a hairline so it
        /// reads as a deliberate outline rather than an edge.
        public static let ring: CGFloat = 1.5
        /// 58 — label column in an inspector row, wide enough for "Rotation".
        public static let propertyLabel: CGFloat = 58
        /// 38 — a numeric readout beside a slider, fixed so it stops jittering.
        public static let valueReadout: CGFloat = 38

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

    /// Translucent white fills, layered over the app's dark chrome.
    ///
    /// These are the states a control moves through — resting, hovered,
    /// selected — named so the whole app shifts together. Written as raw
    /// opacities they drift: the same control ends up at 0.12 in one place and
    /// 0.1 in another, and nobody notices until the two sit side by side.
    public enum Fill {
        /// 0.03 — a block grouping other controls, barely distinct from behind.
        public static let subtle = Color.white.opacity(0.03)
        /// 0.05 — a panel anchored to the window: side panel, inspector, cards.
        ///
        /// Opaque rather than glass. A panel at the window edge has nothing
        /// behind it but the desktop, so refracting buys no depth and costs
        /// contrast on whatever it holds.
        public static let panel = Color.white.opacity(0.05)
        /// 0.09 — a panel lifted above its siblings.
        public static let raised = Color.white.opacity(0.09)
        /// 0.06 — the well a control sits in, at rest.
        public static let well = Color.white.opacity(0.06)
        /// 0.06 — a hovered control that is not selected.
        public static let hover = Color.white.opacity(0.06)
        /// 0.12 — the selected item in a group.
        public static let selected = Color.white.opacity(0.12)
        /// 0.025 — a hovered row tall enough that `.hover` would overwhelm it.
        public static let rowHover = Color.white.opacity(0.025)
        /// 0.05 — a selected row of that same height.
        ///
        /// Fainter than `.selected` because the fill covers several times the
        /// area: the same opacity over a track lane reads as a lit panel rather
        /// than as a highlighted row.
        public static let rowSelected = Color.white.opacity(0.05)
        /// 0.18 — a badge on tinted content, which needs more to read.
        public static let badge = Color.white.opacity(0.18)
        /// 0.18 — the unfilled groove of a scrubber or slider.
        ///
        /// Brighter than `.well` because these sit on the overlay's scrim
        /// rather than on the app's chrome, and a groove that reads as empty
        /// gives the filled part nothing to measure against.
        public static let groove = Color.white.opacity(0.18)
    }

    /// Hairline borders, in the same layered white.
    public enum Border {
        /// 0.06 — the edge of a field well.
        public static let field = Color.white.opacity(0.06)
        /// 0.08 — the edge of an anchored panel.
        public static let panel = Color.white.opacity(0.08)
        /// 0.14 — the edge of a raised panel, which needs to separate further.
        public static let raised = Color.white.opacity(0.14)
        /// 0.1 — a card at rest.
        public static let card = Color.white.opacity(0.1)
        /// 0.28 — a card under the pointer.
        public static let cardHovered = Color.white.opacity(0.28)
        /// 0.2 — a badge over artwork.
        public static let badge = Color.white.opacity(0.2)
        /// 0.35 — the playhead's own edge.
        public static let handle = Color.white.opacity(0.35)
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
        public static let quick = Animation.easeOut(duration: quickDuration)
        /// Panels appearing and disappearing.
        public static let standard = Animation.easeInOut(duration: standardDuration)
        /// Layout changes large enough to need following by eye.
        public static let deliberate = Animation.easeInOut(duration: deliberateDuration)

        // Durations, for the cases that have to wait one out rather than
        // animate. An `Animation` does not report its own length, so anything
        // scheduling around one needs the number itself — and reading it from
        // here is what keeps the wait and the animation in step.

        public static let quickDuration: TimeInterval = 0.12
        public static let standardDuration: TimeInterval = 0.22
        public static let deliberateDuration: TimeInterval = 0.35
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
