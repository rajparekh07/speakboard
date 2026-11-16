import Testing

@testable import SpeakboardCore

@Suite("Typing: Shift and caps lock")
struct ShiftTests {
    /// A field where autocapitalisation is off, so Shift starts off and only the user turns it on.
    static let plain = Field(autocapitalization: .none)

    @Test("Shift starts off, and a letter types lowercase")
    func startsOff() {
        var typist = Typist(Self.plain)
        #expect(typist.shift == .off)
        let output = typist.press(.character("a"))
        #expect(output == TypingOutput(insertion: "a"))
        #expect(typist.shift == .off)
    }

    @Test("A tap turns Shift on for one letter, then it turns off")
    func oneLetter() {
        var typist = Typist(Self.plain)
        typist.press(.shift)
        #expect(typist.shift == .manual)
        #expect(typist.press(.character("a")) == TypingOutput(insertion: "A"))
        #expect(typist.shift == .off)
        typist.type("b")
        #expect(typist.text == "Ab")
    }

    @Test("Two taps further apart than the window turn Shift on, then off")
    func slowDoubleTap() {
        var typist = Typist(Self.plain)
        typist.press(.shift)
        typist.press(.shift, after: timings.shiftDoubleTapWindow * 2)
        #expect(typist.shift == .off)
        typist.type("a")
        #expect(typist.text == "a")
    }

    @Test("A double tap within the window locks Shift; the window's end is inside it")
    func doubleTapLocks() {
        // The taps are at 0 and at the gap, so the engine's subtraction gives the gap exactly.
        for gap in [0, timings.shiftDoubleTapWindow / 2, timings.shiftDoubleTapWindow] {
            var typist = Typist(Self.plain)
            typist.press(.shift, at: 0)
            typist.press(.shift, at: gap)
            #expect(typist.shift == .locked, "gap \(gap)")
        }
    }

    @Test("Just past the window, the second tap is a plain tap")
    func justPastWindow() {
        var typist = Typist(Self.plain)
        typist.press(.shift, at: 0)
        typist.press(.shift, at: timings.shiftDoubleTapWindow.nextUp)
        #expect(typist.shift == .off)
    }

    @Test("Caps lock holds across letters, spaces, Return, delete and context changes, until Shift is tapped")
    func capsLockHolds() {
        var typist = Typist(Self.plain)
        typist.press(.shift)
        typist.press(.shift, after: timings.shiftDoubleTapWindow / 2)
        typist.type("ab c\nd")
        typist.press(.deleteDown)
        typist.press(.deleteUp)
        typist.press(.contextChanged)
        typist.type("ef")
        #expect(typist.text == "AB C\nEF")
        #expect(typist.shift == .locked)
        typist.press(.shift)
        #expect(typist.shift == .off)
        typist.type("g")
        #expect(typist.text == "AB C\nEFg")
    }

    @Test("Shift, then caps lock, then Shift: on, locked, off")
    func shiftCapsLockShift() {
        var typist = Typist(Self.plain)
        typist.press(.shift)
        #expect(typist.shift == .manual)
        typist.press(.shift, after: timings.shiftDoubleTapWindow / 2)
        #expect(typist.shift == .locked)
        typist.press(.shift)
        #expect(typist.shift == .off)
    }

    @Test("A third quick tap unlocks: it is a single tap on a locked Shift (assumption)")
    func tripleTap() {
        var typist = Typist(Self.plain)
        let gap = timings.shiftDoubleTapWindow / 3
        typist.press(.shift)
        typist.press(.shift, after: gap)
        typist.press(.shift, after: gap)
        #expect(typist.shift == .off)
    }

    @Test("A double tap does not lock when Enable Caps Lock is off")
    func capsLockSettingOff() {
        var typist = Typist(Self.plain, settings: TypingSettings(capsLock: false))
        typist.press(.shift)
        typist.press(.shift, after: timings.shiftDoubleTapWindow / 2)
        #expect(typist.shift == .off)
        typist.type("a")
        #expect(typist.text == "a")
    }

    @Test("A double tap from automatic Shift locks")
    func doubleTapFromAutomatic() {
        var typist = Typist(Field(autocapitalization: .sentences))
        #expect(typist.shift == .automatic)
        typist.press(.shift)
        #expect(typist.shift == .off)
        typist.press(.shift, after: timings.shiftDoubleTapWindow / 2)
        #expect(typist.shift == .locked)
    }

    @Test("A tap on automatic Shift turns it off for the next letter")
    func overrideAutomatic() {
        var typist = Typist(Field(autocapitalization: .sentences))
        typist.press(.shift)
        typist.type("hi")
        #expect(typist.text == "hi")
    }

    @Test("Another key between the taps cancels the double tap")
    func keyBetweenTaps() {
        let between: [KeyEvent] = [.character("a"), .space, .returnKey, .deleteDown, .deleteUp]
        for event in between {
            var typist = Typist(Self.plain)
            let gap = timings.shiftDoubleTapWindow / 4
            typist.press(.shift)
            typist.press(event, after: gap)
            typist.press(.shift, after: gap)
            #expect(typist.shift != .locked, "\(event)")
        }
    }

    @Test("A context change between the taps does not cancel the double tap")
    func contextChangeBetweenTaps() {
        var typist = Typist(Self.plain)
        let gap = timings.shiftDoubleTapWindow / 4
        typist.press(.shift)
        typist.press(.contextChanged, after: gap)
        typist.press(.shift, after: gap)
        #expect(typist.shift == .locked)
    }

    @Test("Time going backwards between taps does not lock; time standing still does")
    func timeBetweenTaps() {
        var typist = Typist(Self.plain)
        typist.press(.shift, at: 10)
        typist.press(.shift, at: 10 - timings.shiftDoubleTapWindow / 2)
        #expect(typist.shift == .off)

        var still = Typist(Self.plain)
        still.press(.shift, at: 10)
        still.press(.shift, at: 10)
        #expect(still.shift == .locked)

        var nan = Typist(Self.plain)
        nan.press(.shift, at: 10)
        nan.press(.shift, at: .nan)
        #expect(nan.shift == .off)
    }

    @Test("A manual Shift is used up by a space or Return, then autocapitalisation decides")
    func manualShiftUsedUpBySpace() {
        var typist = Typist(Field(text: "hi", autocapitalization: .sentences))
        #expect(typist.shift == .off)
        typist.press(.shift)
        typist.press(.space)
        #expect(typist.shift == .off)
        typist.press(.shift)
        typist.press(.returnKey)
        #expect(typist.shift == .automatic)
    }

    @Test("A manual Shift stays through a context change (assumption), and goes with a delete")
    func manualShiftAndContext() {
        var typist = Typist(Field(text: "hi", autocapitalization: .sentences))
        typist.press(.shift)
        typist.press(.contextChanged)
        #expect(typist.shift == .manual)
        typist.press(.deleteDown)
        #expect(typist.shift == .off)
    }

    @Test("Shift uppercases with Unicode's case mapping, beyond ASCII")
    func uppercaseMapping() {
        var typist = Typist(Self.plain)
        typist.press(.shift)
        #expect(typist.press(.character("é")).insertion == "É")
        typist.press(.shift)
        #expect(typist.press(.character("ß")).insertion == "SS")
    }
}
