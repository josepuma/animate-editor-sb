import Foundation

/// Every image the app supplies, named and grouped — in one place.
///
/// The sprite menu used to be a hand-written list in the inspector, a third
/// copy of each name beside Core's path and the renderer's title, and it had
/// drifted: 15 of 62 built-ins — the whole Flat vocabulary, the beams, three
/// slashes — could be drawn by presets and never picked by a person. The
/// catalogue is the single list now: the picker, the renderer's titles and the
/// tests read it, and a test fails if any built-in is missing from it.
///
/// Grouped by what an image is *for*, not where it came from: someone looking
/// for lightning is not looking under a pack's name.
public extension BuiltInSprite {
    enum Group: String, CaseIterable, Sendable {
        case particles = "Particles"
        case shapes = "Shapes"
        case flat = "Flat"
        case hud = "HUD"
        case fire = "Fire"
        case energy = "Energy"
        case strokes = "Strokes"
        case atmosphere = "Atmosphere"
        case light = "Light"
        case nature = "Nature"

        /// The order the picker shows them in: the soft generic particles
        /// first, the drawn vocabularies, then the textures by subject.
        public static var displayOrder: [Group] { allCases }
    }

    struct Entry: Hashable, Sendable, Identifiable {
        public let path: String
        public let title: String
        public let group: Group
        public var id: String { path }

        public init(_ path: String, _ title: String, _ group: Group) {
            self.path = path
            self.title = title
            self.group = group
        }
    }

    static let catalogue: [Entry] = [
        Entry(soft, "Soft Dot", .particles),
        Entry(glow, "Glow", .particles),
        Entry(smoke, "Smoke Puff", .particles),
        Entry(star, "Star", .particles),
        Entry(square, "Square", .particles),
        Entry(streak, "Streak", .particles),
        Entry(ring, "Ring", .particles),

        Entry(fill, "Fill", .shapes),
        Entry(disc, "Disc", .shapes),

        Entry(chevron, "Chevron", .flat),
        Entry(arrow, "Arrow", .flat),
        Entry(triangle, "Triangle", .flat),
        Entry(stripe, "Stripe", .flat),
        Entry(node, "Node", .flat),
        Entry(cross, "Cross", .flat),

        Entry(hudSegments, "HUD Segments", .hud),
        Entry(hudArcs, "HUD Arcs", .hud),
        Entry(hudDashes, "HUD Dashes", .hud),
        Entry(hudTicks, "HUD Ticks", .hud),
        Entry(hudArc, "HUD Arc", .hud),
        Entry(hudBracket, "HUD Bracket", .hud),

        Entry(flame, "Flame", .fire),
        Entry(flameTall, "Flame Tall", .fire),
        Entry(flameWisp, "Flame Wisp", .fire),
        Entry(ember, "Embers", .fire),
        Entry(muzzle, "Muzzle Flash", .fire),
        Entry(muzzleWide, "Muzzle Wide", .fire),
        Entry(scorch, "Scorch", .fire),

        Entry(lightning, "Lightning", .energy),
        Entry(lightningWide, "Lightning Wide", .energy),
        Entry(bolt, "Bolt", .energy),
        Entry(boltThin, "Bolt Thin", .energy),
        Entry(flare, "Flare", .energy),
        Entry(flareSoft, "Flare Soft", .energy),
        Entry(runeRing, "Rune Ring", .energy),
        Entry(rune, "Rune", .energy),
        Entry(sparkle, "Sparkle", .energy),

        Entry(arc, "Arc", .strokes),
        Entry(crescent, "Crescent", .strokes),
        Entry(scratch, "Scratch", .strokes),
        Entry(slash, "Slash", .strokes),
        // Named for what it draws: a broad clean arc is a wave front.
        Entry(slashWide, "Wave", .strokes),
        Entry(slashDeep, "Slash Deep", .strokes),
        Entry(slashThin, "Slash Thin", .strokes),
        Entry(beam, "Beam", .strokes),
        Entry(beamThin, "Beam Thin", .strokes),

        Entry(cloud, "Cloud", .atmosphere),
        Entry(cloudWisp, "Cloud Wisp", .atmosphere),
        Entry(debris, "Debris", .atmosphere),
        Entry(pane, "Pane", .atmosphere),

        // "Spotlight", not "Strobe": strobing is what a script does with it,
        // and the menu is for someone looking for a cone of light.
        Entry(strobe, "Spotlight", .light),
        Entry(spotCone, "Spot Cone", .light),
        Entry(sunRay, "Sun Ray", .light),
        Entry(sunFan, "Sun Fan", .light),
        Entry(godRays, "God Rays", .light),
        Entry(stageLights, "Stage Lights", .light),

        Entry(dandelion, "Dandelion", .nature),
        Entry(dandelionTall, "Dandelion Tall", .nature),
        Entry(dandelionDroop, "Dandelion Droop", .nature),
        Entry(dandelionHalf, "Dandelion Half", .nature),
        Entry(dandelionSeed, "Dandelion Seed", .nature),
        Entry(dandelionSeeds, "Dandelion Seeds", .nature),
    ]

    /// The catalogue entry for a stored path, if it is a built-in.
    static func entry(for path: String) -> Entry? {
        catalogueByPath[path]
    }

    private static let catalogueByPath: [String: Entry] =
        Dictionary(uniqueKeysWithValues: catalogue.map { ($0.path, $0) })

    /// Entries matching a search and a group, in catalogue order.
    ///
    /// The search reads the title and the group's name, case-insensitively:
    /// someone typing "fire" wants the Fire group as much as a sprite with the
    /// word in its name. With a search, the group filter steps aside — the
    /// search is for when the name is already known, wherever it lives.
    static func entries(matching search: String, in group: Group?) -> [Entry] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            return catalogue.filter {
                $0.title.lowercased().contains(query) || $0.group.rawValue.lowercased().contains(query)
            }
        }
        guard let group else { return catalogue }
        return catalogue.filter { $0.group == group }
    }
}
