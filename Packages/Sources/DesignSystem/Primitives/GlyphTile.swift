import SwiftUI

/// A small rounded square in its tint carrying a glyph or a letter — the row's
/// picture.
///
/// What a list row was missing. A coloured dot a point and a half wide says
/// "this has a colour"; a tile says "this is a thing", the way an app icon does
/// in a dock — and it is what makes a list read like the previews above it
/// rather than like a spreadsheet.
public struct GlyphTile: View {
    private enum Mark {
        case symbol(String)
        case text(String)
    }

    private let mark: Mark
    private let tint: Color?
    private let size: CGFloat

    /// - Parameter tint: `nil` for a neutral tile — a thing with no colour of
    ///   its own still gets a picture, just a quiet one.
    public init(systemImage: String, tint: Color?, size: CGFloat = Theme.Size.controlSmall) {
        mark = .symbol(systemImage)
        self.tint = tint
        self.size = size
    }

    /// A tile showing the first letter of `name` — for things named by the
    /// user, which have no glyph of their own.
    public init(initialOf name: String, tint: Color?, size: CGFloat = Theme.Size.controlSmall) {
        mark = .text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
        self.tint = tint
        self.size = size
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * Self.cornerRatio, style: .continuous)

        ZStack {
            // Flat: the tile's colour is information — which lane, which
            // family — and a gradient on it would be decoration.
            shape.fill(tint ?? Theme.Tone.well)

            switch mark {
            case let .symbol(name):
                Image(systemName: name)
                    .font(.system(size: (size * Self.glyphRatio).rounded(), weight: .semibold))
            case let .text(letter):
                Text(letter)
                    .font(.custom(Theme.FontFace.semibold, size: (size * Self.glyphRatio).rounded()))
            }
        }
        .foregroundStyle(tint == nil ? Theme.Palette.secondary : Color.white)
        .frame(width: size, height: size)
    }

    /// Proportional rather than fixed, for the reason `IconButton` gives: one
    /// glyph size cannot leave the same air in a 22pt tile and a 44pt one.
    private static let glyphRatio: CGFloat = 0.46
    /// Rounder than a button's corner relative to its size: a tile this small
    /// with a button's radius reads as a square with nicked corners.
    private static let cornerRatio: CGFloat = 0.3
}
