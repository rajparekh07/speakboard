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

/// Told when the typing state the view draws (Shift, the held keys, the return key) may have changed.
@MainActor
public protocol KeyboardTypingObserver: AnyObject {
    /// The state changed; read it from the `KeyboardTyping`.
    func typingStateDidChange(_ typing: KeyboardTyping)
}

/// The keyboard's adapter between touches and the field (ADR-0005: the Apple side is thin). Touches arrive as plain
/// points in the layout's coordinates and times in seconds. The core's touch bookkeeping (`KeyTouches`) finds the key
/// under each finger with the nearest-key hit-test and says which key events the touches make, and when; the core's
/// typing engine turns each event into text operations; and this applies them to the field at once, in the same call:
/// first the backward deletes, then one insertion.
///
/// The rules for touches are `KeyTouches`'s (KEY-24), in short:
/// - Every point below the suggestion strip belongs to a key (`KeyboardLayout.keyIndex(nearest:)`), so a finger that
///   lands, moves or lifts in a gap between keys still has a key.
/// - A letter, the space bar and Return act when the finger lifts, on the key under it then. Shift acts when the
///   finger lands. Delete deletes when the finger lands and repeats until it lifts: `.deleteDown`, then `.tick` at
///   each time the engine asks for, then `.deleteUp`.
/// - Several fingers: each is followed by its identity, and a finger's key is committed at its own lift or when a
///   later finger lands, whichever comes first, so keys come out in the order the fingers landed. A later finger
///   landing ends a Delete hold.
/// - A cancelled finger types nothing; on Delete it still sends `.deleteUp`.
/// - The "123" key, the emoji key, Apple's dictation key and the next-keyboard key type nothing here (KEY-62 does
///   not cover them; the next-keyboard key is the view's, through UIKit). The engine has no event for them yet.
/// - Shift held as a modifier is not modelled: the engine has only a Shift tap (see `KeyTouches`).
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
    /// The layout touches are hit-tested against. Nil: touches do nothing. A new layout (another device class or
    /// orientation) drops every finger down, as if cancelled: their key indices were the old layout's.
    public var layout: KeyboardLayout? {
        didSet { apply(touches.endAll(), at: lastTime) }
    }
    /// Told when the drawn state may have changed.
    public weak var observer: KeyboardTypingObserver?
    /// Which hit-test finds the key under a finger: `.nearest`, unless a test asks for `.exact`, the hit-test before
    /// KEY-24, to show what the nearest-key rule changes.
    public var hitTesting: HitTesting {
        get { touches.hitTesting }
        set { touches.hitTesting = newValue }
    }

    private let scheduler: TickScheduler
    private var touches = KeyTouches()
    private var sessionDocument: UUID?
    /// The time of the last event sent, for the `.deleteUp` a layout change sends.
    private var lastTime: TimeInterval = 0

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

    /// Whether a finger is on key `index` of the layout, so it is drawn held. Several keys can be held at once.
    public func holds(_ index: Int) -> Bool {
        touches.holds(index)
    }

    /// The keyboard appeared: a fresh engine for this field session, which then reads the field. Fingers still down
    /// from before are forgotten.
    public func beginFieldSession(at time: TimeInterval) {
        if let engine = TypingEngine(locale: locale) { self.engine = engine }
        sessionDocument = field.documentIdentifier
        _ = touches.endAll()
        scheduler.requestTick(at: nil, for: self)
        send(.contextChanged, at: time)
        notify()
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
        notify()
    }

    /// The keyboard is going away: no finger types anything more, and a Delete hold ends, as if every touch were
    /// cancelled, in case UIKit does not cancel them.
    public func endTouches(at time: TimeInterval) {
        apply(touches.endAll(), at: time)
        scheduler.requestTick(at: nil, for: self)
    }

    /// A finger landed at `point`. `touch` names the finger until it lifts.
    public func touchBegan(_ touch: Int, at point: LayoutPoint, time: TimeInterval) {
        guard let layout else { return }
        apply(touches.began(touch, at: point, in: layout), at: time)
    }

    /// The finger `touch` moved to `point`. A letter, the space bar or Return under it now is the one it will type.
    public func touchMoved(_ touch: Int, to point: LayoutPoint, time: TimeInterval) {
        guard let layout else { return }
        if touches.moved(touch, to: point, in: layout) { notify() }
    }

    /// The finger `touch` lifted at `point`.
    public func touchEnded(_ touch: Int, at point: LayoutPoint, time: TimeInterval) {
        guard let layout else { return }
        apply(touches.ended(touch, at: point, in: layout), at: time)
    }

    /// The finger `touch` was cancelled: it types nothing, and ends a Delete hold.
    public func touchCancelled(_ touch: Int, time: TimeInterval) {
        apply(touches.cancelled(touch), at: time)
    }

    /// The scheduler's timer fired, at `time`.
    public func tick(at time: TimeInterval) {
        send(.tick, at: time)
        notify()
    }

    /// Sends the events in order, then tells the observer once: the held keys may have changed even with no event.
    private func apply(_ events: KeyEvents, at time: TimeInterval) {
        if let first = events.first { send(first, at: time) }
        if let second = events.second { send(second, at: time) }
        notify()
    }

    private func send(_ event: KeyEvent, at time: TimeInterval) {
        lastTime = time
        let output = engine.handle(event, at: time, in: field.typingContext)
        var deletes = output.deleteCount
        while deletes > 0 {
            field.deleteBackward()
            deletes -= 1
        }
        if !output.insertion.isEmpty { field.insertText(output.insertion) }
        scheduler.requestTick(at: output.nextTick, for: self)
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
