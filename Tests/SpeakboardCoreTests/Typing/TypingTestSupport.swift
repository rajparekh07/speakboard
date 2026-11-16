@testable import SpeakboardCore

/// The estimated timings, which the engine uses by default. Tests take every time from here, as a fraction or a
/// multiple of a window, never as a number of their own.
let timings = TypingTimings.estimated

/// A text field as iOS shows it to a keyboard: the text before the cursor and the field's traits. It applies the
/// engine's output the way the keyboard extension does on iOS: `deleteCount` backward deletes of one character
/// (grapheme cluster) each, which do nothing at the start of the text, then the insertion.
struct Field {
    var text = ""
    var textAfterCursor = ""
    var autocapitalization = Autocapitalization.sentences
    var returnKeyType = ReturnKeyType.default
    var enablesReturnKeyAutomatically = false

    var context: TypingContext {
        TypingContext(
            textBeforeCursor: text, documentHasText: !text.isEmpty || !textAfterCursor.isEmpty,
            autocapitalization: autocapitalization, returnKeyType: returnKeyType,
            enablesReturnKeyAutomatically: enablesReturnKeyAutomatically)
    }

    mutating func apply(_ output: TypingOutput) {
        var remaining = output.deleteCount
        while remaining > 0 && !text.isEmpty {
            text.removeLast()
            remaining -= 1
        }
        text += output.insertion
    }
}

/// An engine and a field, driven by key events at given times.
struct Typist {
    var engine: TypingEngine
    var field: Field
    /// The time of the last event.
    var time = 100.0

    init(
        _ field: Field = Field(), settings: TypingSettings = TypingSettings(), locale: KeyboardLocale = .english,
        timings: TypingTimings = timings
    ) {
        guard let engine = TypingEngine(locale: locale, settings: settings, timings: timings) else {
            preconditionFailure("no typing rules for \(locale.identifier)")
        }
        self.engine = engine
        self.field = field
        _ = press(.contextChanged, after: 0)
    }

    var text: String { field.text }
    var shift: ShiftState { engine.shiftState }

    /// Sends `event` `delay` seconds after the last event, applies the output to the field, and returns it.
    @discardableResult
    mutating func press(_ event: KeyEvent, after delay: Double = 1) -> TypingOutput {
        press(event, at: time + delay)
    }

    /// Sends `event` at `time`, which may be earlier than the last event, applies the output and returns it.
    @discardableResult
    mutating func press(_ event: KeyEvent, at time: Double) -> TypingOutput {
        self.time = time
        let output = engine.handle(event, at: time, in: field.context)
        field.apply(output)
        return output
    }

    /// Types `characters` one key a second apart (slower than every window): a space is the space bar, "\n" is
    /// Return, and anything else is a character key with that lowercase character.
    mutating func type(_ characters: String, every delay: Double = 1) {
        for scalar in characters.unicodeScalars {
            switch scalar {
            case " ": press(.space, after: delay)
            case "\n": press(.returnKey, after: delay)
            default: press(.character(scalar), after: delay)
            }
        }
    }
}
