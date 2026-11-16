// The typing engine: a pure state machine that turns key events into text
// operations. It holds the typing behaviour users expect from Apple's
// keyboard (shift, caps lock, auto-capitalisation, the double-space full stop,
// accelerating delete and the Return key's state), so the keyboard extension
// only draws keys and applies the operations.
//
// Pure and synchronous: each call takes the event, the time it happened and the
// field's context, and returns the operations in the same call. There is no
// clock, no timer and no global state. Time is an input, in seconds on any
// clock that does not jump (on iOS, the touch's timestamp). Delete's repeat
// needs a timer, which the engine does not own: each output says when the
// caller should send the next `.tick`, and the engine works out from the tick's
// time which repeats are due, so a late timer catches up instead of slowing
// the repeat down.
//
// The engine does not own the document (see TypingContext.swift). It reads the
// end of the text before the cursor and returns deletes and an insertion.
//
// Handling an event allocates nothing (MANIFESTO.md, Budgets: "Allocations in
// the keystroke path: zero"). The state is plain values. Every string the
// engine returns is a literal of at most 2 bytes (" ", "\n", ". "), one
// character key's scalar, or that scalar's Unicode uppercase mapping. The
// longest uppercase mapping is 3 scalars and 6 UTF-8 bytes (U+0390 and others,
// measured with the pinned Swift 6.4.2; ShiftTests checks every scalar), and
// Swift stores a string of up to 15 UTF-8 bytes inline, in the String value
// itself, so none of them is on the heap. Text is read with indices in `while` loops,
// because a `for`-`in` loop calls generic iterator code that allocates in a
// debug build. TypingAllocationTests proves it on Linux.
//
// Where each rule comes from is said at the rule. "Recalled, not measured"
// means it is how this project remembers Apple's keyboard behaving; a device
// test (rung 4) must confirm it. "Assumption" marks an edge case where Apple's
// behaviour is not known, and the engine picks one.

/// A key event, from touch handling.
///
/// Notes for the keyboard extension's adapter and touch handling (KEY-24), which build on these events:
/// - There is no event yet for a key that types nothing (123, globe, the mic). Such a key cannot cancel a pending
///   double tap on Shift or a pending double space: a Shift tap, 123, then a quick Shift tap still locks.
/// - Shift is a tap. Holding Shift while typing letters (uppercase while held, off on release) will need Shift
///   down and up events; they do not exist yet.
/// - Send `.deleteUp` when Delete's touch ends for any reason, `touchesCancelled` included. Until `.deleteUp` or
///   another key arrives, the hold goes on deleting at every `.tick`.
/// - An engine lives for one field session (the orchestrator's decision in KEY-22 review round 2). Make a fresh
///   engine, and send it `.contextChanged`, when the keyboard appears and when the document it types into changes
///   (another field, another app). `.contextChanged` is only for changes within that field. If the adapter keeps one
///   engine instead, the user's Shift choice carries over into the next field and the next appearance: a Shift
///   tapped off stays off at the start of an empty field, a manual Shift capitalises its first letter, caps lock stays
///   on, and a pending double tap or double space (within its window) and a delete hold carry over too.
public enum KeyEvent: Equatable, Sendable {
    /// A character key, with the character it shows in lowercase: a letter key's `KeyKind.letter` scalar. The
    /// engine uppercases it when Shift is on.
    case character(Unicode.Scalar)
    /// A tap on Shift.
    case shift
    /// A tap on the space bar.
    case space
    /// A tap on Return.
    case returnKey
    /// Delete's touch-down. It deletes at once and starts the repeat.
    case deleteDown
    /// Delete's touch-up. It stops the repeat.
    case deleteUp
    /// The caller's timer fired, at the time an earlier output's `nextTick` asked for (or later).
    case tick
    /// The text or the insertion point changed outside the engine, within the same field (on iOS,
    /// `textDidChange`). The engine updates the automatic Shift state from the new context and changes nothing else.
    /// It never undoes the user's own choice: a manual Shift, caps lock, and a Shift the user tapped off all stay, so
    /// it is safe to send as often as the caller likes within a field. A new field, another app or the keyboard
    /// appearing again is not a context change: make a fresh engine (see the notes above).
    case contextChanged
}

