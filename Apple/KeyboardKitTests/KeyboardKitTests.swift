import Foundation
import KeyboardKit
import SpeakboardCore
import Testing
import UIKit

// The keyboard view and its typing adapter, driven as the extension drives them, with a fake text field and a fake
// clock. Which class and orientation a screen gets is the core's (DeviceClass.match), tested on Linux; the typing
// rules are the core's, tested on Linux. These tests check the view draws what the core and the tokens say, and that
// touches on it type through the real engine into the field.

/// A text field: the whole text is before the cursor.
@MainActor
final class FakeField: KeyboardTextField {
    var text = ""
    var fieldAutocapitalization: Autocapitalization = .sentences
    var fieldReturnKeyType: ReturnKeyType = .default
    var fieldEnablesReturnKeyAutomatically = false
    var documentIdentifier: UUID? = UUID()
    var documentContextBeforeInput: String? { text }
    var hasText: Bool { !text.isEmpty }
    func insertText(_ text: String) { self.text += text }
    func deleteBackward() {
        if !text.isEmpty { text.removeLast() }
    }
}

/// A clock the test moves by hand: it records the tick the adapter asks for.
@MainActor
final class FakeScheduler: TickScheduler {
    var requested: TimeInterval?
    func requestTick(at time: TimeInterval?, for typing: KeyboardTyping) { requested = time }
}

/// The real view and adapter on a fake field, with taps by key.
@MainActor
final class Rig {
    let field = FakeField()
    let scheduler = FakeScheduler()
    let typing: KeyboardTyping
    let view: KeyboardView
    let layout: KeyboardLayout
    /// Taps land this many keys after the one asked for: 0 is right; anything else is a broken keyboard, for the
    /// test that shows the typing test can fail.
    let keyOffset: Int
    var clock: TimeInterval = 1000
    private var nextTouch = 1

    init(
        deviceClass: DeviceClass = .iphone402x874, autocapitalization: Autocapitalization = .sentences,
        text: String = "", connected: Bool = true, keyOffset: Int = 0
    ) throws {
        field.fieldAutocapitalization = autocapitalization
        field.text = text
        typing = try #require(KeyboardTyping(field: field, scheduler: scheduler))
        view = KeyboardView(typing: connected ? typing : nil)
        let height = view.update(screenWidth: deviceClass.screenWidth, screenHeight: deviceClass.screenHeight)
        layout = try #require(view.layout)
        #expect(height == layout.size.height)
        view.frame = CGRect(x: 0, y: 0, width: layout.size.width, height: layout.size.height)
        self.keyOffset = keyOffset
        typing.beginFieldSession(at: clock)
    }

    func index(of kind: KeyKind) throws -> Int {
        try #require(layout.keys.firstIndex { $0.kind == kind })
    }

    func letter(_ character: Character) -> KeyKind {
        .letter(character.unicodeScalars.first ?? "a")
    }

    func point(_ kind: KeyKind) throws -> CGPoint {
        let position = (try index(of: kind) + keyOffset) % layout.keys.count
        let center = layout.keys[position].frame.center
        return CGPoint(x: center.x, y: center.y)
    }

    func newTouch() -> Int {
        nextTouch += 1
        return nextTouch
    }

    /// A tap: down, 50 ms, up, 100 ms.
    func tap(_ kind: KeyKind) throws {
        let touch = newTouch()
        let location = try point(kind)
        view.touchDown(touch, at: location, time: clock)
        clock += 0.05
        view.touchUp(touch, at: location, time: clock)
        clock += 0.1
    }

    func type(_ text: String) throws {
        for character in text {
            try tap(character == " " ? .space : letter(character))
        }
    }
}

/// Types "hi", two spaces, "x" and a delete, and returns the field's text.
@MainActor
func typeHiScript(_ rig: Rig) throws -> String {
    try rig.type("hi  x")
    try rig.tap(.delete)
    return rig.field.text
}

@Suite("KeyboardKit: typing through the keyboard view")
@MainActor
struct KeyboardTypingTests {
    @Test("Hi, a double space, x and a delete: shift, the full stop and delete, through the real view and engine")
    func typesAShortText() throws {
        let rig = try Rig()
        try rig.type("hi")
        #expect(rig.field.text == "Hi", "the field's sentence capitalisation turns Shift on for the first letter")
        try rig.type("  ")
        #expect(rig.field.text == "Hi. ", "a quick double space types a full stop")
        try rig.type("x")
        #expect(rig.field.text == "Hi. X", "a sentence starts after the full stop")
        try rig.tap(.delete)
        #expect(rig.field.text == "Hi. ")
    }

