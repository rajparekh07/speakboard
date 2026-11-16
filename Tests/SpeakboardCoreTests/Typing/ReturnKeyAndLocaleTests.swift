import Testing

@testable import SpeakboardCore

@Suite("Typing: the Return key")
struct ReturnKeyTests {
    @Test("Return inserts a line break for every kind, and reports the kind", arguments: ReturnKeyType.allCases)
    func everyKind(kind: ReturnKeyType) {
        var typist = Typist(Field(text: "hi", returnKeyType: kind))
        #expect(typist.engine.returnKey(in: typist.field.context) == ReturnKeyState(kind: kind, isEnabled: true))
        #expect(typist.press(.returnKey) == TypingOutput(insertion: "\n"))
        #expect(typist.text == "hi\n")
    }

    @Test("Enabled automatically: disabled in an empty field, where a tap does nothing; enabled once it has text")
    func enablesAutomatically() {
        var typist = Typist(Field(returnKeyType: .search, enablesReturnKeyAutomatically: true))
        #expect(typist.engine.returnKey(in: typist.field.context) == ReturnKeyState(kind: .search, isEnabled: false))
        #expect(typist.press(.returnKey) == TypingOutput())
        #expect(typist.text == "")
        #expect(typist.shift == .automatic)

        typist.type("a")
        #expect(typist.engine.returnKey(in: typist.field.context).isEnabled)
        #expect(typist.press(.returnKey) == TypingOutput(insertion: "\n"))

        typist.press(.deleteDown)
        typist.press(.deleteUp)
        typist.press(.deleteDown)
        #expect(typist.text == "")
        #expect(!typist.engine.returnKey(in: typist.field.context).isEnabled)
    }

    @Test("Enabled automatically, with text only after the cursor: enabled")
    func textAfterCursor() {
        let typist = Typist(Field(textAfterCursor: "later", enablesReturnKeyAutomatically: true))
        #expect(typist.engine.returnKey(in: typist.field.context).isEnabled)
    }

    @Test("Not enabled automatically: enabled in an empty field")
    func notAutomatic() {
        var typist = Typist(Field())
        #expect(typist.engine.returnKey(in: typist.field.context).isEnabled)
        #expect(typist.press(.returnKey) == TypingOutput(insertion: "\n"))
    }

    @Test("A disabled Return still ends a pending double tap on Shift (it is a key)")
    func disabledReturnIsAKey() {
        var typist = Typist(Field(autocapitalization: .none, enablesReturnKeyAutomatically: true))
        let gap = timings.shiftDoubleTapWindow / 4
        typist.press(.shift)
        typist.press(.returnKey, after: gap)
        typist.press(.shift, after: gap)
        #expect(typist.shift == .off)
    }
}

@Suite("Typing: locale")
struct TypingLocaleTests {
    @Test(
        "English and its regional variants get the English rules",
        arguments: ["en", "en-US", "en_GB", "en@calendar=gregorian", "EN"])
    func english(identifier: String) {
        let engine = TypingEngine(locale: LayoutLocale(identifier: identifier))
        #expect(engine?.locale == .english)
    }

    @Test("A locale with no rules, or no language, gets no engine", arguments: ["fr", "fr-CA", "", "-en"])
    func noRules(identifier: String) {
        #expect(TypingEngine(locale: LayoutLocale(identifier: identifier)) == nil)
    }

    @Test("The rules are data per locale, and English is the only locale with rules")
    func rulesAreData() {
        #expect(Array(TypingRules.byLocale.keys) == [.english])
        for locale in TypingRules.byLocale.keys {
            #expect(KeyboardLayout(locale: locale, deviceClass: .iphone390x844, orientation: .portrait) != nil)
        }
    }

    @Test("The engine is a value: a copy forks its state, and the same events give the same output")
    func pureValue() throws {
        var first = try #require(TypingEngine(locale: .english))
        let context = TypingContext(textBeforeCursor: "hi")
        _ = first.handle(.shift, at: 1, in: context)
        var second = first
        #expect(first.handle(.character("a"), at: 2, in: context) == TypingOutput(insertion: "A"))
        #expect(second.handle(.character("a"), at: 2, in: context) == TypingOutput(insertion: "A"))
        #expect(first.shiftState == second.shiftState)
    }
}