/// The Shift key's state, for drawing it and the letter keys.
public enum ShiftState: Equatable, Sendable {
    /// Off: letters are lowercase.
    case off
    /// On because the field's autocapitalisation pressed it. The next letter is uppercase.
    case automatic
    /// On because the user tapped it. The next letter is uppercase.
    case manual
    /// Caps lock: every letter is uppercase until Shift is tapped again.
    case locked

    /// Whether the next letter is uppercase.
    public var isOn: Bool { self != .off }
}

/// The text operations for one event: first `deleteCount` backward deletes, then `insertion` at the insertion
/// point. On iOS that is `deleteCount` calls to `deleteBackward()`, then one `insertText(_:)` if the insertion is
/// not empty.
public struct TypingOutput: Equatable, Sendable {
    /// How many characters to delete backward, one `deleteBackward()` each. Applied first.
    public var deleteCount: Int
    /// The text to insert after the deletes, or "" for none.
    public var insertion: String
    /// When the caller should send `.tick`, on the same clock as the events: while Delete is held, the time of its
    /// next repeat; otherwise nil, and any timer the caller holds can be cancelled.
    public var nextTick: Double?

    /// Operations.
    public init(deleteCount: Int = 0, insertion: String = "", nextTick: Double? = nil) {
        self.deleteCount = deleteCount
        self.insertion = insertion
        self.nextTick = nextTick
    }
}

/// The Return key's state, for drawing it.
public struct ReturnKeyState: Equatable, Sendable {
    /// The kind the field asks for. Its title and colour come from key rendering, not from the engine.
    public var kind: ReturnKeyType
    /// Whether Return does anything when tapped.
    public var isEnabled: Bool
}

/// The typing state machine for one locale. A value type: copy it to fork the state, and keep one per keyboard.
public struct TypingEngine: Sendable {
    /// The locale whose rules the engine follows: the one the data holds, which can be the language of the locale
    /// asked for (see `init`).
    public let locale: KeyboardLocale
    /// The user's keyboard settings. Change them between events at any time.
    public var settings: TypingSettings
    /// The time windows and the delete-repeat schedule.
    public var timings: TypingTimings
    /// The Shift key's state after the last event.
    public private(set) var shiftState: ShiftState = .off

    let rules: TypingRules
    /// Whether the user's last Shift tap turned Shift off, and no key has typed or deleted text since. While it is
    /// true, a context change leaves Shift off (see `contextChanged`).
    private(set) var userTurnedShiftOff = false
    /// The time of the last tap on Shift, while a second tap could still lock it.
    private var lastShiftTap: Double?
    /// The time of the last tap on the space bar, while it was a plain space and a second tap could still turn it
    /// into a full stop.
    private var lastSpace: Double?
    /// Delete's hold, from touch-down to touch-up.
    private var deleteHold: DeleteHold?

    private struct DeleteHold: Sendable {
        /// When the next repeat is due.
        var nextRepeat: Double
        /// How many repeats are done.
        var repeatsDone: Int
    }

    /// The engine for `locale`, or nil if neither the locale nor its language has typing rules. The rules for the
    /// locale itself are used if there are any, otherwise its language's, as for the letters layout: "en-US" gets
    /// the "en" rules. English is the only locale with rules (ADR-0010).
    ///
    /// An engine lives for one field session: make one when the keyboard appears and when the document it types into
    /// changes, then send it `.contextChanged` so it reads the field (Shift starts off). Reusing an engine across
    /// fields carries the user's Shift choice over (see `KeyEvent`'s notes). Assumption: Apple's keyboard does not
    /// keep caps lock, or a Shift the user set, across fields; that is not known and a device test must settle it.
    public init?(
        locale: KeyboardLocale, settings: TypingSettings = TypingSettings(), timings: TypingTimings = .estimated
    ) {
        guard let (dataLocale, rules) = locale.entry(in: TypingRules.byLocale) else { return nil }
        self.locale = dataLocale
        self.rules = rules
        self.settings = settings
        self.timings = timings
    }

