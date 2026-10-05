import SwiftUI

/// A count in a small pill — how many presets, how many keys, how many uses.
///
/// A bare number trailing a row reads as part of its name; in a pill it reads
/// as a property of the row. Accented when what it counts is *live* (keys that
/// are animating), quiet otherwise.
public struct CountBadge: View {
    private let text: String
    private let isAccented: Bool

    public init(_ count: Int, isAccented: Bool = false) {
        text = "\(count)"
        self.isAccented = isAccented
    }

    public init(_ text: String, isAccented: Bool = false) {
        self.text = text
        self.isAccented = isAccented
    }

    public var body: some View {
        Text(text)
            .font(Theme.Typography.readout)
            .foregroundStyle(isAccented ? Theme.Palette.onAccent : Theme.Palette.secondary)
            .padding(.horizontal, Theme.Spacing.snug)
            .padding(.vertical, Theme.Spacing.hair)
            .background(Capsule(style: .continuous).fill(isAccented ? Theme.Palette.accent : Theme.Tone.well))
    }
}
