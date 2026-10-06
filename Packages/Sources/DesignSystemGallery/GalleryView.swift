import DesignSystem
import SwiftUI

/// The catalogue's own navigation: a rail down the side, one page per chapter.
struct GalleryView: View {
    enum Page: String, CaseIterable, Identifiable, Hashable {
        case tokens = "Tokens"
        case surfaces = "Surfaces"
        case buttons = "Buttons"
        case fields = "Fields"
        case chrome = "Chrome"
        case composites = "Components"
        case previews = "Previews"
        case panels = "Panels"

        var id: Self { self }

        var icon: String {
            switch self {
            case .tokens: "paintpalette"
            case .surfaces: "square.on.square"
            case .buttons: "hand.tap"
            case .fields: "slider.horizontal.3"
            case .chrome: "sidebar.left"
            case .composites: "square.grid.2x2"
            case .previews: "photo.on.rectangle.angled"
            case .panels: "list.bullet.rectangle"
            }
        }

        var subtitle: String {
            switch self {
            case .tokens: "The vocabulary every component is built from."
            case .surfaces: "Liquid Glass by role, not by material."
            case .buttons: "One recipe per intent."
            case .fields: "Inspector controls, sharing one well."
            case .chrome: "Navigation and structure."
            case .composites: "Composed in the features, where the tokens meet the domain."
            case .previews: "Tiles, glows and moving previews — the library's look."
            case .panels: "The rows and cards of the editor's side panels and inspector."
            }
        }
    }

    @State private var page: Page = .tokens

    var body: some View {
        HStack(spacing: 0) {
            SidebarRail(
                items: Page.allCases,
                selection: $page,
                icon: \.icon,
                label: \.rawValue,
            )
            .frame(width: Theme.Size.controlLarge)

            Divider()

            ScrollView {
                GallerySection(page.rawValue, subtitle: page.subtitle) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
                        content
                    }
                }
                .padding(Theme.Spacing.section)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Theme.Tone.base)
        .preferredColorScheme(.dark)
        // The app's accent, for every control AppKit draws — sliders, switches,
        // focus rings. Left alone they take the user's system accent, so on a
        // Mac set to orange the inspector's sliders came out orange beside a
        // lime selection: two accents, one of them not chosen by the app.
        .tint(Theme.Palette.accent)
        .surfaceGroup()
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .tokens: TokensPage()
        case .surfaces: SurfacesPage()
        case .buttons: ButtonsPage()
        case .fields: FieldsPage()
        case .chrome: ChromePage()
        case .composites: CompositesPage()
        case .previews: PreviewsPage()
        case .panels: PanelsPage()
        }
    }
}
