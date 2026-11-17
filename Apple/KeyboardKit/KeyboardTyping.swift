import Foundation
import SpeakboardCore

/// Asks for the typing engine's next `.tick`, for Delete's repeat. `TimerTickScheduler` is the real one; tests use a
/// fake and call `KeyboardTyping.tick(at:)` themselves, so the clock is theirs.
@MainActor
public protocol TickScheduler: AnyObject {
    /// Call `tick(at:)` on `typing` at `time` (on the touch timestamps' clock, `ProcessInfo.systemUptime`), or never
    /// if `time` is nil. A new request replaces the last one.
    func requestTick(at time: TimeInterval?, for typing: KeyboardTyping)
}

/// Told when the typing state the view draws (Shift, the held key, the return key) may have changed.
@MainActor
public protocol KeyboardTypingObserver: AnyObject {
    /// The state changed; read it from the `KeyboardTyping`.
    func typingStateDidChange(_ typing: KeyboardTyping)
}

/// The keyboard's adapter between touches and the field (ADR-0005: the Apple side is thin). Touches arrive as plain
/// points in the layout's coordinates and times in seconds; the core's hit-test finds the key, the core's typing
/// engine turns it into text operations, and this applies them to the field at once, in the same call: first the
/// backward deletes, then one insertion.
///
/// What it does with touches, one finger at a time:
/// - A letter, the space bar and Return act when the finger lifts, on the key under it then (a finger that slides
///   off every key types nothing). Shift acts when the finger lands. Delete deletes when the finger lands and repeats
///   until it lifts: `.deleteDown`, then `.tick` at each time the engine asks for, then `.deleteUp`.
/// - A finger that is cancelled (`touchesCancelled`) types nothing; on Delete it still sends `.deleteUp`.
/// - A second finger landing while the first is down finishes the first at once, as if it had lifted where it is,
///   then becomes the finger this follows. The first finger's own lift is then ignored. So fast two-thumb typing
///   neither loses nor doubles a letter, and a second finger ends a Delete hold.
/// - The "123" key, the emoji key, Apple's dictation key and the next-keyboard key type nothing here (KEY-62 does
///   not cover them; the next-keyboard key is the view's, through UIKit). The engine has no event for them yet.
///
/// The engine lives for one field session (KeyEvent's notes): `beginFieldSession(at:)` makes a fresh one, and
/// `textDidChange(at:)` makes a fresh one when the field's document changed, and otherwise sends `.contextChanged`.
@MainActor
public final class KeyboardTyping {
    /// The field typed into.
    public let field: KeyboardTextField
    /// The locale whose typing rules are used.
    public let locale: KeyboardLocale
    /// The engine's state for this field session.
    public private(set) var engine: TypingEngine
    /// The layout touches are hit-tested against. Nil: touches do nothing.
    public var layout: KeyboardLayout?
    /// Told when the drawn state may have changed.
    public weak var observer: KeyboardTypingObserver?

    /// The index in `layout.keys` of the key under the finger being followed, or nil.
    public private(set) var heldKeyIndex: Int?

    private let scheduler: TickScheduler
    private var activeTouch: Int?
    private var activeKind: KeyKind?
    private var sessionDocument: UUID?

    /// An adapter for `field`, typing with `locale`'s rules, or nil if the core has no typing rules for it.
    public init?(field: KeyboardTextField, scheduler: TickScheduler, locale: KeyboardLocale = .english) {
        guard let engine = TypingEngine(locale: locale) else { return nil }
        self.field = field
        self.scheduler = scheduler
        self.locale = locale
        self.engine = engine
    }

    /// The Shift state to draw.
    public var shiftState: ShiftState { engine.shiftState }

    /// The return key's state to draw, for the field as it is now.
    public var returnKey: ReturnKeyState { engine.returnKey(in: field.typingContext) }

    /// The keyboard appeared: a fresh engine for this field session, which then reads the field.
    public func beginFieldSession(at time: TimeInterval) {
        if let engine = TypingEngine(locale: locale) { self.engine = engine }
        sessionDocument = field.documentIdentifier
        activeTouch = nil
        activeKind = nil
        heldKeyIndex = nil
        scheduler.requestTick(at: nil, for: self)
        send(.contextChanged, at: time)
    }

