import SpeakboardCore
import XCTest

// The typing proof through the real keyboard extension (KEY-62). It needs a simulator where Speakboard is enabled,
// has Full Access and is the current keyboard, as scripts/sim-keyboard.sh arranges; the unit test step does not run
// it. It launches the app with its field focused, brings Speakboard up, finds it by its view's accessibility
// identifier, taps key centres computed from the core's layout, and reads the field back: "hi", a double space (a
// double tap on the space bar), "ok" and a delete give "Hi. O", and after a double tap on Shift, "ab" types "AB".
// Then, with Shift off, a tap in the gap between two rows and one in the margin beside the "a" row each type their
// nearest letter (KEY-24).
// SPEAKBOARD_APPEARANCE (set by the script through TEST_RUNNER_) names the screenshots.

/// The view's accessibility identifier: KeyboardView.accessibilityID (KeyboardKit is not linked into this target).
let keyboardID = "SpeakboardKeyboard"

/// When the running test began, for the elapsed time in each `speakboard-ui` line.
@MainActor var testStart = Date()

/// Prints a line the script copies into the job log, with the seconds since the test began, so a slow run shows
/// where its time went (KEY-62 review round 2).
@MainActor
func say(_ message: String) {
    print("speakboard-ui: +\(String(format: "%.1f", Date().timeIntervalSince(testStart)))s \(message)")
}

/// Where Speakboard's keyboard is on screen, and how to tap one of its keys. It is found by its view's accessibility
/// identifier, or the test fails: a proof that our keyboard typed cannot tap a keyboard it has not found (on 9ce7fbf a
/// fallback to `app.keyboards` typed on Apple's keyboard).
@MainActor
struct KeyboardOnScreen {
    let app: XCUIApplication
    let layout: KeyboardLayout
    let origin: CGPoint

    init(app: XCUIApplication, layout: KeyboardLayout) throws {
        self.app = app
        self.layout = layout
        let view = app.descendants(matching: .any)[keyboardID]
        XCTAssertTrue(view.waitForExistence(timeout: 10), "Speakboard's keyboard view is not on screen")
        origin = view.frame.origin
        say("keyboard found by its accessibility identifier, frame \(view.frame)")
    }

    func coordinate(_ kind: KeyKind) throws -> XCUICoordinate {
        coordinate(try frame(kind).center)
    }

    /// The screen coordinate of `point`, in the keyboard view's coordinates.
    func coordinate(_ point: LayoutPoint) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: Double(origin.x) + point.x, dy: Double(origin.y) + point.y))
    }

    func frame(_ kind: KeyKind) throws -> LayoutRect {
        try XCTUnwrap(layout.keys.first { $0.kind == kind }, "no \(kind) key").frame
    }

    /// Taps `point`, which must be in a gap or margin, where the exact hit-test finds no key and the nearest-key
    /// hit-test finds `expected` (KEY-24).
    func tap(gap point: LayoutPoint, expecting expected: KeyKind, _ what: String) throws {
        XCTAssertNil(layout.key(at: point), "\(what): the point \(point) is on a key, not in a gap")
        XCTAssertEqual(layout.key(nearest: point)?.kind, expected, "\(what): the nearest key")
        say("tap \(what) at \(point), nearest key \(expected)")
        coordinate(point).tap()
    }

    func tap(_ kind: KeyKind) throws {
        try coordinate(kind).tap()
    }

    func type(_ text: String) throws {
        for character in text {
            if character == " " {
                try tap(.space)
            } else {
                try tap(.letter(try XCTUnwrap(character.lowercased().unicodeScalars.first)))
            }
        }
    }
}

/// Makes Speakboard the keyboard on screen. `xcodebuild test` reinstalls the app, and after that the system may show
/// Apple's keyboard (seen on CI: its keys in the accessibility tree, and its 226 pt frame). This waits for a keyboard
/// to be up at all, then, while Apple's key elements are on screen and ours is not, taps the system's next-keyboard
/// button. A custom keyboard's view exposes no key elements; Apple's does.
@MainActor
func bringUpSpeakboard(_ app: XCUIApplication) {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let ours = app.descendants(matching: .any)[keyboardID]
    for attempt in 0..<6 {
        if ours.waitForExistence(timeout: 5) {
            say("attempt \(attempt): Speakboard is up")
            return
        }
        let appleKeys = app.keys.count
        say("attempt \(attempt): Speakboard not found; \(appleKeys) of Apple's key elements")
        guard appleKeys > 0 else {
            // No keyboard yet, or one without key elements that is not ours: wait, do not cycle blind.
            continue
        }
        let candidates = [
            app.buttons["Next keyboard"], springboard.buttons["Next keyboard"],
            app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'next keyboard'")).firstMatch,
            springboard.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'next keyboard'")).firstMatch,
        ]
        guard let next = candidates.first(where: { $0.exists }) else {
            say("no next-keyboard button found")
            break
        }
        next.tap()
    }
    XCTFail("Speakboard did not come up: the keyboard on screen is not ours (see the speakboard-ui lines)")
}

