// The bookkeeping of the fingers on the keyboard (KEY-24): which key each
// finger is on, and which key events the typing engine gets, and when. The
// keyboard extension's view feeds it each touch's identity and point, and sends
// the events it returns to the engine (`TypingEngine.handle`), in order, with
// the touch's time. It is a plain value in the core, rather than code in the
// adapter, so it is tested on Linux (ADR-0005).
//
// The rules, one finger at a time:
// - A letter, the space bar and Return act when the finger lifts, on the key
//   under it then (`.character`, `.space`, `.returnKey`). A finger that moves
//   follows the key under it, so a slide from one letter to another types the
//   one it lifts on.
// - Shift acts when the finger lands (`.shift`). Delete deletes when the finger
//   lands (`.deleteDown`) and repeats until it lifts or is cancelled, which sends
//   `.deleteUp`. A finger that landed on Shift or Delete stays on that key: its
//   moves change nothing. A finger that lands on a letter and lifts on Shift or
//   Delete types nothing (those keys act on landing, which it did not do there).
// - The "123", emoji, dictation and next-keyboard keys type nothing here: the
//   engine has no event for them yet.
// - A cancelled finger types nothing, and on Delete still sends `.deleteUp`.
//
// Several fingers (rollover). Fast typing overlaps touches: the next finger
// lands before the last one lifts. Each finger is followed by its identity, in
// the order the fingers landed. The rule for when a finger's key is committed:
// at its own lift, or when a later finger lands, whichever comes first. A
// finger that lands first finishes every finger already down that is still
// open, as if it had lifted where it is (a letter types, a Delete hold ends with
// `.deleteUp`), and only then does its own landing act. A finished finger stays
// down, and its key stays held for drawing, but its moves, its lift and its
// cancellation do nothing more. So at most one finger is open at a time, the
// last to land, and keys are committed in the order the fingers landed whatever
// order they lift in: "t", "h" and "e" overlapping type "the". Recalled, not
// measured: that Apple's keyboard commits a held key when the next finger
// lands. Assumption, for a device test (rung 4). This commit rule is KEY-62's
// adapter's, unchanged: what is typed under rollover is the same as before
// KEY-24 (review round 1 drove both adapters with the same touches). KEY-24
// moved the bookkeeping here, gave touches the nearest-key hit-test, and has
// every held key drawn.
//
// Not modelled (a gap for the typing engine, not decided here): Shift held as a
// modifier. The engine has only a Shift tap (`KeyEvent.shift`), so holding
// Shift and typing with another finger types the first letter upper case (Shift
// is on, then used up) and the next ones lower case, and lifting Shift does
// nothing. The engine would need Shift down and up events and a rule: letters
// typed while Shift is held are upper case; lifting Shift after typing turns it
// off (caps lock aside); lifting it without typing is a tap. The engine's own
// note on it is at `KeyEvent` (TypingEngine.swift); the ticket is KEY-66.
//
// Allocates nothing while at most `capacity` fingers are down: the touches are
// kept in an array whose storage is reserved when the value is made, and every
// loop indexes it with `while`.

/// One finger on the keyboard.
public struct KeyTouch: Equatable, Sendable {
    /// The finger's identity, from the caller: the same number from landing to lift.
    public let id: Int
    /// The index in the layout's `keys` of the key under the finger: where it landed, then where it moved while
    /// open. Nil when it is on no key (outside the layout's `touchArea`, or in a gap with the exact hit-test).
    public internal(set) var keyIndex: Int?
    /// The kind of that key.
    public internal(set) var kind: KeyKind?
    /// The kind of the key it landed on.
    public let landedOn: KeyKind?
    /// Whether the finger can still type: from landing until it lifts, is cancelled, or a later finger lands.
    public internal(set) var isOpen: Bool
}

/// The key events for one touch change, in the order to send them: at most two (a later finger's landing can
/// finish an open finger and then act itself). A value with no storage of its own.
public struct KeyEvents: Equatable, Sendable {
    /// The first event, or nil for none.
    public private(set) var first: KeyEvent?
    /// The second event, or nil. Never set when `first` is nil.
    public private(set) var second: KeyEvent?

    /// No events.
    public init() {}

    /// How many events there are: 0, 1 or 2.
    public var count: Int { first == nil ? 0 : (second == nil ? 1 : 2) }

    mutating func append(_ event: KeyEvent?) {
        guard let event else { return }
        if first == nil {
            first = event
        } else {
            second = event
        }
    }
}

/// The fingers on the keyboard and the key events they make. See the rules at the top of this file.
public struct KeyTouches: Sendable {
    /// How many fingers can be down at once without allocating. More still work.
    public static let capacity = 16

    /// Which hit-test finds the key under a finger. `.nearest` (the default) gives every point of the layout's
    /// `touchArea` a key; `.exact` is the hit-test before KEY-24, for tests.
    public var hitTesting: HitTesting
    /// Whether the next-keyboard (globe) key is shown. When false it is no key: touches on it and in the gaps around
    /// it go to its visible neighbours (`KeyboardLayout.keyIndex(nearest:showsInputModeSwitchKey:)`). The keyboard
    /// view sets it from UIKit's `needsInputModeSwitchKey`.
    public var showsInputModeSwitchKey = true
    /// Every finger down, in the order they landed.
    public private(set) var touches: [KeyTouch] = []

