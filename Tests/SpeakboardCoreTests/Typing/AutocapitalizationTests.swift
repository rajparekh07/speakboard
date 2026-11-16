import Testing

@testable import SpeakboardCore

@Suite("Typing: auto-capitalisation")
struct AutocapitalizationTests {
    /// The Shift state the engine reads from `text` in a field of `type`, as when the cursor is put there.
    static func shift(after text: String, _ type: Autocapitalization, settings: TypingSettings = TypingSettings())
        -> ShiftState
    {
        Typist(Field(text: text, autocapitalization: type), settings: settings).shift
    }

    @Test("An empty field: on for sentences, words and all characters, off for none")
    func emptyField() {
        #expect(Self.shift(after: "", .sentences) == .automatic)
        #expect(Self.shift(after: "", .words) == .automatic)
        #expect(Self.shift(after: "", .allCharacters) == .automatic)
        #expect(Self.shift(after: "", .none) == .off)
    }

    @Test(
        "Sentences: on after a terminator and whitespace",
        arguments: ["Hi. ", "Hi! ", "Hi? ", "Hi.  ", "Hi.\t", "e.g. ", "1. "])
    func sentenceEnds(text: String) {
        #expect(Self.shift(after: text, .sentences) == .automatic)
    }

    @Test(
        "Sentences: off mid-sentence, right after a terminator, and after other punctuation",
        arguments: ["Hi", "Hi ", "Hi.", "Hi, ", "Hi; ", "Hi: ", "Hi - ", "Hi.a", "3.5"])
    func notSentenceEnds(text: String) {
        #expect(Self.shift(after: text, .sentences) == .off)
    }

    @Test(
        "Sentences: closing quotes and brackets between the terminator and the space",
        arguments: ["He said \"hi.\" ", "(Really?) ", "\u{201C}Yes.\u{201D} ", "It's 'done.' ", "[Ok!]) "])
    func closers(text: String) {
        #expect(Self.shift(after: text, .sentences) == .automatic)
    }

    @Test(
        "Sentences: a closer with no terminator before it is not a sentence end",
        arguments: ["He said \"hi\" ", "(really) "])
    func closerWithoutTerminator(text: String) {
        #expect(Self.shift(after: text, .sentences) == .off)
    }

    @Test(
        "Sentences and words: an opening quote or bracket just before the cursor is skipped",
        arguments: ["\"", "(", "Hi. \"", "Hi. (", "Hi. \u{201C}", "Hi. (\""])
    func openers(text: String) {
        #expect(Self.shift(after: text, .sentences) == .automatic)
        #expect(Self.shift(after: text, .words) == .automatic)
    }

    @Test("Sentences: an opener after a word with no sentence end is not a sentence start")
    func openerMidSentence() {
        #expect(Self.shift(after: "hi \"", .sentences) == .off)
        #expect(Self.shift(after: "hi\"", .sentences) == .off)
    }

    @Test(
        "Sentences: on after a line break, with or without whitespace after it",
        arguments: ["hello\n", "hello\n  ", "hello\r\n", "hello\u{2028}", "hello,\n", "a\n\n"])
    func lineBreaks(text: String) {
        #expect(Self.shift(after: text, .sentences) == .automatic)
    }

    @Test("Sentences: text that is only whitespace is the start; only closers and whitespace is not (assumption)")
    func onlyWhitespaceOrClosers() {
        #expect(Self.shift(after: "   ", .sentences) == .automatic)
        #expect(Self.shift(after: ") ", .sentences) == .off)
    }

    @Test("Words: on after whitespace, off inside a word", arguments: ["hello ", "hello\n", "a, ", "hello \""])
    func wordStarts(text: String) {
        #expect(Self.shift(after: text, .words) == .automatic)
    }

    @Test("Words: off inside or right after a word", arguments: ["hello", "hello.", "don'"])
    func notWordStarts(text: String) {
        #expect(Self.shift(after: text, .words) == .off)
    }

    @Test("None: never on", arguments: ["", "Hi. ", "hello\n"])
    func none(text: String) {
        #expect(Self.shift(after: text, .none) == .off)
    }

    @Test("All characters: always on, and every letter is uppercase")
    func allCharacters() {
        #expect(Self.shift(after: "abc", .allCharacters) == .automatic)
        var typist = Typist(Field(autocapitalization: .allCharacters))
        typist.type("ny ca")
        #expect(typist.text == "NY CA")
        typist.press(.shift)
        typist.type("xy")
        #expect(typist.text == "NY CAxY")
    }

    @Test("The Auto-Capitalization setting off turns every type off, all characters too (assumption)")
    func settingOff() {
        let off = TypingSettings(autoCapitalization: false)
        for type in Autocapitalization.allCases {
            #expect(Self.shift(after: "", type, settings: off) == .off, "\(type)")
            #expect(Self.shift(after: "Hi. ", type, settings: off) == .off, "\(type)")
        }
    }

    @Test("Typing sentences capitalises their first letters, after an opening bracket too, and nothing else")
    func typingSentences() {
        var typist = Typist()
        typist.type("hello. how are you? fine\nthanks! (yes.) ok, e.g. this")
        #expect(typist.text == "Hello. How are you? Fine\nThanks! (Yes.) Ok, e.g. This")
    }

    @Test("Typing words capitalises each word")
    func typingWords() {
        var typist = Typist(Field(autocapitalization: .words))
        typist.type("jane q. public\nnew york")
        #expect(typist.text == "Jane Q. Public\nNew York")
    }

    @Test("A delete back to a sentence start turns Shift on; typing on turns it off")
    func afterDelete() {
        var typist = Typist(Field(text: "Hi. a"))
        #expect(typist.shift == .off)
        typist.press(.deleteDown)
        #expect(typist.text == "Hi. ")
        #expect(typist.shift == .automatic)
        typist.press(.deleteUp)
        typist.press(.deleteDown)
        #expect(typist.text == "Hi.")
        #expect(typist.shift == .off)
    }

    @Test("A context change reads the new context: the cursor moved to a sentence start, or away from one")
    func contextChange() {
        var typist = Typist(Field(text: "Hi"))
        #expect(typist.shift == .off)
        typist.field.text = "Hi. "
        typist.press(.contextChanged)
        #expect(typist.shift == .automatic)
        typist.field.text = "Hi"
        typist.press(.contextChanged)
        #expect(typist.shift == .off)
        typist.field.autocapitalization = .allCharacters
        typist.press(.contextChanged)
        #expect(typist.shift == .automatic)
    }
}
