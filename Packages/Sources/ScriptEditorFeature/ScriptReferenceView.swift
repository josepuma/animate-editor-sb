import DesignSystem
import SwiftUI

/// The scripting API, as a page somebody can read.
///
/// Generated from `ScriptAPI` rather than written beside it, so it cannot go
/// out of date: the same table feeds the completion list, the highlighter's
/// reserved words and this. A hand-written reference is a fourth copy of the
/// same facts, and the second copy in this project was already wrong — all
/// thirty-five easing names were spelled backwards.
///
/// A window rather than a file in the repo. The question "what can a script
/// call" arrives *while* somebody is writing one, and a Markdown file in a
/// checkout is not where they are looking.
public struct ScriptReferenceView: View {
    @State private var search = ""

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().overlay(Theme.Border.panel)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.regular) {
                    localTime
                    controls

                    ForEach(sections, id: \.title) { section in
                        if !section.entries.isEmpty {
                            SectionBlock(section: section)
                        }
                    }

                    if sections.allSatisfy(\.entries.isEmpty) {
                        Text("Nothing matches")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Palette.tertiary)
                    }

                    absences
                }
                .padding(Theme.Spacing.regular)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .background(Theme.Palette.stage)
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.compact) {
            Text("Scripting")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.primary)

            Spacer()

            TextInputField(text: $search, placeholder: "Search")
                .frame(width: 180)
        }
        .padding(Theme.Spacing.regular)
    }

    /// The one thing worth reading before anything else.
    ///
    /// "Where is `startTime`?" is the first question anybody asks, and the
    /// answer is a design decision rather than a missing feature — so it is at
    /// the top rather than in a note somebody finds later.
    @ViewBuilder
    private var localTime: some View {
        if search.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                SectionHeader("Time is local")

                Text(
                    """
                    A script generates over `0...duration`. Zero is where the clip starts, whatever the timeline says — the song's own clock is not something a script can read, and there is no `startTime`.

                    That is what makes dragging a clip safe: it moves the same sprites rather than generating different ones. Write an effect once and put it anywhere, or copy it to another moment in the song, and it animates identically.

                    It is the same rule the rest of the effects follow, and the same one After Effects follows: a composition does not know where it is nested.
                    """
                )
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.secondary)
                .textSelection(.enabled)

                Divider().overlay(Theme.Border.panel)
            }
        }
    }

    /// How a control gets into the inspector.
    ///
    /// Two calls that need each other, listed alphabetically as `param` and
    /// `params` — so the first thing anybody read was how to *read* a control
    /// that did not exist yet. Reported exactly that way: "you had to declare
    /// it first, the help did not explain that well".
    ///
    /// Its own section, above the lists, because the relationship is the part
    /// that matters and an alphabetical list cannot express one.
    @ViewBuilder
    private var controls: some View {
        if search.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                SectionHeader("Controls come in two halves")

                Text(
                    """
                    `params()` DECLARES a control and puts it in the inspector.                     `param(id)` READS one back. Reading without declaring gives                     `undefined` and no control appears — which looks exactly                     like a control that failed to show up.

                    Declare once at the top, then read wherever you need it:
                    """
                )
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.secondary)
                .textSelection(.enabled)

                Text(
                    """
                    params({
                      count: { type: 'integer', default: 24, range: [1, 200] },
                      tint:  { type: 'color',   default: '#ff8844' },
                    })

                    const count = param('count')
                    """
                )
                .font(Theme.Typography.readout)
                .foregroundStyle(Theme.Palette.primary)
                .textSelection(.enabled)
                .padding(Theme.Spacing.compact)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Theme.Fill.well,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.small),
                )

                Text(
                    """
                    With a declaration the default is guaranteed, so `?? 24` is not needed. Reading an id that was never declared says so rather than quietly giving `undefined`.
                    """
                )
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.secondary)
                .textSelection(.enabled)

                // The six types, as a table rather than a sentence.
                //
                // They were listed inside a paragraph — `number`, `integer`,
                // `toggle`… — which is a list somebody has to parse out of
                // prose while trying to write a declaration. Asked for
                // directly, twice, which is what a buried answer looks like.
                Text(
                    """
                    number    a decimal        default: 1.5
                    integer   a whole number   default: 24
                    toggle    a switch         default: true
                    choice    a menu           default: 'ring'  + options: ['ring', 'disc']
                    color     a colour well    default: '#ff8844'
                    text      a text field     default: 'sb/a.png'

                    range: [1, 200]    makes it a slider; without one it is a field
                    step: 0.05         how far one nudge moves it
                    unit: 'px'         shown after the value
                    name: 'How many'   overrides the title, otherwise taken from the id
                    group: 'Shape'     which heading it sits under
                    """
                )
                .font(Theme.Typography.readout)
                .foregroundStyle(Theme.Palette.secondary)
                .textSelection(.enabled)
                .padding(Theme.Spacing.compact)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Theme.Fill.well,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.small),
                )

                Text(
                    """
                    There is no `path` type: a motion path is drawn on the canvas with the pen, not written in a declaration.
                    """
                )
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.tertiary)
                .textSelection(.enabled)

                Divider().overlay(Theme.Border.panel)
            }
        }
    }

    /// What the language deliberately does not have.
    ///
    /// Documented as prominently as what it does. Somebody reaching for
    /// `Date.now()` will find nothing and assume a bug rather than a decision,
    /// and the reason — that a fresh number breaks the agreement between the
    /// preview and the exported file — is the kind of thing only the docs can
    /// say.
    @ViewBuilder
    private var absences: some View {
        if search.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                SectionHeader("Not available")

                Text(
                    """
                    No `Date`, `performance` or `crypto`: a clock reads differently on every run, so a script using one would draw a preview that does not match the file it exports.

                    No `fetch`, `require` or `process`: a script has no way to reach the disk or the network, which is what makes running one safe.

                    `Math.random` exists but is seeded from the clip, so it gives the same field every time. Use `rng` — it says so.
                    """
                )
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.secondary)
                .textSelection(.enabled)
            }
        }
    }

    // MARK: - Content

    private struct Section {
        let title: String
        let detail: String
        let entries: [ScriptAPI.Entry]
    }

    private var sections: [Section] {
        [
            Section(
                title: "Globals",
                detail: "In scope everywhere in a script.",
                entries: ScriptAPI.globals.matching(search),
            ),
            Section(
                title: "Sprite commands",
                detail: "Chained on whatever `sprite()` returns. The easing is optional, and the times come before the values.",
                entries: ScriptAPI.spriteMethods.matching(search),
            ),
            Section(
                title: "Image",
                detail: "The shapes the app provides. Any other path is read from the beatmap folder.",
                entries: ScriptAPI.images.matching(search),
            ),
            Section(
                title: "Ease",
                detail: "Every curve the format has. Family first, direction after — `quadOut`, not `outQuad`.",
                entries: ScriptAPI.easings.matching(search),
            ),
            Section(
                title: "rng",
                detail: "Seeded from the clip, so two evaluations agree.",
                entries: ScriptAPI.randomMethods.matching(search),
            ),
            Section(
                title: "Layer",
                detail: "Which layer a sprite draws on. The track decides by default.",
                entries: ScriptAPI.layers.matching(search),
            ),
            Section(
                title: "Origin",
                detail: "Which point of a sprite its position refers to.",
                entries: ScriptAPI.origins.matching(search),
            ),
            Section(
                title: "console",
                detail: "Present so a script that logs does not die. Goes nowhere yet.",
                entries: ScriptAPI.consoleMethods.matching(search),
            ),
        ]
    }

    private struct SectionBlock: View {
        let section: Section

        var body: some View {
            VStack(alignment: .leading, spacing: Theme.Spacing.snug) {
                SectionHeader(section.title)

                Text(section.detail)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.tertiary)

                ForEach(section.entries, id: \.name) { entry in
                    EntryRow(entry: entry)
                }
            }
        }
    }

    private struct EntryRow: View {
        let entry: ScriptAPI.Entry

        var body: some View {
            VStack(alignment: .leading, spacing: Theme.Spacing.hair) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.compact) {
                    Text(entry.name)
                        .font(Theme.Typography.readout)
                        .foregroundStyle(Theme.Palette.primary)

                    Text(entry.summary)
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.secondary)
                }

                if let example = entry.example {
                    Text(example)
                        .font(Theme.Typography.readout)
                        .foregroundStyle(Theme.Palette.secondary)
                        .textSelection(.enabled)
                        .padding(Theme.Spacing.compact)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            Theme.Fill.well,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.small),
                        )
                }
            }
            .padding(.bottom, Theme.Spacing.tight)
        }
    }
}

private extension [ScriptAPI.Entry] {
    /// Matched on the name *or* the summary.
    ///
    /// Somebody looking for "how do I tint something" types "colour", which is
    /// in a summary and not in a name — a search that only reads names sends
    /// them away from the page that has the answer.
    func matching(_ search: String) -> [ScriptAPI.Entry] {
        guard !search.isEmpty else { return self }
        let needle = search.lowercased()
        return filter {
            $0.name.lowercased().contains(needle) || $0.summary.lowercased().contains(needle)
        }
    }
}