final class KeyboardExtensionUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    var appearance: String {
        ProcessInfo.processInfo.environment["SPEAKBOARD_APPEARANCE"] ?? "light"
    }

    @MainActor
    func screenshot(_ name: String) {
        defer { say("screenshot \(name) taken") }
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(name)-\(appearance)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func expectValue(_ field: XCUIElement, _ expected: String, _ what: String) {
        let predicate = NSPredicate(format: "value == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: field)
        let result = XCTWaiter().wait(for: [expectation], timeout: 10)
        say("\(what): the field reads \(String(describing: field.value))")
        XCTAssertEqual(
            result, .completed, "\(what): the field reads \(String(describing: field.value)), not \(expected)")
    }

    /// Through the extension: "hi" with Shift on for the first letter (sentence capitalisation), a double space as a
    /// double tap on the space bar (a full stop, which reads the proxy's context right after the keyboard's own
    /// insert), "ok" (Shift on again after the full stop), a delete; then Shift on, and caps lock as a double tap on
    /// Shift, checked by typing "ab" as "AB" and deleting it; then Shift off, and "g" and "a" typed by taps in a gap
    /// and a margin (KEY-24).
    @MainActor
    func testTypesThroughTheExtension() throws {
        testStart = Date()
        say("test began")
        let app = XCUIApplication()
        app.launchArguments = ["-SpeakboardFocusField"]
        app.launch()
        say("app launched")
        let field = app.textFields["TryField"]
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the app's field")
        say("field found")
        let window = app.windows.firstMatch.frame
        let match = DeviceClass.match(screenWidth: Double(window.width), screenHeight: Double(window.height))
        let layout = try XCTUnwrap(
            KeyboardLayout(locale: .english, deviceClass: match.deviceClass, orientation: .portrait))
        say("device \(match.deviceClass.rawValue); window \(window)")
        bringUpSpeakboard(app)
        let keyboard = try KeyboardOnScreen(app: app, layout: layout)
        screenshot("shift-auto")

        try keyboard.type("hi")
        expectValue(field, "Hi", "after hi")
        try keyboard.coordinate(.space).doubleTap()
        expectValue(field, "Hi. ", "after the double tap on space")
        try keyboard.type("ok")
        try keyboard.tap(.delete)
        expectValue(field, "Hi. O", "after ok and a delete")
        screenshot("shift-off")

        try keyboard.tap(.shift)
        screenshot("shift-on")
        try keyboard.tap(.shift)
        sleep(1)
        try keyboard.coordinate(.shift).doubleTap()
        screenshot("caps-lock")
        try keyboard.type("ab")
        expectValue(field, "Hi. OAB", "after the double tap on Shift and ab")
        try keyboard.tap(.delete)
        try keyboard.tap(.delete)
        expectValue(field, "Hi. O", "after two deletes")

        // Hit targets (KEY-24): Shift off, then a tap in the gap between the "g" row and the row below it, a quarter
        // of the way down, and one in the margin left of "a". Each types its nearest letter.
        try keyboard.tap(.shift)
        let g = try keyboard.frame(.letter("g"))
        let b = try keyboard.frame(.letter("b"))
        try keyboard.tap(
            gap: LayoutPoint(x: g.center.x, y: g.maxY + (b.minY - g.maxY) / 4), expecting: .letter("g"),
            "the gap below g")
        let a = try keyboard.frame(.letter("a"))
        try keyboard.tap(
            gap: LayoutPoint(x: a.minX / 2, y: a.center.y), expecting: .letter("a"), "the margin left of a")
        expectValue(field, "Hi. Oga", "after Shift off and the taps in a gap and beside a")
    }
}
