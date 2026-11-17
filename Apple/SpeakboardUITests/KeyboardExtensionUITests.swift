import SpeakboardCore
import XCTest

// The typing proof through the real keyboard extension (KEY-62). It needs a simulator where Speakboard is enabled,
// has Full Access and is the current keyboard, as scripts/sim-keyboard.sh arranges; the unit test step does not run
// it. It launches the app with its field focused, finds the keyboard on screen, taps key centres computed from the
// core's layout, and reads the field back. SPEAKBOARD_APPEARANCE (set by the script through TEST_RUNNER_) names the
// screenshots.

/// Where the keyboard is on screen, and how to tap one of its keys.
@MainActor
struct KeyboardOnScreen {
    let app: XCUIApplication
    let layout: KeyboardLayout
    let origin: CGPoint
    let foundBy: String

    init(app: XCUIApplication) throws {
        self.app = app
        let window = app.windows.firstMatch.frame
        let match = DeviceClass.match(screenWidth: Double(window.width), screenHeight: Double(window.height))
        let layout = try XCTUnwrap(
            KeyboardLayout(locale: .english, deviceClass: match.deviceClass, orientation: .portrait))
        self.layout = layout
        let view = app.descendants(matching: .any)["SpeakboardKeyboard"]
        let keyboard = app.keyboards.firstMatch
        if view.waitForExistence(timeout: 5) {
            origin = view.frame.origin
            foundBy = "its accessibility identifier, frame \(view.frame)"
        } else if keyboard.exists, abs(Double(keyboard.frame.height) - layout.size.height) < 2 {
            origin = keyboard.frame.origin
            foundBy = "app.keyboards, frame \(keyboard.frame), our layout's height"
        } else {
            // The keyboard's view sits above the strip iOS draws below it on Face ID iPhones (systemStrip.height).
            let metrics = layout.metrics
            let strip = match.deviceClass.hasHomeIndicator ? metrics.systemStripHeight.value : 0
            origin = CGPoint(x: 0, y: Double(window.height) - strip - layout.size.height)
            foundBy = "the screen and the core's heights (no element found)"
        }
        print("speakboard-ui: keyboard found by \(foundBy); device \(match.deviceClass.rawValue); window \(window)")
    }

    func coordinate(_ kind: KeyKind) throws -> XCUICoordinate {
        let key = try XCTUnwrap(layout.keys.first { $0.kind == kind }, "no \(kind) key")
        let center = key.frame.center
        return app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: Double(origin.x) + center.x, dy: Double(origin.y) + center.y))
    }

    func tap(_ kind: KeyKind) throws {
        try coordinate(kind).tap()
    }

    func type(_ text: String) throws {
        for character in text {
            if character == " " {
                try tap(.space)
            } else {
                try tap(.letter(try XCTUnwrap(character.unicodeScalars.first)))
            }
        }
    }
}

/// Makes Speakboard the keyboard on screen. `xcodebuild test` reinstalls the app, and after that the system shows
/// Apple's keyboard (seen on CI: its keys in the accessibility tree, and its 226 pt frame), so this taps the system's
/// next-keyboard button until Apple's key elements are gone and a keyboard of our layout's height is up. A custom
/// keyboard's view exposes no key elements; Apple's does.
@MainActor
func bringUpSpeakboard(_ app: XCUIApplication, height: Double) {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    for attempt in 0..<6 {
        let keyboard = app.keyboards.firstMatch
        let frame = keyboard.exists ? keyboard.frame : .zero
        let appleKeys = app.keys.count
        print("speakboard-ui: attempt \(attempt): \(appleKeys) key elements, keyboard frame \(frame)")
        if appleKeys == 0, abs(Double(frame.height) - height) < 2 { return }
        if app.descendants(matching: .any)["SpeakboardKeyboard"].exists { return }
        let candidates = [
            app.buttons["Next keyboard"], springboard.buttons["Next keyboard"],
            app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'next keyboard'")).firstMatch,
            springboard.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'next keyboard'")).firstMatch,
        ]
        guard let next = candidates.first(where: { $0.exists }) else {
            print("speakboard-ui: no next-keyboard button found")
            break
        }
        next.tap()
        sleep(2)
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
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(name)-\(appearance)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func waitForValue(_ field: XCUIElement, _ expected: String) {
        let predicate = NSPredicate(format: "value == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: field)
        let result = XCTWaiter().wait(for: [expectation], timeout: 10)
        XCTAssertEqual(result, .completed, "the field reads \(String(describing: field.value)), not \(expected)")
    }

    /// Types "hi ok" and a delete through the extension: "Hi o", with Shift turned on by the field's sentence
    /// capitalisation for the first letter. Then shows Shift on and caps lock, for the screenshots.
    @MainActor
    func testTypesThroughTheExtension() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-SpeakboardFocusField"]
        app.launch()
        let field = app.textFields["TryField"]
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the app's field")
        let match = DeviceClass.match(
            screenWidth: Double(app.windows.firstMatch.frame.width),
            screenHeight: Double(app.windows.firstMatch.frame.height))
        let height = try XCTUnwrap(
            KeyboardLayout(locale: .english, deviceClass: match.deviceClass, orientation: .portrait)
        ).size.height
        bringUpSpeakboard(app, height: height)
        let keyboard = try KeyboardOnScreen(app: app)
        screenshot("shift-auto")
        try keyboard.type("hi ok")
        try keyboard.tap(.delete)
        waitForValue(field, "Hi o")
        screenshot("shift-off")
        try keyboard.tap(.shift)
        screenshot("shift-on")
        try keyboard.tap(.shift)
        try keyboard.coordinate(.shift).doubleTap()
        screenshot("caps-lock")
        print("speakboard-ui: after the caps lock double tap the field reads \(String(describing: field.value))")
    }
}
