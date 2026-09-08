import DesignSystem
import SwiftUI

/// One line of a script's output.
struct OutputLine: View {
    enum Tone {
        case plain
        case warning
        case error
    }

    let text: String
    let tone: Tone

    var body: some View {
        Text(text)
            .font(Theme.Typography.micro)
            .foregroundStyle(colour)
            .textSelection(.enabled)
            // Wrapped rather than truncated: a logged object or a parse error
            // says what went wrong in its tail, which is exactly the part an
            // ellipsis removes.
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var colour: Color {
        switch tone {
        case .plain: Theme.Palette.secondary
        case .warning: Theme.Palette.warning
        case .error: Theme.Palette.danger
        }
    }
}