    /// The Return key's state in `context`. Disabled only when the field sets `enablesReturnKeyAutomatically` and
    /// has no text, as Apple documents that trait; enabled otherwise, for every kind.
    public func returnKey(in context: TypingContext) -> ReturnKeyState {
        ReturnKeyState(
            kind: context.returnKeyType,
            isEnabled: !(context.enablesReturnKeyAutomatically && !context.documentHasText))
    }

    /// Handles `event`, which happened at `time` (seconds) in `context`, and returns the text operations for it.
    /// The new Shift state is in `shiftState`, and the Return key's in `returnKey(in:)` with the next context.
    public mutating func handle(_ event: KeyEvent, at time: Double, in context: TypingContext) -> TypingOutput {
        var output: TypingOutput
        switch event {
        case .character(let scalar): output = character(scalar, in: context)
        case .shift: output = shift(at: time)
        case .space: output = space(at: time, in: context)
        case .returnKey: output = returnKey(context)
        case .deleteDown: output = deleteDown(at: time, in: context)
        case .deleteUp: output = deleteUp()
        case .tick: output = tick(at: time, in: context)
        case .contextChanged: output = contextChanged(context)
        }
        output.nextTick = deleteHold?.nextRepeat
        return output
    }

    // MARK: Events

    /// A character key. Shift on (automatic, manual or locked) uppercases it with Unicode's default case mapping.
    /// A manual or automatic Shift is used up by the character, then autocapitalisation decides again; caps lock
    /// stays. Recalled, not measured: Shift applies to one letter.
    private mutating func character(_ scalar: Unicode.Scalar, in context: TypingContext) -> TypingOutput {
        endOtherKeyState()
        let insertion = shiftState.isOn ? scalar.properties.uppercaseMapping : String(Character(scalar))
        updateAutomaticShift(
            context, end: context.textBeforeCursor.endIndex, inserting: insertion, keepUserChoice: false)
        return TypingOutput(insertion: insertion)
    }

    /// Shift. A tap turns Shift off if it is on (automatic, manual or locked), and on (manual) if it is off.
    /// A second tap within `shiftDoubleTapWindow` of the first, with no other key between them, turns on caps lock
    /// when the Enable Caps Lock setting is on. Recalled, not measured: the double tap, and that it locks from any
    /// starting state. Assumption: a third tap right after locking unlocks (it is a single tap on a locked Shift).
    private mutating func shift(at time: Double) -> TypingOutput {
        deleteHold = nil
        lastSpace = nil
        if settings.capsLock, let last = lastShiftTap, Self.within(time - last, timings.shiftDoubleTapWindow) {
            shiftState = .locked
            lastShiftTap = nil
            userTurnedShiftOff = false
            return TypingOutput()
        }
        shiftState = shiftState == .off ? .manual : .off
        userTurnedShiftOff = shiftState == .off
        lastShiftTap = time
        return TypingOutput()
    }

    /// The space bar. It types a space, except for the double-space full stop: when the "." Shortcut setting is on,
    /// the previous key was a space that typed a plain space less than `doubleSpaceWindow` ago, and that space
    /// still ends the text and follows a letter or digit (possibly with closing quotes or brackets after it), the
    /// space is deleted and the locale's full stop and space are typed. Apple lists "automatic period upon double
    /// space" (Custom Keyboard guide); its exact conditions are recalled, not measured. Assumptions: no full stop
    /// after punctuation (`hi.` then two spaces gives two spaces), at the start of the text or after whitespace,
    /// and a third space after the full stop is a plain space.
    private mutating func space(at time: Double, in context: TypingContext) -> TypingOutput {
        deleteHold = nil
        lastShiftTap = nil
        let text = context.textBeforeCursor
        if settings.periodShortcut, let last = lastSpace, Self.within(time - last, timings.doubleSpaceWindow),
            followsAWord(afterTrailingSpace: text)
        {
            lastSpace = nil
            let insertion = rules.doubleSpaceInsertion
            let end = text.index(before: text.endIndex)
            updateAutomaticShift(context, end: end, inserting: insertion, keepUserChoice: false)
            return TypingOutput(deleteCount: 1, insertion: insertion)
        }
        lastSpace = time
        updateAutomaticShift(context, end: text.endIndex, inserting: " ", keepUserChoice: false)
        return TypingOutput(insertion: " ")
    }

