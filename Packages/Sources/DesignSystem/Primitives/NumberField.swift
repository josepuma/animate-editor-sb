import SwiftUI

/// A numeric value that can be typed or stepped, with an optional unit.
public struct NumberField: View {
    @Binding private var value: Double
    private let unit: String?
    private let step: Double
    private let range: ClosedRange<Double>
    private let format: String

    /// What the field shows while it is being typed in.
    ///
    /// The bound value cannot hold this: half-typed input is not a number yet
    /// — "1." and "-" are both states a field passes through — and formatting
    /// the value back on every keystroke would fight whoever is typing.
    @State private var editing: String?
    @FocusState private var isFocused: Bool

    public init(
        value: Binding<Double>,
        unit: String? = nil,
        step: Double = 1,
        range: ClosedRange<Double> = -.infinity...(.infinity),
        format: String = "%.0f",
    ) {
        _value = value
        self.unit = unit
        self.step = step
        self.range = range
        self.format = format
    }

    public var body: some View {
        FieldWell(isFocused: isFocused) {
            HStack(spacing: Theme.Spacing.tight) {
                TextField(
                    "",
                    text: Binding(
                        get: { editing ?? String(format: format, value) },
                        set: { editing = $0 },
                    ),
                )
                .textFieldStyle(.plain)
                .font(Theme.Typography.readout)
                .foregroundStyle(Theme.Palette.secondary)
                .focused($isFocused)
                .onSubmit(commit)
                // Committing on focus loss as well as on return: clicking
                // straight into the next field is how a form is filled, and a
                // value that needs Enter to take is a value people lose.
                .onChange(of: isFocused) { _, focused in
                    if !focused { commit() }
                }
                // Escape abandons the edit and hands the keyboard back, which
                // is the way out for someone who clicked a field by accident.
                .onExitCommand {
                    editing = nil
                    isFocused = false
                }

                if let unit {
                    Text(unit)
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.tertiary)
                }

                Spacer(minLength: 0)

                Stepper(
                    "",
                    value: Binding(
                        get: { value },
                        set: { clamp($0) },
                    ),
                    step: step,
                )
                .labelsHidden()
                .controlSize(.mini)
            }
        }
    }

    /// Applies what was typed, or puts the old value back when it is not a
    /// number.
    ///
    /// Reverting rather than clearing: a typo should cost the typo, not the
    /// value that was there before it.
    private func commit() {
        defer {
            editing = nil
            // Handing focus back after a commit: a field that keeps it goes on
            // swallowing keystrokes meant for the app, and space — play/pause
            // in an editor — is a character as far as a text field is
            // concerned.
            isFocused = false
        }
        guard let text = editing else { return }

        let cleaned = text.trimmingCharacters(in: .whitespaces)
        guard let parsed = Double(cleaned) else { return }
        clamp(parsed)
    }

    private func clamp(_ newValue: Double) {
        value = min(max(range.lowerBound, newValue), range.upperBound)
    }
}

/// A single line of editable text in a field well.
///
/// Separate from `NumberField` rather than a mode of it: there is nothing to
/// parse, nothing to clamp and no stepper, and a field that handles both ends
/// up with half its body switched off in either case.
public struct TextInputField: View {
    @Binding private var text: String
    private let placeholder: String

    /// What is shown while typing, committed on return or on leaving the field.
    ///
    /// Writing through on every keystroke would be correct and unusable here: a
    /// path drives an effect, and re-evaluating it — thousands of sprites, and
    /// a texture load for a path that is still half typed — on each letter
    /// stalls the typing that caused it.
    @State private var editing: String?
    @FocusState private var isFocused: Bool

    public init(text: Binding<String>, placeholder: String = "") {
        _text = text
        self.placeholder = placeholder
    }

    public var body: some View {
        FieldWell(isFocused: isFocused) {
            TextField(
                placeholder,
                text: Binding(
                    get: { editing ?? text },
                    set: { editing = $0 },
                ),
            )
            .textFieldStyle(.plain)
            .font(Theme.Typography.micro)
            .foregroundStyle(Theme.Palette.secondary)
            .lineLimit(1)
            .focused($isFocused)
            .onSubmit(commit)
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
            .onExitCommand {
                editing = nil
                isFocused = false
            }
        }
    }

    private func commit() {
        defer {
            editing = nil
            isFocused = false
        }
        guard let edited = editing, edited != text else { return }
        text = edited
    }
}

/// A slider with its value shown alongside.
public struct SliderField: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let format: String

    public init(
        value: Binding<Double>,
        range: ClosedRange<Double> = 0...1,
        format: String = "%.2f",
    ) {
        _value = value
        self.range = range
        self.format = format
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.snug) {
            Slider(value: $value, in: range)
                .controlSize(.mini)

            Text(String(format: format, value))
                .font(Theme.Typography.readout)
                .foregroundStyle(Theme.Palette.secondary)
                // Fixed width so the slider does not jump as digits change.
                .frame(width: Theme.Size.valueReadout, alignment: .trailing)
        }
    }
}
