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

    /// A tap at `point`: down, 50 ms, up, 100 ms.
    func tap(at point: CGPoint) {
        let touch = newTouch()
        view.touchDown(touch, at: point, time: clock)
        clock += 0.05
        view.touchUp(touch, at: point, time: clock)
        clock += 0.1
    }

    func frame(_ kind: KeyKind) throws -> LayoutRect {
        layout.keys[try index(of: kind)].frame
    }

    static func cgPoint(_ point: LayoutPoint) -> CGPoint {
        CGPoint(x: point.x, y: point.y)
    }

    static func layoutPoint(_ point: CGPoint) -> LayoutPoint {
        LayoutPoint(x: Double(point.x), y: Double(point.y))
    }

    /// A point in the gap below "g", a quarter of the way down to the row below: the nearest key is "g".
    func gapBelowG() throws -> CGPoint {
        let g = try frame(letter("g"))
        let below = try frame(letter("b"))
        return Self.cgPoint(LayoutPoint(x: g.center.x, y: g.maxY + (below.minY - g.maxY) / 4))
    }

    /// A point in the margin left of "a", at its middle height: the nearest key is "a".
    func besideA() throws -> CGPoint {
        let a = try frame(letter("a"))
        return Self.cgPoint(LayoutPoint(x: a.minX / 2, y: a.center.y))
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

@Suite("KeyboardKit: hit targets and several fingers through the keyboard view (KEY-24)")
@MainActor
struct KeyboardTouchTests {
    @Test(
        "A tap in a gap between rows, and one beside the a row, type the nearest letter; the exact hit-test types none",
        arguments: [HitTesting.nearest, .exact])
    func gapTaps(hitTesting: HitTesting) throws {
        let rig = try Rig(autocapitalization: .none)
        rig.typing.hitTesting = hitTesting
        let gap = try rig.gapBelowG()
        let margin = try rig.besideA()
        #expect(rig.layout.key(at: Rig.layoutPoint(gap)) == nil, "the point is in a gap")
        #expect(rig.layout.key(at: Rig.layoutPoint(margin)) == nil, "the point is in the margin")
        rig.tap(at: gap)
        rig.tap(at: margin)
        #expect(rig.field.text == (hitTesting == .nearest ? "ga" : ""), "\(hitTesting)")
    }

    @Test(
        "A finger that lands on a key and lifts in a gap types the key; the exact hit-test types none",
        arguments: [HitTesting.nearest, .exact])
    func liftInAGap(hitTesting: HitTesting) throws {
        let rig = try Rig(autocapitalization: .none)
        rig.typing.hitTesting = hitTesting
        let g = try rig.frame(rig.letter("g"))
        let lift = Rig.cgPoint(LayoutPoint(x: g.center.x, y: g.maxY + 1))
        #expect(rig.layout.key(at: Rig.layoutPoint(lift)) == nil)
        rig.view.touchDown(1, at: try rig.point(rig.letter("g")), time: rig.clock)
        rig.view.touchMove(1, to: lift, time: rig.clock + 0.03)
        rig.view.touchUp(1, at: lift, time: rig.clock + 0.05)
        #expect(rig.field.text == (hitTesting == .nearest ? "g" : ""), "\(hitTesting)")
    }

    @Test("Three overlapping fingers type in the order they landed, with lifts in every order")
    func rollover() throws {
        let orders = [[1, 2, 3], [1, 3, 2], [2, 1, 3], [2, 3, 1], [3, 1, 2], [3, 2, 1]]
        for order in orders {
            let rig = try Rig(autocapitalization: .none)
            let t = try rig.point(rig.letter("t"))
            let h = try rig.point(rig.letter("h"))
            let e = try rig.point(rig.letter("e"))
            let points = [1: t, 2: h, 3: e]
            for id in 1...3 {
                rig.view.touchDown(id, at: points[id] ?? .zero, time: rig.clock)
                rig.clock += 0.03
            }
            #expect(rig.field.text == "th", "each finger's landing commits the one before it")
            for id in order {
                rig.view.touchUp(id, at: points[id] ?? .zero, time: rig.clock)
                rig.clock += 0.03
            }
            #expect(rig.field.text == "the", "lifts in the order \(order)")
        }
    }

    @Test("Several fingers down hold several keys: each is drawn pressed until its own finger lifts")
    func heldKeys() throws {
        let rig = try Rig(autocapitalization: .none, text: "abc")
        let shift = try rig.index(of: .shift)
        let delete = try rig.index(of: .delete)
        let metrics = rig.layout.metrics
        // Shift and Delete are both function keys: the same fill at rest and the same pressed fill.
        let style = KeyStyle.of(.shift, returnKey: .standard, appearance: rig.view.appearance, metrics: metrics)
        let pressed = KeyboardDrawingTests.expectedColor(try #require(style.pressedFill))
        let rest = KeyboardDrawingTests.expectedColor(style.fill)
        #expect(KeyStyle.of(.delete, returnKey: .standard, appearance: rig.view.appearance, metrics: metrics) == style)
        rig.view.touchDown(1, at: try rig.point(.delete), time: rig.clock)
        rig.view.touchDown(2, at: try rig.point(.shift), time: rig.clock + 0.05)
        #expect(rig.typing.holds(delete) && rig.typing.holds(shift))
        #expect(rig.view.faceLayers[delete].backgroundColor == pressed)
        #expect(rig.view.faceLayers[shift].backgroundColor == pressed)
        rig.view.touchUp(1, at: try rig.point(.delete), time: rig.clock + 0.1)
        #expect(rig.view.faceLayers[delete].backgroundColor == rest)
        #expect(rig.view.faceLayers[shift].backgroundColor == pressed)
        rig.view.touchUp(2, at: try rig.point(.shift), time: rig.clock + 0.15)
        #expect(rig.view.faceLayers[shift].backgroundColor == rest)
    }

    @Test("Shift held as a modifier is a gap in the engine: the first letter is upper case, the next lower case")
    func shiftHeld() throws {
        let rig = try Rig(autocapitalization: .none)
        let shift = try rig.point(.shift)
        rig.view.touchDown(1, at: shift, time: rig.clock)
        #expect(rig.typing.shiftState == .manual)
        rig.view.touchDown(2, at: try rig.point(rig.letter("a")), time: rig.clock + 0.1)
        rig.view.touchUp(2, at: try rig.point(rig.letter("a")), time: rig.clock + 0.15)
        rig.view.touchDown(3, at: try rig.point(rig.letter("b")), time: rig.clock + 0.2)
        rig.view.touchUp(3, at: try rig.point(rig.letter("b")), time: rig.clock + 0.25)
        rig.view.touchUp(1, at: shift, time: rig.clock + 0.3)
        // The engine has only a Shift tap, used up by the first letter (KeyTouches.swift records the gap). A Shift
        // held as a modifier would type "AB" and turn off at the lift.
        #expect(rig.field.text == "Ab")
        #expect(rig.typing.shiftState == .off)
    }

    @Test("Delete held while another finger types: the hold ends when the finger lands, the letter types, no repeat")
    func deleteHeldWhileTyping() throws {
        let rig = try Rig(autocapitalization: .none, text: "abcdef")
        let delete = try rig.point(.delete)
        let x = try rig.point(rig.letter("x"))
        let start = rig.clock
        rig.view.touchDown(1, at: delete, time: start)
        #expect(rig.field.text == "abcde")
        let first = try #require(rig.scheduler.requested)
        rig.typing.tick(at: first)
        #expect(rig.field.text == "abcd")
        rig.view.touchDown(2, at: x, time: first + 0.05)
        #expect(rig.scheduler.requested == nil, "the landing finger ends the hold")
        rig.typing.tick(at: first + 1)
        #expect(rig.field.text == "abcd", "a late tick deletes nothing")
        rig.view.touchUp(2, at: x, time: first + 0.1)
        #expect(rig.field.text == "abcdx")
        rig.view.touchUp(1, at: delete, time: first + 0.2)
        #expect(rig.field.text == "abcdx", "Delete's own lift deletes nothing more")
        #expect(rig.scheduler.requested == nil)
    }

    @Test("A hidden next-keyboard key takes no touch: a finger on it holds its neighbour; shown, it holds the key")
    func hiddenInputModeSwitchKey() throws {
        let rig = try Rig(deviceClass: .iphone375x667, autocapitalization: .none)
        let globe = try rig.index(of: .globe)
        let modeSwitch = try rig.index(of: .modeSwitch)
        let frame = try rig.frame(.globe)
        let leftHalf = Rig.cgPoint(LayoutPoint(x: frame.minX + 1, y: frame.center.y))
        #expect(!rig.view.showsInputModeSwitchKey)
        #expect(!rig.typing.showsInputModeSwitchKey, "the view tells the adapter")
        rig.view.touchDown(1, at: leftHalf, time: rig.clock)
        #expect(!rig.typing.holds(globe) && rig.typing.holds(modeSwitch))
        rig.view.touchUp(1, at: leftHalf, time: rig.clock + 0.05)
        rig.view.showsInputModeSwitchKey = true
        #expect(rig.typing.showsInputModeSwitchKey)
        rig.view.touchDown(2, at: leftHalf, time: rig.clock + 0.1)
        #expect(rig.typing.holds(globe) && !rig.typing.holds(modeSwitch))
        rig.view.touchUp(2, at: leftHalf, time: rig.clock + 0.15)
        #expect(rig.field.text == "")
    }

    @Test("A cancel among several fingers: nothing lost, doubled or left repeating")
    func cancelAmongSeveral() throws {
        let rig = try Rig(autocapitalization: .none, text: "ab")
        let t = try rig.point(rig.letter("t"))
        let h = try rig.point(rig.letter("h"))
        let delete = try rig.point(.delete)
        rig.view.touchDown(1, at: t, time: rig.clock)
        rig.view.touchDown(2, at: h, time: rig.clock + 0.03)
        rig.view.touchDown(3, at: delete, time: rig.clock + 0.06)
        #expect(rig.field.text == "abt", "t and h are committed by the landings after them; Delete deletes h")
        #expect(rig.scheduler.requested != nil)
        rig.view.touchCancel(3, time: rig.clock + 0.09)
        #expect(rig.scheduler.requested == nil, "the cancelled Delete stops repeating")
        rig.view.touchCancel(1, time: rig.clock + 0.09)
        rig.view.touchUp(2, at: h, time: rig.clock + 0.12)
        #expect(rig.field.text == "abt", "the finished fingers' cancel and lift type nothing more")
        try rig.tap(rig.letter("e"))
        #expect(rig.field.text == "abte")
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

    /// The colour of the most opaque pixel of `image`, un-premultiplied, from 0 to 1, or nil if it has no opaque
    /// pixel. Read from the image's own pixels, not from what the view says it drew.
    static func inkColor(_ image: CGImage) -> (red: Double, green: Double, blue: Double)? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var best = 0
        var bestAlpha: UInt8 = 0
        for index in stride(from: 0, to: pixels.count, by: 4) where pixels[index + 3] > bestAlpha {
            bestAlpha = pixels[index + 3]
            best = index
        }
        guard bestAlpha > 200 else { return nil }
        let alpha = Double(bestAlpha)
        return (Double(pixels[best]) / alpha, Double(pixels[best + 1]) / alpha, Double(pixels[best + 2]) / alpha)
    }

    /// Checks every glyph key's layer holds an image whose ink is `key.label` in `appearance`, and returns the images.
    static func checkGlyphs(_ rig: Rig, _ appearance: Appearance, _ indices: [Int]) -> [CGImage?] {
        let label = Palette.of(appearance).keyLabel.color
        return indices.map { index in
            let image = rig.view.glyphImage(at: index)
            #expect(image != nil, "key \(index) shows its glyph image in \(appearance)")
            if let image, let ink = inkColor(image) {
                #expect(
                    abs(ink.red - label.red) < 0.1, "key \(index) in \(appearance): red \(ink.red), not \(label.red)")
                #expect(abs(ink.green - label.green) < 0.1, "key \(index) in \(appearance)")
                #expect(abs(ink.blue - label.blue) < 0.1, "key \(index) in \(appearance)")
            } else {
                Issue.record("key \(index) in \(appearance): no opaque pixel in its glyph image")
            }
            return image
        }
    }

    @Test("Glyphs are redrawn in the new label colour when the appearance changes, light, dark and light again")
    func glyphsFollowTheAppearance() throws {
        // The layers are first drawn in light (as the extension may, before its trait callback says dark), then the
        // appearance changes with the keyboard up, as `simctl ui appearance dark` does in sim-keyboard.sh.
        let rig = try Rig(autocapitalization: .none)
        let indices = try [KeyKind.shift, .delete, .emoji].map { try rig.index(of: $0) }
        rig.view.applyUserInterfaceStyle(.light)
        let light = Self.checkGlyphs(rig, .light, indices)
        rig.view.applyUserInterfaceStyle(.dark)
        let dark = Self.checkGlyphs(rig, .dark, indices)
        for (before, after) in zip(light, dark) {
            #expect(before !== after, "the glyph layer's contents changed with the appearance")
        }
        rig.view.applyUserInterfaceStyle(.light)
        _ = Self.checkGlyphs(rig, .light, indices)
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

@Suite("KeyboardKit: a typing state change redraws only the layers that change (KEY-65)")
@MainActor
struct KeyboardRedrawTests {
    /// The keys whose layers were written between `before` and `after`, with how many writes of each kind.
    static func writes(_ before: [KeyLayerWrites], _ after: [KeyLayerWrites]) -> [Int: KeyLayerWrites] {
        var changed: [Int: KeyLayerWrites] = [:]
        for index in after.indices {
            let old = index < before.count ? before[index] : KeyLayerWrites()
            var delta = KeyLayerWrites()
            delta.face = after[index].face - old.face
            delta.fill = after[index].fill - old.fill
            delta.label = after[index].label - old.label
            delta.glyph = after[index].glyph - old.glyph
            if delta != KeyLayerWrites() { changed[index] = delta }
        }
        return changed
    }

    static func only(face: Int = 0, fill: Int = 0, label: Int = 0, glyph: Int = 0) -> KeyLayerWrites {
        var writes = KeyLayerWrites()
        writes.face = face
        writes.fill = fill
        writes.label = label
        writes.glyph = glyph
        return writes
    }

    @Test("A letter's press and lift write only that key's fill, once each")
    func letterPress() throws {
        let rig = try Rig(autocapitalization: .none)
        let q = try rig.index(of: rig.letter("q"))
        let start = rig.view.layerWrites
        rig.view.touchDown(1, at: try rig.point(rig.letter("q")), time: rig.clock)
        #expect(Self.writes(start, rig.view.layerWrites) == [q: Self.only(fill: 1)])
        rig.view.touchUp(1, at: try rig.point(rig.letter("q")), time: rig.clock + 0.05)
        #expect(Self.writes(start, rig.view.layerWrites) == [q: Self.only(fill: 2)])
        #expect(rig.field.text == "q")
    }

    @Test("Two fingers: the held keys' fills, and nothing else")
    func twoFingers() throws {
        let rig = try Rig(autocapitalization: .none)
        let t = try rig.index(of: rig.letter("t"))
        let h = try rig.index(of: rig.letter("h"))
        let start = rig.view.layerWrites
        rig.view.touchDown(1, at: try rig.point(rig.letter("t")), time: rig.clock)
        rig.view.touchDown(2, at: try rig.point(rig.letter("h")), time: rig.clock + 0.03)
        #expect(Self.writes(start, rig.view.layerWrites) == [t: Self.only(fill: 1), h: Self.only(fill: 1)])
        rig.view.touchUp(1, at: try rig.point(rig.letter("t")), time: rig.clock + 0.06)
        rig.view.touchUp(2, at: try rig.point(rig.letter("h")), time: rig.clock + 0.09)
        #expect(Self.writes(start, rig.view.layerWrites) == [t: Self.only(fill: 2), h: Self.only(fill: 2)])
        #expect(rig.field.text == "th")
    }

    @Test("A Shift change writes the letters' text and Shift's glyph; Shift's press and lift write its fill")
    func shiftChange() throws {
        let rig = try Rig(autocapitalization: .none)
        let shift = try rig.index(of: .shift)
        let letters = rig.layout.keys.indices.filter {
            if case .letter = rig.layout.keys[$0].kind { return true }
            return false
        }
        #expect(letters.count == 26)
        var expected: [Int: KeyLayerWrites] = [shift: Self.only(fill: 2, glyph: 1)]
        for index in letters { expected[index] = Self.only(label: 1) }

        let start = rig.view.layerWrites
        try rig.tap(.shift)
        #expect(rig.typing.shiftState == .manual)
        #expect(Self.writes(start, rig.view.layerWrites) == expected)
        #expect(rig.view.labelText(at: letters[0]) == "Q")
        #expect(rig.view.glyphName(at: shift) == "shift.fill")

        // A letter uses Shift up: its own fill twice, and the letters and Shift back to lower case.
        let a = try rig.index(of: rig.letter("a"))
        let before = rig.view.layerWrites
        try rig.tap(rig.letter("a"))
        #expect(rig.field.text == "A")
        var back: [Int: KeyLayerWrites] = [shift: Self.only(glyph: 1)]
        for index in letters { back[index] = Self.only(label: 1) }
        back[a] = Self.only(fill: 2, label: 1)
        #expect(Self.writes(before, rig.view.layerWrites) == back)
        #expect(rig.view.labelText(at: letters[0]) == "q")
        #expect(rig.view.glyphName(at: shift) == "shift")
    }

    @Test("Caps lock: manual to locked writes only Shift's glyph (and fill); locked to off the letters' case too")
    func capsLock() throws {
        let rig = try Rig(autocapitalization: .none)
        let shift = try rig.index(of: .shift)
        let letters = rig.layout.keys.indices.filter {
            if case .letter = rig.layout.keys[$0].kind { return true }
            return false
        }
        try rig.tap(.shift)
        #expect(rig.typing.shiftState == .manual)
        let manual = rig.view.layerWrites
        try rig.tap(.shift)
        #expect(rig.typing.shiftState == .locked)
        #expect(Self.writes(manual, rig.view.layerWrites) == [shift: Self.only(fill: 2, glyph: 1)])
        #expect(rig.view.glyphName(at: shift) == "capslock.fill")

        rig.clock += 1
        let locked = rig.view.layerWrites
        try rig.tap(.shift)
        #expect(rig.typing.shiftState == .off)
        var expected: [Int: KeyLayerWrites] = [shift: Self.only(fill: 2, glyph: 1)]
        for index in letters { expected[index] = Self.only(label: 1) }
        #expect(Self.writes(locked, rig.view.layerWrites) == expected)
        #expect(rig.view.glyphName(at: shift) == "shift")
        #expect(rig.view.labelText(at: letters[0]) == "q")
    }

    @Test("A tap on automatic Shift: Shift's fill and glyph; then a context change that changes nothing writes nothing")
    func shiftWithoutVisibleChange() throws {
        let rig = try Rig(autocapitalization: .sentences)
        #expect(rig.typing.shiftState == .automatic)
        let shift = try rig.index(of: .shift)
        let start = rig.view.layerWrites
        // A tap turns automatic Shift off: the letters to lower case, and Shift's fill (press and lift) and glyph.
        try rig.tap(.shift)
        #expect(rig.typing.shiftState == .off)
        #expect(Self.writes(start, rig.view.layerWrites)[shift] == Self.only(fill: 2, glyph: 1))
        // A context change that changes nothing writes nothing.
        let quiet = rig.view.layerWrites
        rig.typing.textDidChange(at: rig.clock)
        #expect(Self.writes(quiet, rig.view.layerWrites).isEmpty)
    }

    @Test("A return key type change writes only the return key, whole")
    func returnKeyChange() throws {
        let rig = try Rig(autocapitalization: .none)
        let returnIndex = try rig.index(of: .returnKey)
        let start = rig.view.layerWrites
        rig.field.fieldReturnKeyType = .go
        rig.typing.textDidChange(at: rig.clock)
        #expect(Self.writes(start, rig.view.layerWrites) == [returnIndex: Self.only(face: 1, fill: 1, label: 1)])
        #expect(rig.view.labelText(at: returnIndex) == "go")
        let prominent = KeyStyle.of(
            .returnKey, returnKey: .prominent, appearance: rig.view.appearance, metrics: rig.layout.metrics)
        #expect(rig.view.faceLayers[returnIndex].backgroundColor == KeyboardDrawingTests.expectedColor(prominent.fill))
    }

    @Test("An appearance change redraws every key: face, fill, and label or glyph")
    func appearanceChange() throws {
        let rig = try Rig(autocapitalization: .none)
        rig.view.applyUserInterfaceStyle(.light)
        let start = rig.view.layerWrites
        rig.view.applyUserInterfaceStyle(.dark)
        let writes = Self.writes(start, rig.view.layerWrites)
        #expect(writes.count == rig.layout.keys.count)
        for index in rig.layout.keys.indices {
            let key = writes[index] ?? KeyLayerWrites()
            #expect(key.face == 1 && key.fill == 1 && key.label + key.glyph == 1, "key \(index): \(key)")
        }
        KeyboardDrawingTests.check(rig, .dark)
        let again = rig.view.layerWrites
        rig.view.applyUserInterfaceStyle(.dark)
        #expect(Self.writes(again, rig.view.layerWrites).isEmpty, "the same appearance again redraws nothing")
    }

    @Test("A layout change rebuilds and redraws every key")
    func layoutChange() throws {
        let rig = try Rig(autocapitalization: .none)
        let other = DeviceClass.iphone440x956
        rig.view.update(screenWidth: other.screenWidth, screenHeight: other.screenHeight)
        let layout = try #require(rig.view.layout)
        #expect(layout.deviceClass == other)
        #expect(rig.view.layerWrites.count == layout.keys.count)
        for (index, key) in rig.view.layerWrites.enumerated() {
            #expect(key.face == 1 && key.fill == 1 && key.label + key.glyph == 1, "key \(index): \(key)")
        }
        let same = rig.view.layerWrites
        rig.view.update(screenWidth: other.screenWidth, screenHeight: other.screenHeight)
        #expect(Self.writes(same, rig.view.layerWrites).isEmpty, "the same layout again redraws nothing")
    }

    /// Whether each key was written exactly once whole: face, fill, and label or glyph (KEY-67).
    static func expectEveryKeyOnce(_ writes: [Int: KeyLayerWrites], _ layout: KeyboardLayout, _ what: String) {
        #expect(writes.count == layout.keys.count, "\(what): \(writes.count) of \(layout.keys.count) keys written")
        for index in layout.keys.indices {
            let key = writes[index] ?? KeyLayerWrites()
            #expect(key.face == 1 && key.fill == 1 && key.label + key.glyph == 1, "\(what): key \(index): \(key)")
        }
    }

    @Test("A new field session: the letters' case and Shift's glyph if Shift changed, the fill a dropped finger held")
    func newFieldSession() throws {
        let rig = try Rig(autocapitalization: .none)
        let shift = try rig.index(of: .shift)
        let q = try rig.index(of: rig.letter("q"))
        let letters = rig.layout.keys.indices.filter {
            if case .letter = rig.layout.keys[$0].kind { return true }
            return false
        }
        try rig.tap(.shift)
        #expect(rig.typing.shiftState == .manual)
        rig.view.touchDown(rig.newTouch(), at: try rig.point(rig.letter("q")), time: rig.clock)
        #expect(rig.typing.holds(q))

        // A fresh engine (Shift off: the field does not capitalise) and the finger on "q" forgotten.
        let start = rig.view.layerWrites
        rig.typing.beginFieldSession(at: rig.clock + 0.05)
        #expect(rig.typing.shiftState == .off)
        #expect(!rig.typing.holds(q))
        var expected: [Int: KeyLayerWrites] = [shift: Self.only(glyph: 1)]
        for index in letters { expected[index] = Self.only(label: 1) }
        expected[q] = Self.only(fill: 1, label: 1)
        #expect(Self.writes(start, rig.view.layerWrites) == expected)
        #expect(rig.field.text.isEmpty, "the forgotten finger typed nothing")

        // Another session that changes nothing drawn writes nothing.
        let same = rig.view.layerWrites
        rig.typing.beginFieldSession(at: rig.clock + 0.1)
        #expect(Self.writes(same, rig.view.layerWrites).isEmpty)
    }

    @Test("The next-keyboard key appearing, then going: every key redrawn once each time; the same value, nothing")
    func inputModeSwitchKeyChange() throws {
        let rig = try Rig(deviceClass: .iphone375x667, autocapitalization: .none)
        let globe = try rig.index(of: .globe)
        #expect(rig.view.faceLayers[globe].isHidden)
        for shows in [true, false] {
            let start = rig.view.layerWrites
            rig.view.showsInputModeSwitchKey = shows
            Self.expectEveryKeyOnce(Self.writes(start, rig.view.layerWrites), rig.layout, "shows \(shows)")
            #expect(rig.view.faceLayers[globe].isHidden == !shows)
            let same = rig.view.layerWrites
            rig.view.showsInputModeSwitchKey = shows
            #expect(Self.writes(same, rig.view.layerWrites).isEmpty, "shows \(shows) again redraws nothing")
        }
    }

    @Test("A display-scale change redraws every key once, with the glyphs rendered at the new scale")
    func displayScaleChange() throws {
        let rig = try Rig(autocapitalization: .none)
        let shift = try rig.index(of: .shift)
        var widths: [CGFloat: Int] = [:]
        for scale: CGFloat in [2, 3] {
            let start = rig.view.layerWrites
            rig.view.traitOverrides.displayScale = scale
            rig.view.updateTraitsIfNeeded()
            // A view with no window takes a trait override on `traitOverrides` (macOS CI, KEY-67), though it ignores
            // `overrideUserInterfaceStyle` (KEY-62).
            let taken = rig.view.traitCollection.displayScale
            try #require(taken == scale, "the view reads display scale \(taken), not the override \(scale)")
            // The registered trait change redraws, or the next layout pass does: either way, once. This call to
            // `applyUserInterfaceStyle` is the test's own, so the test shows that a new scale redraws every key once,
            // at that scale; it would still pass if `UITraitDisplayScale` were dropped from `registerForTraitChanges`.
            rig.view.applyUserInterfaceStyle(.light)
            Self.expectEveryKeyOnce(Self.writes(start, rig.view.layerWrites), rig.layout, "scale \(scale)")
            widths[scale] = try #require(rig.view.glyphImage(at: shift)).width
            let same = rig.view.layerWrites
            rig.view.applyUserInterfaceStyle(.light)
            #expect(Self.writes(same, rig.view.layerWrites).isEmpty, "scale \(scale) again redraws nothing")
        }
        let two = try #require(widths[2])
        let three = try #require(widths[3])
        #expect(abs(Double(three) * 2 - Double(two) * 3) <= 3, "Shift's glyph is \(two) px at 2x, \(three) px at 3x")
    }
}