    @Test("The typing test can fail: a keyboard whose keys are off by one, or not wired to the engine, types wrong")
    func brokenVariantsFail() throws {
        #expect(try typeHiScript(Rig()) == "Hi. ")
        #expect(try typeHiScript(Rig(keyOffset: 1)) != "Hi. ")
        #expect(try typeHiScript(Rig(connected: false)) != "Hi. ")
        #expect(try typeHiScript(Rig(connected: false)) == "")
    }

    @Test("Caps lock: a double tap on Shift locks it, the letters and the Shift glyph show it, and a tap unlocks")
    func capsLock() throws {
        let rig = try Rig(autocapitalization: .none)
        let shift = try rig.index(of: .shift)
        let a = try rig.index(of: rig.letter("a"))
        #expect(rig.view.glyphName(at: shift) == "shift")
        #expect(rig.view.labelText(at: a) == "a")
        try rig.tap(.shift)
        #expect(rig.typing.shiftState == .manual)
        #expect(rig.view.glyphName(at: shift) == "shift.fill")
        try rig.tap(.shift)
        #expect(rig.typing.shiftState == .locked)
        #expect(rig.view.glyphName(at: shift) == "capslock.fill")
        #expect(rig.view.labelText(at: a) == "A")
        try rig.type("ab")
        #expect(rig.field.text == "AB")
        #expect(rig.typing.shiftState == .locked)
        rig.clock += 1
        try rig.tap(.shift)
        #expect(rig.typing.shiftState == .off)
        #expect(rig.view.labelText(at: a) == "a")
        try rig.type("c")
        #expect(rig.field.text == "ABc")
    }

    @Test("A held delete repeats at the times the engine asks for, on the test's clock, and stops when lifted")
    func deleteRepeat() throws {
        let rig = try Rig(autocapitalization: .none, text: "abcdef")
        let point = try rig.point(.delete)
        let start = rig.clock
        rig.view.touchDown(7, at: point, time: start)
        #expect(rig.field.text == "abcde", "touch-down deletes at once")
        let first = try #require(rig.scheduler.requested)
        #expect(abs(first - (start + TypingTimings.estimated.deleteInitialDelay)) < 1e-9)
        rig.typing.tick(at: first)
        #expect(rig.field.text == "abcd")
        let second = try #require(rig.scheduler.requested)
        #expect(abs(second - (first + TypingTimings.estimated.deleteRepeatInterval)) < 1e-9)
        rig.typing.tick(at: second)
        #expect(rig.field.text == "abc")
        rig.view.touchUp(7, at: point, time: second + 0.01)
        #expect(rig.scheduler.requested == nil, "lifting stops the repeat")
        rig.typing.tick(at: second + 1)
        #expect(rig.field.text == "abc", "a late tick after the lift deletes nothing")
    }

    @Test("A second finger finishes the first: no letter lost or doubled, and it ends a delete hold")
    func secondFinger() throws {
        let rig = try Rig(autocapitalization: .none)
        let a = try rig.point(rig.letter("a"))
        let b = try rig.point(rig.letter("b"))
        rig.view.touchDown(1, at: a, time: rig.clock)
        rig.view.touchDown(2, at: b, time: rig.clock + 0.03)
        #expect(rig.field.text == "a", "the first finger's letter is typed when the second lands")
        rig.view.touchUp(1, at: a, time: rig.clock + 0.06)
        #expect(rig.field.text == "a", "the first finger's own lift types nothing more")
        rig.view.touchUp(2, at: b, time: rig.clock + 0.09)
        #expect(rig.field.text == "ab")

        rig.clock += 1
        let delete = try rig.point(.delete)
        let x = try rig.point(rig.letter("x"))
        rig.view.touchDown(3, at: delete, time: rig.clock)
        #expect(rig.field.text == "a")
        #expect(rig.scheduler.requested != nil)
        rig.view.touchDown(4, at: x, time: rig.clock + 0.1)
        #expect(rig.scheduler.requested == nil, "the second finger ends the delete hold")
        rig.view.touchUp(4, at: x, time: rig.clock + 0.2)
        rig.view.touchUp(3, at: delete, time: rig.clock + 0.3)
        #expect(rig.field.text == "ax")
    }

    @Test("A cancelled touch types nothing, and a cancelled delete stops repeating")
    func cancelled() throws {
        let rig = try Rig(autocapitalization: .none, text: "ab")
        rig.view.touchDown(1, at: try rig.point(rig.letter("q")), time: rig.clock)
        rig.view.touchCancel(1, time: rig.clock + 0.05)
        #expect(rig.field.text == "ab")
        rig.view.touchDown(2, at: try rig.point(.delete), time: rig.clock + 0.1)
        #expect(rig.field.text == "a")
        rig.view.touchCancel(2, time: rig.clock + 0.2)
        #expect(rig.scheduler.requested == nil)
    }

