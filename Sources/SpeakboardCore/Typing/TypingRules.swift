// The typing rules, as data: one entry per locale (ADR-0010). English is the
// only locale with rules. A locale with no rules of its own uses its
// language's, the same way as the letters layout (LayoutLocale.entry(in:)):
// "en-US", "en_GB" and "EN" all get the "en" rules. A later language adds an
// entry here; the engine's code does not change.
//
// What is not per locale, because it is Unicode's: which characters are
// whitespace (the White_Space property), letters (Alphabetic) and digits
// (Numeric_Type), and how a letter is uppercased (Unicode's default case
// mapping). A language whose case mapping differs from Unicode's default, such
// as Turkish dotted and dotless i, needs a mapping added here.
//
// Every rule below is recalled behaviour of Apple's English keyboard, not
// measured. Apple documents only that "the first letter of a sentence in a
// case-sensitive language is automatically capitalized" (Custom Keyboard guide)
// and what each UITextAutocapitalizationType case means; it does not say what
// ends a sentence.

/// The characters the typing engine reads to find a sentence's end and a word's start, for one locale.
struct TypingRules: Sendable {
    /// Characters that end a sentence, when whitespace follows them.
    let sentenceTerminators: [Unicode.Scalar]
    /// Closing quotes and brackets, which may stand between a sentence's terminator and the whitespace after it
    /// (`"Hi." He`), or after the word before a double space (`"hi"` then two spaces).
    let closers: [Unicode.Scalar]
    /// Opening quotes and brackets, which may stand between the start of a sentence or word and the insertion
    /// point (`Hi. "W`).
    let openers: [Unicode.Scalar]
    /// What a double space types in place of its first space: the locale's full stop and a space.
    let doubleSpaceInsertion: String

    /// The rules per locale.
    static let byLocale: [LayoutLocale: TypingRules] = [
        // Recalled, not measured.
        .english: TypingRules(
            sentenceTerminators: [".", "!", "?"],
            closers: [")", "]", "}", "\"", "'", "\u{201D}", "\u{2019}"],
            openers: ["(", "[", "{", "\"", "'", "\u{201C}", "\u{2018}"],
            doubleSpaceInsertion: ". ")
    ]
}

extension Array where Element == Unicode.Scalar {
    /// Whether the array holds `scalar`. A `while` loop over indices, not `contains` or `for`-`in`, which call
    /// generic iterator code that allocates in a debug build.
    func has(_ scalar: Unicode.Scalar) -> Bool {
        var index = 0
        while index < count {
            if self[index] == scalar { return true }
            index += 1
        }
        return false
    }
}
