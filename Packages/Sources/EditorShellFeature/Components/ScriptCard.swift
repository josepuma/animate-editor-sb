import DesignSystem
import SwiftUI

/// A script file, as a card in the scripts panel.
///
/// Clicking it places another clip that runs the file; its edit button opens
/// the file in the code editor.
///
/// A script has no picture of its own until it runs, so the card shows **the
/// code**: its first lines, cut off by the card's edge. That is what tells two
/// scripts apart at a glance — a file name is something you read, the shape of
/// the code is something you recognise.
package struct ScriptCard: View {
    /// What happened the last time the script ran.
    package enum Status: Equatable {
        /// Ran without failing.
        case ready
        /// Threw, with the engine's message.
        case failed(String)
        /// The file the clip names is not in the beatmap folder.
        case missing
    }

    private let fileName: String
    /// The name without its extension — what renaming edits, so nobody has to
    /// remember to keep the `.js` (and cannot type a second one by accident).
    private let editableName: String
    private let snippet: [String]
    private let status: Status
    private let clipCount: Int
    private let tint: Color
    private let isSelected: Bool
    private let action: () -> Void
    private let rename: ((String) -> Void)?
    private let openInEditor: (() -> Void)?

    @State private var isHovered = false
    @State private var isRenaming = false
    @State private var draft = ""
    @FocusState private var isNameFocused: Bool

    /// - Parameters:
    ///   - snippet: the first few lines of the file. More than five are
    ///     clipped.
    ///   - clipCount: how many clips name this file. Shown because editing a
    ///     shared file reloads every one of them, and an edit with more reach
    ///     than expected is the one nobody notices until the second clip looks
    ///     wrong.
    ///   - rename: makes the name editable — from the card's menu or a double
    ///     click on it — with the new name, extension left off.
    ///   - openInEditor: offers "Open in Editor" on the card's menu.
    package init(
        fileName: String,
        editableName: String? = nil,
        snippet: [String],
        status: Status,
        clipCount: Int,
        tint: Color,
        isSelected: Bool = false,
        action: @escaping () -> Void = {},
        rename: ((String) -> Void)? = nil,
        openInEditor: (() -> Void)? = nil,
    ) {
        self.fileName = fileName
        self.editableName = editableName ?? fileName
        self.snippet = snippet
        self.status = status
        self.clipCount = clipCount
        self.tint = tint
        self.isSelected = isSelected
        self.action = action
        self.rename = rename
        self.openInEditor = openInEditor
    }

    package var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)

        // A tap target rather than a `Button`: the name turns into a text
        // field while renaming, and a field inside a button fights it for
        // every click.
        VStack(alignment: .leading, spacing: 0) {
            header
            footer
        }
        .background(Theme.Tone.raised)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(
                isSelected ? Theme.Palette.accent
                    : (isHovered ? Theme.Border.cardHovered : Theme.Border.card),
                lineWidth: isSelected ? Theme.Size.ring * 1.5 : Theme.Size.hairline,
            )
        }
        .contentShape(shape)
        .onTapGesture { if !isRenaming { action() } }
        .contextMenu {
            Button("Add to Timeline", systemImage: "plus", action: action)
            if let openInEditor {
                Button("Open in Editor", systemImage: "arrow.up.forward.app", action: openInEditor)
            }
            if rename != nil {
                Button("Rename…", systemImage: "pencil") { beginRenaming() }
            }
        }
        .onHover { isHovered = $0 }
        .animation(Theme.Motion.quick, value: isHovered)
    }

    private var header: some View {
        ZStack(alignment: .topLeading) {
            Theme.Tone.well

            VStack(alignment: .leading, spacing: Theme.Spacing.hair) {
                ForEach(Array(snippet.prefix(5).enumerated()), id: \.offset) { _, line in
                    Text(line.isEmpty ? " " : line)
                        .font(Theme.Typography.code)
                        .foregroundStyle(Theme.Palette.secondary)
                        .lineLimit(1)
                }
            }
            .padding(Theme.Spacing.compact)
        }
        .frame(height: Theme.Size.cardArtwork)
        .clipped()
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.snug) {
            // The status as a dot, its detail in the tooltip. A line of
            // "342 sprites" or an engine message on every card was text nobody
            // came to the scripts panel to read; the colour alone says whether
            // something needs a look, and the message is one hover away.
            Circle()
                .fill(statusTint)
                .frame(width: Theme.Spacing.snug, height: Theme.Spacing.snug)
                .help(statusText)

            if isRenaming {
                TextField("Name", text: $draft)
                    .textFieldStyle(.plain)
                    .font(Theme.Typography.code)
                    .foregroundStyle(Theme.Palette.primary)
                    .focused($isNameFocused)
                    // Enter or a click elsewhere commits — clicking away is how
                    // a field is left, and a name that needs Enter is a name
                    // that gets lost. Escape puts the old one back.
                    .onSubmit(commitRename)
                    .onExitCommand(perform: cancelRename)
                    .onChange(of: isNameFocused) { _, focused in
                        if !focused, isRenaming { commitRename() }
                    }
            } else {
                Text(fileName)
                    .font(Theme.Typography.code)
                    .foregroundStyle(Theme.Palette.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .onTapGesture(count: 2) { beginRenaming() }
            }

            Spacer(minLength: 0)

            // Shown under the pointer: on every card at rest a row of buttons
            // crowds the code that tells the cards apart. Its own control, not
            // the card's click, which places a clip — the two things anyone
            // does with a script are both one click away.
            if let openInEditor {
                let shows = isHovered && !isRenaming
                IconButton(
                    systemImage: "square.and.pencil",
                    size: Theme.Size.controlTiny,
                    help: "Edit in the code editor",
                    action: openInEditor,
                )
                // Always laid out, only faded: appearing in the row pushed the
                // name and the ×N aside on every hover, so the card's contents
                // jumped under the pointer.
                .opacity(shows ? 1 : 0)
                .allowsHitTesting(shows)
            }

            if clipCount > 1 {
                Text("×\(clipCount)")
                    .font(Theme.Typography.readout)
                    .foregroundStyle(Theme.Palette.tertiary)
                    .help("Shared by \(clipCount) clips — editing the file reloads all of them")
            }
        }
        .padding(Theme.Spacing.compact)
    }

    private var statusTint: Color {
        switch status {
        case .ready: Theme.Palette.accent
        case .failed: Theme.Palette.danger
        case .missing: Theme.Palette.warning
        }
    }

    private var statusText: String {
        switch status {
        case .ready: "Last run succeeded"
        case let .failed(message): message
        case .missing: "File not found"
        }
    }

    // ─── Renaming ────────────────────────────────────────────────────────────

    private func beginRenaming() {
        guard rename != nil else { return }
        draft = editableName
        isRenaming = true
        isNameFocused = true
    }

    private func commitRename() {
        guard isRenaming else { return }
        isRenaming = false
        isNameFocused = false
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        // Unchanged or emptied is not a rename: an accidental double click
        // followed by a click away must not touch the file.
        guard !name.isEmpty, name != editableName else { return }
        rename?(name)
    }

    /// Leaves the name as it was and hands the keyboard back — a field that
    /// keeps focus after Escape is how the space bar ends up typing instead
    /// of playing.
    private func cancelRename() {
        isRenaming = false
        isNameFocused = false
    }
}