    /// Return. It inserts a line break, "\n", whatever the field's Return key kind. When the Return key is disabled
    /// (`returnKey(in:)`) a tap does nothing; that part is documented (`enablesReturnKeyAutomatically`).
    ///
    /// Recalled, not measured: that a custom keyboard sends "\n" for every kind, Go and Search included, and that
    /// the field acts on it (sends, searches, dismisses the keyboard). Apple's Custom Keyboard guide shows only
    /// `insertText("\n")` inserting a newline in a text view, and returnKeyType's documentation says pressing the
    /// key "typically results in the system dismissing the keyboard" without saying how. A device test must settle
    /// it.
    private mutating func returnKey(_ context: TypingContext) -> TypingOutput {
        endOtherKeyState()
        guard returnKey(in: context).isEnabled else { return TypingOutput() }
        updateAutomaticShift(context, end: context.textBeforeCursor.endIndex, inserting: "\n", keepUserChoice: false)
        return TypingOutput(insertion: "\n")
    }

    /// Delete's touch-down: it deletes one character at once and starts the hold. Recalled, not measured: Delete
    /// acts on touch-down, not touch-up. It deletes even when the context shows no text, because iOS may share no
    /// context while there is text, and a delete at the start of a field does nothing. A touch-down during a hold
    /// starts a new hold (the touch-up was lost).
    private mutating func deleteDown(at time: Double, in context: TypingContext) -> TypingOutput {
        lastShiftTap = nil
        lastSpace = nil
        deleteHold = DeleteHold(nextRepeat: time + timings.deleteInitialDelay, repeatsDone: 0)
        let text = context.textBeforeCursor
        let end = text.isEmpty ? text.endIndex : text.index(before: text.endIndex)
        updateAutomaticShift(context, end: end, inserting: "", keepUserChoice: false)
        return TypingOutput(deleteCount: 1)
    }

    /// Delete's touch-up: the hold ends and nothing more is deleted.
    private mutating func deleteUp() -> TypingOutput {
        endOtherKeyState()
        return TypingOutput()
    }

    /// The caller's timer. While Delete is held, it does every repeat that is due by `time` and not done yet. The
    /// first repeat is due `deleteInitialDelay` after touch-down, the next ones every `deleteRepeatInterval` while
    /// repeats delete characters, then every `deleteWordRepeatInterval`. The first `deleteCharacterRepeats` repeats
    /// delete one character each, and every later one a word: the whitespace before the cursor and the run of
    /// non-whitespace before that. Recalled, not measured: the repeat, its speeding up, and deleting by word. The
    /// timings are estimates (TypingTimings).
    ///
    /// A repeat is due when the tick's time is at or after the `nextTick` the engine gave, so a tick at exactly that
    /// time does the repeat. A tick before it (time standing still, or going backwards, or NaN) does nothing.
    /// Without a hold, a tick does nothing.
    ///
    /// In one tick the repeats delete what the context shows, and at most one character more, so a missing or
    /// short context still deletes at the repeat rate. Once a tick has nothing left to delete, the repeats still
    /// due would delete nothing, so they are skipped and the schedule goes on from the tick's time: a late tick
    /// does a bounded amount of work, and the next tick it asks for is in the future.
    private mutating func tick(at time: Double, in context: TypingContext) -> TypingOutput {
        guard var hold = deleteHold, hold.nextRepeat <= time else { return TypingOutput() }

        let text = context.textBeforeCursor
        var end = text.endIndex
        var count = 0
        var usedExtra = false
        while hold.nextRepeat <= time {
            if usedExtra && end == text.startIndex {
                hold.nextRepeat = time + repeatInterval(after: hold.repeatsDone)
                break
            }
            var deleted = 0
            if hold.repeatsDone < timings.deleteCharacterRepeats {
                if end > text.startIndex {
                    end = text.index(before: end)
                    deleted = 1
                }
            } else {
                deleted = Self.stepBackOverWord(text, end: &end)
            }
            if deleted == 0 && !usedExtra {
                usedExtra = true
                deleted = 1
            }
            count += deleted
            hold.repeatsDone += 1
            hold.nextRepeat += repeatInterval(after: hold.repeatsDone)
        }
        deleteHold = hold
        updateAutomaticShift(context, end: end, inserting: "", keepUserChoice: false)
        return TypingOutput(deleteCount: count)
    }

