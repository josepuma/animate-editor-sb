# Examples

Scripts that show what the scripting effect is for, kept as reference rather
than as scratch work.

## `scripts/`

JavaScript for a script clip. Paste one into a script effect's editor and press
⌘S to run it.

| | What it shows |
|---|---|
| `wave-mesh.js` | A mesh deformed by two crossing sine waves. Every dot takes its own phase from where it sits in the grid and its own brightness from how steep the surface is under it — per-particle rules with access to the index, which is the reason scripts exist at all. |

**These run in the test suite** (`ExampleScriptTests`), and the guards check
what each script's own comments claim, not merely that it drew something. An
example nobody runs is one that can name a renamed method or a misspelled
easing and go on looking fine — which already happened to the initial template,
where the easings were spelled the wrong way round and the only test asserted
that it drew. It did, in silence, as linear.

So a script here is not free to rot: renaming part of the API breaks these, and
that is the point of keeping them in the repo instead of in a scratchpad.
