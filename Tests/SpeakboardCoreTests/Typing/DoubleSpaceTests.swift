import Testing

@testable import SpeakboardCore

@Suite("Typing: double-space full stop")
struct DoubleSpaceTests {
    /// Types two spaces `gap` seconds apart after `text`, and returns the field's text and the second output.
    static func doubleSpace(
        after text: String, gap: Double = timings.doubleSpaceWindow / 2, settings: TypingSettings = TypingSettings()
    ) -> (String, TypingOutput) {
        var typist = Typist(Field(text: text), settings: settings)
        // The spaces are at 0 and at the gap, so the engine's subtraction gives the gap exactly.
        typist.press(.space, at: 0)
        let second = typist.press(.space, at: gap)
        return (typist.text, second)
    }

    @Test("Two quick spaces after a word type a full stop and a space, and turn Shift on")
    func afterWord() {
        var typist = Typist(Field(text: "hi"))
        #expect(typist.press(.space) == TypingOutput(insertion: " "))
        let second = typist.press(.space, after: timings.doubleSpaceWindow / 2)
        #expect(second == TypingOutput(deleteCount: 1, insertion: ". "))
        #expect(typist.text == "hi. ")
        #expect(typist.shift == .automatic)
    }

    @Test(
        "After a letter, a digit, or closing quotes or brackets after one",
        arguments: ["hi", "Hi", "2", "\"hi\"", "(see 2)", "\u{201C}ok\u{201D}", "café", "hi\u{301}", "cafe\u{301}\""])
    func eligible(text: String) {
        #expect(Self.doubleSpace(after: text).0 == text + ". ")
    }

    @Test(
        "Not at the start, after whitespace, or after punctuation (assumption): two spaces",
        arguments: [
            "", "hi ", "hi\n", "hi.", "hi,", "hi!", "\"Hi.\"", "(", ")",
            // A Prepend character joins the space typed after it, so the text does not end with a plain space
            // (KEY-22 review round 2).
            "\u{600}", "hi\u{600}", "hi\u{D4E}", "x\u{110BD}",
        ])
    func notEligible(text: String) {
        let (result, second) = Self.doubleSpace(after: text)
        #expect(result == text + "  ")
        #expect(second == TypingOutput(insertion: " "))
    }

    @Test("The window: inside and at its end a full stop, just past it two spaces")
    func window() {
        #expect(Self.doubleSpace(after: "hi", gap: 0).0 == "hi. ")
        #expect(Self.doubleSpace(after: "hi", gap: timings.doubleSpaceWindow).0 == "hi. ")
        #expect(Self.doubleSpace(after: "hi", gap: timings.doubleSpaceWindow.nextUp).0 == "hi  ")
        #expect(Self.doubleSpace(after: "hi", gap: timings.doubleSpaceWindow * 10).0 == "hi  ")
    }

    @Test("Time going backwards between the spaces gives two spaces")
    func timeBackwards() {
        #expect(Self.doubleSpace(after: "hi", gap: -timings.doubleSpaceWindow / 2).0 == "hi  ")
        #expect(Self.doubleSpace(after: "hi", gap: .nan).0 == "hi  ")
    }

    @Test("The \".\" Shortcut setting off gives two spaces")
    func settingOff() {
        #expect(Self.doubleSpace(after: "hi", settings: TypingSettings(periodShortcut: false)).0 == "hi  ")
    }

    @Test("A third quick space after the full stop is a plain space")
    func thirdSpace() {
        var typist = Typist(Field(text: "hi"))
        let gap = timings.doubleSpaceWindow / 3
        typist.press(.space)
        typist.press(.space, after: gap)
        #expect(typist.press(.space, after: gap) == TypingOutput(insertion: " "))
        #expect(typist.text == "hi.  ")
    }

    @Test("Four quick spaces: a full stop, then two spaces")
    func fourSpaces() {
        var typist = Typist(Field(text: "hi"))
        let gap = timings.doubleSpaceWindow / 4
        for _ in 0..<4 { typist.press(.space, after: gap) }
        #expect(typist.text == "hi.   ")
    }

    @Test("Another key between the spaces cancels it")
    func keyBetween() {
        for event in [KeyEvent.shift, .character("a"), .deleteUp] {
            var typist = Typist(Field(text: "hi"))
            let gap = timings.doubleSpaceWindow / 4
            typist.press(.space)
            typist.press(event, after: gap)
            typist.field.text = "hi "
            typist.press(.space, after: gap)
            #expect(typist.text == "hi  ", "\(event)")
        }
    }

    @Test("A cursor moved between the spaces, so the text no longer ends with the space: a plain space")
    func cursorMoved() {
        var typist = Typist(Field(text: "hi"))
        let gap = timings.doubleSpaceWindow / 4
        typist.press(.space)
        typist.field.text = "hi there"
        typist.press(.contextChanged, after: gap)
        let second = typist.press(.space, after: gap)
        #expect(second == TypingOutput(insertion: " "))
        #expect(typist.text == "hi there ")
    }

    @Test("A mark joined to the first space before the second: no full stop, nothing deleted")
    func markedSpace() {
        for mark in ["\u{301}", "\u{FE0F}"] {
            var typist = Typist(Field(text: "hi"))
            let gap = timings.doubleSpaceWindow / 4
            typist.press(.space)
            typist.field.text += mark
            typist.press(.contextChanged, after: gap)
            #expect(typist.press(.space, after: gap) == TypingOutput(insertion: " "))
            #expect(typist.text == "hi " + mark + " ")
        }
    }

    @Test("Typing with double spaces makes sentences")
    func typing() {
        var typist = Typist()
        let gap = timings.doubleSpaceWindow / 2
        typist.type("one")
        typist.press(.space)
        typist.press(.space, after: gap)
        typist.type("two")
        #expect(typist.text == "One. Two")
    }
}