    /// The context changed outside the engine. Automatic Shift follows the new context, and nothing else changes.
    /// The user's own choice stays: caps lock, a manual Shift, and a Shift the user tapped off.
    ///
    /// Assumptions, not measured, within one field session (an engine lives for one field; see `init`): moving the
    /// cursor keeps a manual Shift; and a Shift the user tapped off stays off through any context change, until the
    /// next key that types or deletes text (a character, a space, an enabled Return, Delete's touch-down, or a repeat
    /// that deletes) or the next Shift tap. The engine cannot tell a context
    /// change at the same place (iOS repeating `textDidChange`) from a move to another place without storing the
    /// text, which it does not, so it keeps the user's "off" in both: after tapping Shift off and moving the cursor to
    /// a sentence start, the next letter is lowercase.
    private mutating func contextChanged(_ context: TypingContext) -> TypingOutput {
        updateAutomaticShift(context, end: context.textBeforeCursor.endIndex, inserting: "", keepUserChoice: true)
        return TypingOutput()
    }

    /// Any key but Delete's touch-down, a tick or a context change ends the delete hold, and cancels a pending
    /// double tap on Shift and a pending double space. Assumption: another key during a delete hold stops it.
    private mutating func endOtherKeyState() {
        deleteHold = nil
        lastShiftTap = nil
        lastSpace = nil
    }

    // MARK: Autocapitalisation

    /// Sets Shift from autocapitalisation for the text as it will be after the output: the context's text up to
    /// `end`, then `insertion`. Caps lock is never changed. When `keepUserChoice` is true, a manual Shift and a
    /// Shift the user tapped off are kept too; when it is false (a key typed or deleted text), the user's "off"
    /// ends here.
    private mutating func updateAutomaticShift(
        _ context: TypingContext, end: String.Index, inserting insertion: String, keepUserChoice: Bool
    ) {
        if shiftState == .locked { return }
        if keepUserChoice && (shiftState == .manual || userTurnedShiftOff) { return }
        userTurnedShiftOff = false
        var text = BackwardScalars(base: context.textBeforeCursor, end: end, tail: insertion)
        shiftState = capitalizes(&text, context.autocapitalization) ? .automatic : .off
    }

    /// Whether the next letter after `text` is capitalised automatically.
    ///
    /// - `none`: never. `allCharacters`: always. Both as Apple documents them.
    /// - `words`: at the start of the text and after whitespace. Apple: "the first letter of each word".
    /// - `sentences`: at the start of the text, after a line break, and after a sentence terminator (for English
    ///   ".", "!" or "?") followed by whitespace, with any closing quotes or brackets between them (`"Hi." `).
    ///   Apple: "the first letter of each sentence"; what ends a sentence is recalled, not measured.
    ///
    /// In `words` and `sentences`, opening quotes and brackets just before the cursor are skipped (`Hi. "`).
    /// Recalled, not measured. Assumptions: text that is only whitespace counts as the start of the text; text
    /// that is only closers and whitespace (`) `) does not; abbreviations such as "e.g. " end a sentence, because
    /// the engine has no lexicon; the Auto-Capitalization setting off turns off every type, `allCharacters` too.
    private func capitalizes(_ text: inout BackwardScalars, _ type: Autocapitalization) -> Bool {
        guard settings.autoCapitalization else { return false }
        switch type {
        case .none: return false
        case .allCharacters: return true
        case .words, .sentences: break
        }

        var scalar = text.next()
        while let current = scalar, rules.openers.has(current) { scalar = text.next() }
        guard let first = scalar else { return true }
        guard first.properties.isWhitespace else { return false }
        if type == .words { return true }

        while let current = scalar, current.properties.isWhitespace {
            if Self.isLineBreak(current) { return true }
            scalar = text.next()
        }
        guard scalar != nil else { return true }
        while let current = scalar, rules.closers.has(current) { scalar = text.next() }
        guard let last = scalar else { return false }
        return rules.sentenceTerminators.has(last)
    }

