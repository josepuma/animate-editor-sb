import DesignSystem
import SwiftUI

/// Every token at its real size, so the scale can be judged rather than read.
struct TokensPage: View {
    var body: some View {
        Specimen("Spacing", note: "A 4pt scale, named by role so a step can be retuned everywhere at once.") {
            SpecimenRow {
                MetricBar("hair", Theme.Spacing.hair)
                MetricBar("tight", Theme.Spacing.tight)
                MetricBar("snug", Theme.Spacing.snug)
                MetricBar("compact", Theme.Spacing.compact)
                MetricBar("regular", Theme.Spacing.regular)
                MetricBar("loose", Theme.Spacing.loose)
                MetricBar("section", Theme.Spacing.section)
                MetricBar("page", Theme.Spacing.page)
            }
        }

        Specimen("Radius", note: "Paired to the size of what they wrap: too small on a large surface reads as a mistake.") {
            SpecimenRow {
                MetricBar("small", Theme.Radius.small, isRadius: true)
                MetricBar("control", Theme.Radius.control, isRadius: true)
                MetricBar("bar", Theme.Radius.bar, isRadius: true)
                MetricBar("panel", Theme.Radius.panel, isRadius: true)
                MetricBar("stage", Theme.Radius.stage, isRadius: true)
            }
        }

        Specimen("Typography", note: "Roles rather than sizes — .readout says what the text is for.") {
            VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
                sample("title", Theme.Typography.title)
                sample("heading", Theme.Typography.heading)
                sample("cardTitle", Theme.Typography.cardTitle)
                sample("body", Theme.Typography.body)
                sample("label", Theme.Typography.label)
                sample("micro", Theme.Typography.micro)
                sample("readout", Theme.Typography.readout, text: "00:00.000")
            }
        }

        Specimen("Palette", note: "Text follows the system; accents are chosen, because the system palette desaturates on a near-black stage.") {
            SpecimenRow {
                ColorSwatch("primary", Theme.Palette.primary)
                ColorSwatch("secondary", Theme.Palette.secondary)
                ColorSwatch("tertiary", Theme.Palette.tertiary)
                ColorSwatch("accent", Theme.Palette.accent)
                ColorSwatch("playhead", Theme.Palette.playhead)
                ColorSwatch("warning", Theme.Palette.warning)
                ColorSwatch("danger", Theme.Palette.danger)
            }
        }

        Specimen("Fill", note: "The states a control moves through. Written as raw opacities they drift — one place lands on 0.12, another on 0.1.") {
            SpecimenRow {
                ColorSwatch("subtle", Theme.Fill.subtle, overDark: true)
                ColorSwatch("panel", Theme.Fill.panel, overDark: true)
                ColorSwatch("raised", Theme.Fill.raised, overDark: true)
                ColorSwatch("well", Theme.Fill.well, overDark: true)
                ColorSwatch("hover", Theme.Fill.hover, overDark: true)
                ColorSwatch("selected", Theme.Fill.selected, overDark: true)
                ColorSwatch("badge", Theme.Fill.badge, overDark: true)
                ColorSwatch("groove", Theme.Fill.groove, overDark: true)
            }
        }

        Specimen(
            "Row fills",
            note: "Fainter than the shared ones on purpose: a track lane is several times the height of a list row, and the same opacity over that area reads as a lit panel.",
        ) {
            SpecimenRow {
                ColorSwatch("rowHover", Theme.Fill.rowHover, overDark: true)
                ColorSwatch("rowSelected", Theme.Fill.rowSelected, overDark: true)
            }
        }

        Specimen("Track palette", note: "Content colours, distinct from each other and legible on dark.") {
            SpecimenRow {
                ColorSwatch("blue", Theme.TrackPalette.blue)
                ColorSwatch("violet", Theme.TrackPalette.violet)
                ColorSwatch("pink", Theme.TrackPalette.pink)
                ColorSwatch("teal", Theme.TrackPalette.teal)
                ColorSwatch("amber", Theme.TrackPalette.amber)
                ColorSwatch("green", Theme.TrackPalette.green)
                ColorSwatch("red", Theme.TrackPalette.red)
            }
        }

        Specimen("Elevation", note: "On a near-black stage a shadow reads as depth rather than as a grey smudge.") {
            SpecimenRow {
                elevationTile("low", Theme.Elevation.low)
                elevationTile("medium", Theme.Elevation.medium)
                elevationTile("high", Theme.Elevation.high)
            }
        }
    }

    private func sample(_ name: String, _ font: Font, text: String = "The quick brown fox") -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.compact) {
            Text(name)
                .font(Theme.Typography.readout)
                .foregroundStyle(Theme.Palette.tertiary)
                .frame(width: 84, alignment: .leading)

            Text(text)
                .font(font)
                .foregroundStyle(Theme.Palette.primary)
        }
    }

    private func elevationTile(_ name: String, _ shadow: Theme.Elevation.Shadow) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                .fill(Theme.Palette.accentMuted)
                .frame(width: 96, height: 56)
                .elevated(shadow)

            Text(name)
                .font(Theme.Typography.readout)
                .foregroundStyle(Theme.Palette.tertiary)
        }
    }
}