    @Test("An identifier that arrives after the keyboard keeps the session: caps lock stays on; another one resets it")
    func lateDocumentIdentifier() throws {
        let rig = try Rig(autocapitalization: .none)
        rig.field.documentIdentifier = nil
        rig.typing.beginFieldSession(at: rig.clock)
        try rig.tap(.shift)
        try rig.tap(.shift)
        #expect(rig.typing.shiftState == .locked)
        rig.field.documentIdentifier = UUID()
        rig.typing.textDidChange(at: rig.clock)
        #expect(rig.typing.shiftState == .locked, "the first identifier is this session's: no new engine")
        try rig.type("a")
        #expect(rig.field.text == "A")
        rig.field.documentIdentifier = UUID()
        rig.typing.textDidChange(at: rig.clock)
        #expect(rig.typing.shiftState == .off, "another identifier is another field: a fresh engine")
    }

    @Test("The keyboard going away ends a delete hold and types nothing for a held letter")
    func endTouches() throws {
        let rig = try Rig(autocapitalization: .none, text: "abc")
        rig.view.touchDown(1, at: try rig.point(.delete), time: rig.clock)
        #expect(rig.field.text == "ab")
        #expect(rig.scheduler.requested != nil)
        rig.typing.endTouches(at: rig.clock + 0.1)
        #expect(rig.scheduler.requested == nil)
        rig.view.touchDown(2, at: try rig.point(rig.letter("q")), time: rig.clock + 0.2)
        rig.typing.endTouches(at: rig.clock + 0.3)
        rig.view.touchUp(2, at: try rig.point(rig.letter("q")), time: rig.clock + 0.4)
        #expect(rig.field.text == "ab")
    }

    @Test("A finger that slides from one letter to another types the one it lifts on")
    func slide() throws {
        let rig = try Rig(autocapitalization: .none)
        rig.view.touchDown(1, at: try rig.point(rig.letter("q")), time: rig.clock)
        rig.view.touchMove(1, to: try rig.point(rig.letter("w")), time: rig.clock + 0.05)
        rig.view.touchUp(1, at: try rig.point(rig.letter("w")), time: rig.clock + 0.1)
        #expect(rig.field.text == "w")
    }
}

@Suite("KeyboardKit: drawing the keys")
@MainActor
struct KeyboardDrawingTests {
    static func expectedColor(_ cell: ColorCell) -> CGColor {
        UIColor(
            red: CGFloat(cell.color.red), green: CGFloat(cell.color.green), blue: CGFloat(cell.color.blue),
            alpha: CGFloat(cell.color.alpha)
        ).cgColor
    }

    /// Whether two frames are equal up to Core Animation's rounding: a layer keeps its position and bounds, and
    /// computes its frame from them, so a frame read back can differ from the one set in the last bits.
    static func same(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 1e-9 && abs(a.minY - b.minY) < 1e-9 && abs(a.width - b.width) < 1e-9
            && abs(a.height - b.height) < 1e-9
    }

    static func check(_ rig: Rig, _ appearance: Appearance) {
        let palette = Palette.of(appearance)
        #expect(rig.view.appearance == appearance)
        #expect(rig.view.layer.backgroundColor == expectedColor(palette.keyboardBackdropFallback))
        #expect(rig.view.faceLayers.count == rig.layout.keys.count)
        for (index, key) in rig.layout.keys.enumerated() {
            let face = rig.view.faceLayers[index]
            let style = KeyStyle.of(key.kind, returnKey: .standard, appearance: appearance, metrics: rig.layout.metrics)
            let frame = CGRect(x: key.frame.x, y: key.frame.y, width: key.frame.width, height: key.frame.height)
            #expect(same(face.frame, frame), "\(key.kind): \(face.frame) is not \(frame)")
            #expect(face.backgroundColor == expectedColor(style.fill), "\(key.kind) \(appearance)")
            #expect(face.cornerRadius == CGFloat(style.cornerRadius.value))
            #expect(face.shadowOffset.height == CGFloat(style.shadow.offsetY.value))
            #expect(face.shadowRadius == 0)
        }
    }

    @Test("Each key's layer has the core's frame and the tokens' fill, radius and shadow, in light and in dark")
    func layers() throws {
        let rig = try Rig()
        rig.view.applyUserInterfaceStyle(.light)
        Self.check(rig, .light)
        rig.view.applyUserInterfaceStyle(.dark)
        Self.check(rig, .dark)
        rig.view.applyUserInterfaceStyle(.light)
        Self.check(rig, .light)
    }