    /// Whether `text` ends with a space (U+0020) that follows a letter or digit, possibly with closing quotes or
    /// brackets between them. It reads characters (grapheme clusters) by their first scalar, as the word delete
    /// does, so a letter followed by combining marks ("i" and U+0301) counts as a letter.
    ///
    /// The last character must be exactly one space, on its own. A space can join the character before it: a
    /// Prepend scalar such as U+0600 followed by a space is one character (Unicode grapheme rule GB9b). Then the
    /// text does not end with a plain space, there is no full stop, and the one delete that would replace the space
    /// cannot remove the Prepend scalar with it (KEY-22 review round 2).
    private func followsAWord(afterTrailingSpace text: String) -> Bool {
        guard text.endIndex > text.startIndex else { return false }
        // `text.index(before:)` from a character boundary gives a character boundary; `endIndex` is one.
        var end = text.index(before: text.endIndex)
        let scalars = text.unicodeScalars
        guard scalars[end] == " ", scalars.index(after: end) == scalars.endIndex else { return false }
        while end > text.startIndex {
            let previous = text.index(before: end)
            let first = scalars[previous]
            if rules.closers.has(first) {
                end = previous
                continue
            }
            return first.properties.isAlphabetic || first.properties.numericType != nil
        }
        return false
    }

    // MARK: Delete repeat

    /// The time from repeat `repeatsDone` to the next one.
    private func repeatInterval(after repeatsDone: Int) -> Double {
        repeatsDone < timings.deleteCharacterRepeats ? timings.deleteRepeatInterval : timings.deleteWordRepeatInterval
    }

    /// Moves `end` back over the whitespace before it and the run of non-whitespace before that, a character
    /// (grapheme cluster) at a time, and returns how many characters it moved over. A character counts as
    /// whitespace by its first scalar.
    ///
    /// Cost, for a device test (rung 4): linear in the word's length, except that Swift's backward grapheme
    /// breaking over a run of regional indicators (flag emoji) is quadratic. The KEY-22 round 1 review measured a
    /// word delete over 100, 1,000 and 4,000 flags at 0.14, 12 and 218 ms in a Linux debug build. iOS shares only
    /// part of the text before the cursor, which bounds it in practice; the device test should confirm that.
    private static func stepBackOverWord(_ text: String, end: inout String.Index) -> Int {
        var count = 0
        while end > text.startIndex {
            let previous = text.index(before: end)
            guard text.unicodeScalars[previous].properties.isWhitespace else { break }
            end = previous
            count += 1
        }
        while end > text.startIndex {
            let previous = text.index(before: end)
            if text.unicodeScalars[previous].properties.isWhitespace { break }
            end = previous
            count += 1
        }
        return count
    }

    // MARK: Helpers

    /// Whether `interval` is a time from 0 to `window`, both included. A negative or NaN interval (time going
    /// backwards) is outside.
    private static func within(_ interval: Double, _ window: Double) -> Bool {
        interval >= 0 && interval <= window
    }

    /// Unicode's line break characters: LF, VT, FF, CR, NEL, LINE SEPARATOR and PARAGRAPH SEPARATOR.
    private static func isLineBreak(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0A...0x0D, 0x85, 0x2028, 0x2029: return true
        default: return false
        }
    }
}

/// Reads text backward one Unicode scalar at a time: first `tail` from its end, then `base` from `end`. It stands
/// for the text as it will be after an output (`base` up to `end`, the part the deletes leave, then the insertion)
/// without building that string.
struct BackwardScalars {
    private let base: String.UnicodeScalarView
    private var baseIndex: String.Index
    private let tail: String.UnicodeScalarView
    private var tailIndex: String.Index

    init(base: String, end: String.Index, tail: String) {
        self.base = base.unicodeScalars
        self.baseIndex = end
        self.tail = tail.unicodeScalars
        self.tailIndex = tail.unicodeScalars.endIndex
    }

    /// The scalar before the last one read, or nil at the start of `base`.
    mutating func next() -> Unicode.Scalar? {
        if tailIndex > tail.startIndex {
            tailIndex = tail.index(before: tailIndex)
            return tail[tailIndex]
        }
        if baseIndex > base.startIndex {
            baseIndex = base.index(before: baseIndex)
            return base[baseIndex]
        }
        return nil
    }
}
