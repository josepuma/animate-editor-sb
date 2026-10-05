import CoreGraphics
import DesignSystem
import SwiftUI

/// An effect, filter or preset in the library, shown as what it draws.
///
/// The frames are the renderer's own preview of it (`EffectThumbnails`), held
/// still at rest and **playing under the pointer**: a grid of forty previews
/// all moving is a wall of noise, and the one under the hand is the one being
/// asked about.
///
/// With no frames yet — they are rendered on demand — the card shows a flat
/// placeholder with its glyph, so the grid never shows a broken tile.
package struct EffectPreviewCard: View {
    private let title: String
    private let systemImage: String
    private let tint: Color
    private let frames: [CGImage]
    private let isSelected: Bool
    private let action: () -> Void

    @State private var isHovered = false

    /// - Parameters:
    ///   - systemImage: the item's type, shown as a badge so a preset and the
    ///     effect it belongs to are told apart at a glance.
    ///   - tint: the placeholder glyph's colour while there are no frames.
    package init(
        title: String,
        systemImage: String,
        tint: Color,
        frames: [CGImage] = [],
        isSelected: Bool = false,
        action: @escaping () -> Void = {},
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.frames = frames
        self.isSelected = isSelected
        self.action = action
    }

    package var body: some View {
        MediaTile(title: title, isSelected: isSelected, action: action) {
            if frames.isEmpty {
                ArtworkPlaceholder(systemImage: systemImage, tint: tint)
            } else {
                // Over the stage's black: a preview is a picture of the stage,
                // and its transparent edges should read as the stage too.
                ZStack {
                    Theme.Palette.stage
                    FrameSequence(frames, isPlaying: isHovered || isSelected)
                }
            }
        } accessory: {
            Image(systemName: systemImage)
                .font(Theme.Typography.micro)
                .foregroundStyle(.white)
                .frame(width: Theme.Size.controlTiny, height: Theme.Size.controlTiny)
                .background(Circle().fill(.black.opacity(0.45)))
        }
        .onHover { isHovered = $0 }
    }
}