    @Test("A held function key shows its pressed fill; a held letter shows no pressed face (the export has none)")
    func pressed() throws {
        let rig = try Rig(autocapitalization: .none)
        let shift = try rig.index(of: .shift)
        let q = try rig.index(of: rig.letter("q"))
        let metrics = rig.layout.metrics
        rig.view.touchDown(1, at: try rig.point(.shift), time: rig.clock)
        let shiftStyle = KeyStyle.of(.shift, returnKey: .standard, appearance: rig.view.appearance, metrics: metrics)
        #expect(
            rig.view.faceLayers[shift].backgroundColor
                == KeyboardDrawingTests.expectedColor(try #require(shiftStyle.pressedFill)))
        rig.view.touchUp(1, at: try rig.point(.shift), time: rig.clock + 0.05)
        #expect(rig.view.faceLayers[shift].backgroundColor == KeyboardDrawingTests.expectedColor(shiftStyle.fill))
        rig.view.touchDown(2, at: try rig.point(rig.letter("q")), time: rig.clock + 0.5)
        let letterStyle = KeyStyle.of(
            rig.letter("q"), returnKey: .standard, appearance: rig.view.appearance, metrics: metrics)
        #expect(rig.view.faceLayers[q].backgroundColor == KeyboardDrawingTests.expectedColor(letterStyle.fill))
    }

    @Test("Labels: letters, space, 123 and the return key's title follow the field; glyph keys show their symbols")
    func labels() throws {
        let rig = try Rig(autocapitalization: .none)
        #expect(rig.view.labelText(at: try rig.index(of: rig.letter("q"))) == "q")
        #expect(rig.view.labelText(at: try rig.index(of: .space)) == "space")
        #expect(rig.view.labelText(at: try rig.index(of: .modeSwitch)) == "123")
        #expect(rig.view.labelText(at: try rig.index(of: .returnKey)) == "return")
        #expect(rig.view.glyphName(at: try rig.index(of: .delete)) == "delete.left")
        #expect(rig.view.glyphName(at: try rig.index(of: .emoji)) == "face.smiling")
        rig.field.fieldReturnKeyType = .go
        rig.typing.textDidChange(at: rig.clock)
        let returnIndex = try rig.index(of: .returnKey)
        #expect(rig.view.labelText(at: returnIndex) == "go")
        let prominent = KeyStyle.of(
            .returnKey, returnKey: .prominent, appearance: rig.view.appearance, metrics: rig.layout.metrics)
        #expect(rig.view.faceLayers[returnIndex].backgroundColor == KeyboardDrawingTests.expectedColor(prominent.fill))
        // A return key type the export does not give a face: the standard face, with its own title.
        rig.field.fieldReturnKeyType = .next
        rig.typing.textDidChange(at: rig.clock)
        let standard = KeyStyle.of(
            .returnKey, returnKey: .standard, appearance: rig.view.appearance, metrics: rig.layout.metrics)
        #expect(rig.view.labelText(at: returnIndex) == "next")
        #expect(rig.view.faceLayers[returnIndex].backgroundColor == KeyboardDrawingTests.expectedColor(standard.fill))
    }

    @Test("The next-keyboard key is drawn only when the system asks for it")
    func inputModeSwitchKey() throws {
        let rig = try Rig(deviceClass: .iphone375x667)
        let globe = try rig.index(of: .globe)
        #expect(rig.view.faceLayers[globe].isHidden)
        rig.view.showsInputModeSwitchKey = true
        #expect(!rig.view.faceLayers[globe].isHidden)
        #expect(rig.view.glyphName(at: globe) == "globe")
    }

    @Test("Its height is the core's keyboard height for the device", arguments: DeviceClass.allCases)
    func height(deviceClass: DeviceClass) throws {
        let view = KeyboardView(typing: nil)
        let height = view.update(screenWidth: deviceClass.screenWidth, screenHeight: deviceClass.screenHeight)
        let layout = try #require(KeyboardLayout(locale: .english, deviceClass: deviceClass, orientation: .portrait))
        #expect(height == layout.size.height)
        #expect(view.faceLayers.count == layout.keys.count)
    }

    @Test("A landscape screen gets the landscape layout")
    func landscape() throws {
        let view = KeyboardView(typing: nil)
        let height = view.update(screenWidth: 874, screenHeight: 402)
        let layout = try #require(
            KeyboardLayout(locale: .english, deviceClass: .iphone402x874, orientation: .landscape))
        #expect(view.layout?.orientation == .landscape)
        #expect(height == layout.size.height)
    }
}