    /// The field's text or selection changed outside the keyboard (`textDidChange`, `selectionDidChange`). Another
    /// document means another field session, but only when one known identifier changes to another: the proxy has
    /// none when the keyboard appears (seen in the simulator), so the first identifier to arrive is taken as this
    /// session's, keeping the engine and the user's Shift, and the change is a context change.
    public func textDidChange(at time: TimeInterval) {
        let current = field.documentIdentifier
        if let current, let sessionDocument, current != sessionDocument {
            beginFieldSession(at: time)
            return
        }
        if sessionDocument == nil { sessionDocument = current }
        send(.contextChanged, at: time)
    }

    /// The keyboard is going away: the finger being followed types nothing more, and a Delete hold ends, as if the
    /// touch were cancelled, in case UIKit does not cancel it.
    public func endTouches(at time: TimeInterval) {
        if activeTouch != nil { finishActiveTouch(commit: false, at: time) }
        scheduler.requestTick(at: nil, for: self)
    }

    /// A finger landed at `point`. `touch` names the finger until it lifts.
    public func touchBegan(_ touch: Int, at point: LayoutPoint, time: TimeInterval) {
        if activeTouch != nil { finishActiveTouch(commit: true, at: time) }
        activeTouch = touch
        let index = keyIndex(at: point)
        heldKeyIndex = index
        activeKind = index.flatMap { layout?.keys[$0].kind }
        switch activeKind {
        case .shift?: send(.shift, at: time)
        case .delete?: send(.deleteDown, at: time)
        default: notify()
        }
    }

    /// The finger `touch` moved to `point`. A letter, the space bar or Return under it now is the one it will type.
    public func touchMoved(_ touch: Int, to point: LayoutPoint, time: TimeInterval) {
        guard touch == activeTouch else { return }
        switch activeKind {
        case .shift?, .delete?: return
        default: break
        }
        let index = keyIndex(at: point)
        if index != heldKeyIndex {
            heldKeyIndex = index
            activeKind = index.flatMap { layout?.keys[$0].kind }
            notify()
        }
    }

    /// The finger `touch` lifted at `point`.
    public func touchEnded(_ touch: Int, at point: LayoutPoint, time: TimeInterval) {
        guard touch == activeTouch else { return }
        touchMoved(touch, to: point, time: time)
        finishActiveTouch(commit: true, at: time)
    }

    /// The finger `touch` was cancelled: it types nothing, and ends a Delete hold.
    public func touchCancelled(_ touch: Int, time: TimeInterval) {
        guard touch == activeTouch else { return }
        finishActiveTouch(commit: false, at: time)
    }

    /// The scheduler's timer fired, at `time`.
    public func tick(at time: TimeInterval) {
        send(.tick, at: time)
    }

    private func finishActiveTouch(commit: Bool, at time: TimeInterval) {
        let kind = activeKind
        activeTouch = nil
        activeKind = nil
        heldKeyIndex = nil
        switch kind {
        case .letter(let scalar)? where commit: send(.character(scalar), at: time)
        case .space? where commit: send(.space, at: time)
        case .returnKey? where commit: send(.returnKey, at: time)
        case .delete?: send(.deleteUp, at: time)
        default: notify()
        }
    }

    private func keyIndex(at point: LayoutPoint) -> Int? {
        guard let layout, let key = layout.key(at: point) else { return nil }
        var index = 0
        while index < layout.keys.count {
            if layout.keys[index].frame == key.frame { return index }
            index += 1
        }
        return nil
    }

    private func send(_ event: KeyEvent, at time: TimeInterval) {
        let output = engine.handle(event, at: time, in: field.typingContext)
        var deletes = output.deleteCount
        while deletes > 0 {
            field.deleteBackward()
            deletes -= 1
        }
        if !output.insertion.isEmpty { field.insertText(output.insertion) }
        scheduler.requestTick(at: output.nextTick, for: self)
        notify()
    }

    private func notify() {
        observer?.typingStateDidChange(self)
    }
}

/// The real scheduler: one `Timer` on the main run loop, replaced at each request.
@MainActor
public final class TimerTickScheduler: TickScheduler {
    private var timer: Timer?

    /// A scheduler with nothing scheduled.
    public init() {}

    /// See `TickScheduler`.
    public func requestTick(at time: TimeInterval?, for typing: KeyboardTyping) {
        timer?.invalidate()
        timer = nil
        guard let time else { return }
        let delay = max(0, time - ProcessInfo.processInfo.systemUptime)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak typing] _ in
            MainActor.assumeIsolated {
                typing?.tick(at: ProcessInfo.processInfo.systemUptime)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
