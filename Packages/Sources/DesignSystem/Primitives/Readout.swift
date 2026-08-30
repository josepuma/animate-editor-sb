import SwiftUI

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
