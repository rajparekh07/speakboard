import Testing

@testable import SpeakboardCore

@Suite("Typing: delete and its acceleration")
struct DeleteTests {
    /// Estimated timings, but with one character repeat, so a hold reaches whole words at its second repeat.
    static let quickWords = TypingTimings(
        shiftDoubleTapWindow: timings.shiftDoubleTapWindow, doubleSpaceWindow: timings.doubleSpaceWindow,
        deleteInitialDelay: timings.deleteInitialDelay, deleteRepeatInterval: timings.deleteRepeatInterval,
        deleteCharacterRepeats: 1, deleteWordRepeatInterval: timings.deleteWordRepeatInterval)

    /// Holds Delete and sends a tick at each `nextTick` the engine asks for, `ticks` times. Returns each tick's
    /// delete count.
    static func hold(_ typist: inout Typist, ticks: Int) -> [Int] {
        var next = typist.press(.deleteDown).nextTick
        var counts: [Int] = []
        for _ in 0..<ticks {
            guard let time = next else { break }
            let output = typist.press(.tick, at: time)
            #expect(output.insertion.isEmpty)
            counts.append(output.deleteCount)
            next = output.nextTick
        }
        return counts
    }

    @Test("Touch-down deletes one character at once and asks for a tick after the initial delay")
    func touchDown() {
        var typist = Typist(Field(text: "abc"))
        let output = typist.press(.deleteDown, at: 50)
        #expect(output == TypingOutput(deleteCount: 1, nextTick: 50 + timings.deleteInitialDelay))
        #expect(typist.text == "ab")
    }

    @Test("Touch-up stops the repeat: no tick is asked for, and a late tick deletes nothing")
    func touchUp() {
        var typist = Typist(Field(text: "abc"))
        typist.press(.deleteDown)
        #expect(typist.press(.deleteUp, after: 0.01) == TypingOutput())
        #expect(typist.press(.tick, after: timings.deleteInitialDelay * 4) == TypingOutput())
        #expect(typist.text == "ab")
    }

    @Test("Delete at the start of the text sends one delete, which does nothing there, and Shift is on")
    func atStart() {
        var typist = Typist(Field())
        #expect(typist.press(.deleteDown).deleteCount == 1)
        #expect(typist.text == "")
        #expect(typist.shift == .automatic)
    }

    @Test("A held delete: characters at the repeat rate, then a word per repeat, across word boundaries")
    func heldDelete() {
        let characters = timings.deleteCharacterRepeats
        let start = "one two  three "
        var typist = Typist(Field(text: start + String(repeating: "z", count: characters + 1)))
        let counts = Self.hold(&typist, ticks: characters + 5)
        #expect(counts == Array(repeating: 1, count: characters) + [6, 5, 4, 1, 1])
        #expect(typist.text == "")
    }

    @Test("The repeat schedule follows the timings: the initial delay, the character interval, the word interval")
    func schedule() {
        var typist = Typist(Field(text: String(repeating: "word ", count: 200)))
        let down = 1000.0
        var next = typist.press(.deleteDown, at: down).nextTick
        var expected = down + timings.deleteInitialDelay
        var repeatNumber = 1
        while repeatNumber <= timings.deleteCharacterRepeats + 3, let time = next {
            #expect(abs(time - expected) < 1e-9, "repeat \(repeatNumber)")
            next = typist.press(.tick, at: time).nextTick
            expected +=
                repeatNumber < timings.deleteCharacterRepeats
                ? timings.deleteRepeatInterval : timings.deleteWordRepeatInterval
            repeatNumber += 1
        }
        #expect(repeatNumber == timings.deleteCharacterRepeats + 4)
    }

    @Test("A tick before the next repeat is due deletes nothing: early, the same time again, or time going back")
    func earlyTicks() {
        var typist = Typist(Field(text: "abcdef"))
        guard let due = typist.press(.deleteDown, at: 10).nextTick else {
            Issue.record("no tick asked for")
            return
        }
        #expect(typist.press(.tick, at: due.nextDown) == TypingOutput(nextTick: due))
        #expect(typist.press(.tick, at: due).deleteCount == 1)
        let next = typist.press(.tick, at: due)
        #expect(next.deleteCount == 0)
        #expect(typist.press(.tick, at: 5) == next)
        #expect(typist.press(.tick, at: .nan) == next)
        #expect(typist.text == "abcd")
    }

    @Test("A late tick does every repeat that is due, but deletes at most the context and one character more")
    func lateTick() {
        var typist = Typist(Field(text: "abc"))
        typist.press(.deleteDown, at: 0)
        let catchUp = typist.press(.tick, at: timings.deleteInitialDelay + timings.deleteRepeatInterval * 2.5)
        #expect(catchUp.deleteCount == 3)
        #expect(typist.text == "")

        var far = Typist(Field(text: "one two three"))
        far.press(.deleteDown, at: 0)
        let farOutput = far.press(.tick, at: 1e300)
        #expect(farOutput.deleteCount == "one two thre".count + 1)
        #expect(far.text == "")
        #expect(farOutput.nextTick.map { $0 > 1e299 } == true)
    }

    @Test("With no context the hold still deletes one character a tick (iOS may share none)")
    func noContext() {
        var typist = Typist(Field(textAfterCursor: "hidden"))
        let counts = Self.hold(&typist, ticks: timings.deleteCharacterRepeats + 3)
        #expect(counts == Array(repeating: 1, count: timings.deleteCharacterRepeats + 3))
    }

    @Test("Word deletes count characters, not scalars: emoji and combining marks are one character each")
    func graphemes() {
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
        let thumb = "\u{1F44D}\u{1F3FD}"
        var typist = Typist(Field(text: "ok \(thumb)e\u{301}\(family)xy"), timings: Self.quickWords)
        let counts = Self.hold(&typist, ticks: 2)
        #expect(counts == [1, 3])
        #expect(typist.text == "ok ")
    }

    @Test("A word delete takes the whitespace before the cursor with the word before it, line breaks too")
    func wordWithWhitespace() {
        var typist = Typist(Field(text: "first\nsecond \t x"), timings: Self.quickWords)
        let counts = Self.hold(&typist, ticks: 3)
        #expect(counts == [1, 8, 6])
        #expect(typist.text == "")
    }

    @Test("Another key during the hold ends it; a context change does not")
    func otherKeyEndsHold() {
        for event in [KeyEvent.character("a"), .space, .returnKey, .shift] {
            var typist = Typist(Field(text: "abcdef"))
            typist.press(.deleteDown)
            #expect(typist.press(event, after: 0.01).nextTick == nil, "\(event)")
            #expect(typist.press(.tick, after: timings.deleteInitialDelay * 2).deleteCount == 0, "\(event)")
        }
        var typist = Typist(Field(text: "abcdef"))
        let due = typist.press(.deleteDown, at: 0).nextTick
        #expect(typist.press(.contextChanged, at: 0.01).nextTick == due)
    }

    @Test("A second touch-down during a hold starts a new hold")
    func secondTouchDown() {
        var typist = Typist(Field(text: "abcdef"))
        typist.press(.deleteDown, at: 0)
        let output = typist.press(.deleteDown, at: 7)
        #expect(output == TypingOutput(deleteCount: 1, nextTick: 7 + timings.deleteInitialDelay))
    }

    @Test("A tick with no hold does nothing")
    func tickWithoutHold() {
        var typist = Typist(Field(text: "abc"))
        #expect(typist.press(.tick) == TypingOutput())
        #expect(typist.text == "abc")
    }
}