    /// No fingers down.
    public init(hitTesting: HitTesting = .nearest) {
        self.hitTesting = hitTesting
        touches.reserveCapacity(Self.capacity)
    }

    /// Whether a finger down, open or finished, is on key `keyIndex`, so the key is drawn held.
    public func holds(_ keyIndex: Int) -> Bool {
        var index = 0
        while index < touches.count {
            if touches[index].keyIndex == keyIndex { return true }
            index += 1
        }
        return false
    }

    /// The finger `id` landed at `point` in `layout`. Finishes the open finger first, if there is one (it commits
    /// its key), then acts for this one: `.shift` on Shift, `.deleteDown` on Delete. A finger already down with the
    /// same identity (its lift was lost) is dropped first, as if it had lifted.
    public mutating func began(_ id: Int, at point: LayoutPoint, in layout: KeyboardLayout) -> KeyEvents {
        var events = KeyEvents()
        events.append(finishOpen(commit: true))
        if let stale = position(of: id) { touches.remove(at: stale) }
        let keyIndex = layout.keyIndex(at: point, by: hitTesting, showsInputModeSwitchKey: showsInputModeSwitchKey)
        let kind = Self.kind(at: keyIndex, in: layout)
        touches.append(KeyTouch(id: id, keyIndex: keyIndex, kind: kind, landedOn: kind, isOpen: true))
        switch kind {
        case .shift?: events.append(.shift)
        case .delete?: events.append(.deleteDown)
        default: break
        }
        return events
    }

    /// The finger `id` moved to `point`. An open finger that did not land on Shift or Delete follows the key under
    /// it. Returns whether any finger's key changed, so the held keys are drawn again.
    public mutating func moved(_ id: Int, to point: LayoutPoint, in layout: KeyboardLayout) -> Bool {
        guard let position = position(of: id), touches[position].isOpen else { return false }
        switch touches[position].landedOn {
        case .shift?, .delete?: return false
        default: break
        }
        let keyIndex = layout.keyIndex(at: point, by: hitTesting, showsInputModeSwitchKey: showsInputModeSwitchKey)
        guard keyIndex != touches[position].keyIndex else { return false }
        touches[position].keyIndex = keyIndex
        touches[position].kind = Self.kind(at: keyIndex, in: layout)
        return true
    }

    /// The finger `id` lifted at `point`. An open finger moves there, then commits its key; a finished one does
    /// nothing more. Either way it is no longer down.
    public mutating func ended(_ id: Int, at point: LayoutPoint, in layout: KeyboardLayout) -> KeyEvents {
        guard let position = position(of: id) else { return KeyEvents() }
        _ = moved(id, to: point, in: layout)
        var events = KeyEvents()
        events.append(finish(at: position, commit: true))
        touches.remove(at: position)
        return events
    }

    /// The finger `id` was cancelled (`touchesCancelled`). It types nothing; an open finger on Delete still ends
    /// the hold. It is no longer down.
    public mutating func cancelled(_ id: Int) -> KeyEvents {
        guard let position = position(of: id) else { return KeyEvents() }
        var events = KeyEvents()
        events.append(finish(at: position, commit: false))
        touches.remove(at: position)
        return events
    }

    /// Every finger is gone at once (the keyboard is going away): none types, a Delete hold ends.
    public mutating func endAll() -> KeyEvents {
        var events = KeyEvents()
        events.append(finishOpen(commit: false))
        touches.removeAll(keepingCapacity: true)
        return events
    }

    /// Finishes every open finger (at most one), and returns its event.
    private mutating func finishOpen(commit: Bool) -> KeyEvent? {
        var event: KeyEvent?
        var index = 0
        while index < touches.count {
            if touches[index].isOpen, let finished = finish(at: index, commit: commit) { event = finished }
            index += 1
        }
        return event
    }

    /// Finishes the finger at `position`, if it is open, and returns its event: a Delete hold's end, or, when
    /// `commit` is true, its key's character, space or return.
    private mutating func finish(at position: Int, commit: Bool) -> KeyEvent? {
        guard touches[position].isOpen else { return nil }
        touches[position].isOpen = false
        if touches[position].landedOn == .delete { return .deleteUp }
        guard commit else { return nil }
        switch touches[position].kind {
        case .letter(let scalar)?: return .character(scalar)
        case .space?: return .space
        case .returnKey?: return .returnKey
        default: return nil
        }
    }

    private func position(of id: Int) -> Int? {
        var index = 0
        while index < touches.count {
            if touches[index].id == id { return index }
            index += 1
        }
        return nil
    }

    private static func kind(at keyIndex: Int?, in layout: KeyboardLayout) -> KeyKind? {
        guard let keyIndex, keyIndex < layout.keys.count else { return nil }
        return layout.keys[keyIndex].kind
    }
}
