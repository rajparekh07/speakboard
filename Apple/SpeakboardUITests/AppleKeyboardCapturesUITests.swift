import UIKit
import XCTest

// Reference captures of Apple's own keyboard (KEY-9), for measuring the design tokens from. scripts/sim-keyboard.sh
// runs this test, alone, on a fresh simulator before Speakboard is enabled, so the keyboard on screen can only be
// Apple's, once in light and once in dark appearance; SPEAKBOARD_APPLE_CAPTURES=1 (set by the script through
// TEST_RUNNER_) turns it on, and without it the test skips, so a run of the whole scheme does not depend on it.
//
// It launches the app with its field focused, the default keyboard type, and drives Apple's keyboard through five
// states: letters upper case (automatic Shift in the empty field), letters lower case (a tap on Shift), caps lock (a
// double tap on Shift), the numbers plane ("123") and the symbols plane ("#+="). It finds Apple's keys in the
// accessibility tree by their labels and identifiers, logs the tree the first time and after each change, checks the
// plane after each tap before it takes the screenshot, and checks the case by typing a letter and reading the field
// after it (then deletes it). Each screenshot is attached as a lossless PNG, apple-<state>-<appearance>, and a
// `speakboard-apple-capture` line gives the facts its marker needs. It fails, with the tree in the log, if a key or a
// plane is not found, or if no on-screen keyboard is up (with a hardware keyboard connected, iOS shows none).

/// One element of the keyboard's accessibility tree, as a snapshot gives it.
struct KeyboardItem {
    let type: XCUIElement.ElementType
    let identifier: String
    let label: String
    let value: String
    let frame: CGRect

    var typeName: String {
        switch type {
        case .key: return "key"
        case .button: return "button"
        case .keyboard: return "keyboard"
        case .other: return "other"
        case .staticText: return "text"
        case .cell: return "cell"
        case .collectionView: return "collection"
        default: return "type\(type.rawValue)"
        }
    }

    /// The identifier or the label, lower case, is one of `names`.
    func isNamed(_ names: [String]) -> Bool {
        names.contains(identifier.lowercased()) || names.contains(label.lowercased())
    }
}

/// The five states, in the order the test takes them.
enum AppleKeyboardState: String {
    case lettersUpper = "letters-upper"
    case lettersLower = "letters-lower"
    case capsLock = "caps-lock"
    case numbers = "numbers"
    case symbols = "symbols"
}

final class AppleKeyboardCapturesUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    var appearance: String {
        ProcessInfo.processInfo.environment["SPEAKBOARD_APPEARANCE"] ?? "light"
    }

    /// The field's value when it is empty: its placeholder, as XCUITest reads it, or nothing.
    let emptyValues = ["", "Type here"]

    @MainActor
    func items(_ app: XCUIApplication) throws -> [KeyboardItem] {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return [] }
        var found: [KeyboardItem] = []
        func walk(_ snapshot: any XCUIElementSnapshot) {
            found.append(
                KeyboardItem(
                    type: snapshot.elementType, identifier: snapshot.identifier, label: snapshot.label,
                    value: snapshot.value.map { String(describing: $0) } ?? "", frame: snapshot.frame))
            for child in snapshot.children {
                walk(child)
            }
        }
        walk(try keyboard.snapshot())
        return found
    }

    /// Logs the tree on one line (so the job log stays short): each element as type:identifier/label=value.
    @MainActor
    func log(_ items: [KeyboardItem], _ title: String) {
        let elements = items.map { item in
            "\(item.typeName):\(item.identifier)/\(item.label)" + (item.value.isEmpty ? "" : "=\(item.value)")
        }
        say("apple keyboard tree, \(title): \(items.count) elements: \(elements.joined(separator: " | "))")
    }

    /// The first element that `matches`, or a failure with the tree in the log.
    @MainActor
    func find(
        _ items: [KeyboardItem], _ what: String, _ matches: (KeyboardItem) -> Bool
    ) throws -> KeyboardItem {
        if let item = items.first(where: matches) {
            say("found \(what): \(item.typeName) id=\"\(item.identifier)\" label=\"\(item.label)\" at \(item.frame)")
            return item
        }
        log(items, "no \(what) in it")
        return try XCTUnwrap(
            items.first(where: matches), "no \(what) on Apple's keyboard (the tree is in the speakboard-ui lines)")
    }

    func labels(_ items: [KeyboardItem]) -> Set<String> {
        Set(items.filter { $0.type == .key }.map(\.label))
    }

    func hasKey(_ items: [KeyboardItem], _ names: [String]) -> Bool {
        items.contains { $0.type == .key && $0.isNamed(names) }
    }

    @MainActor
    func tap(_ app: XCUIApplication, _ item: KeyboardItem, double: Bool = false) {
        let point = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: item.frame.midX, dy: item.frame.midY))
        if double {
            point.doubleTap()
        } else {
            point.tap()
        }
    }

    @MainActor
    func expectValue(_ field: XCUIElement, _ expected: [String], _ what: String) {
        let predicate = NSPredicate(format: "value IN %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: field)
        let result = XCTWaiter().wait(for: [expectation], timeout: 10)
        say("\(what): the field reads \(String(describing: field.value))")
        XCTAssertEqual(
            result, .completed, "\(what): the field reads \(String(describing: field.value)), not one of \(expected)")
    }

    /// Types `text` on Apple's letter keys (found by label, either case), checks the field reads `expected`, and
    /// deletes it again, so the field is empty.
    @MainActor
    func typeAndDelete(_ app: XCUIApplication, _ field: XCUIElement, _ text: String, expecting expected: String)
        throws
    {
        for character in text {
            let letter = String(character)
            let key = try find(try items(app), "the key \(letter)") {
                $0.type == .key && $0.label.lowercased() == letter
            }
            tap(app, key)
        }
        expectValue(field, [expected], "after typing \(text) on Apple's keyboard")
        for _ in text {
            let delete = try find(try items(app), "the delete key") { $0.isNamed(["delete"]) }
            tap(app, delete)
        }
        expectValue(field, emptyValues, "after deleting it")
    }

    /// Checks that Apple's on-screen keyboard is up and wholly inside the crop the screenshots jobs make (the bottom
    /// 2/5 of the screen), then attaches a lossless screenshot and prints its facts.
    @MainActor
    func capture(_ app: XCUIApplication, _ state: AppleKeyboardState, window: CGRect) throws {
        sleep(1)
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.exists, "\(state.rawValue): no on-screen keyboard (is a hardware keyboard connected?)")
        let frame = keyboard.frame
        XCTAssertGreaterThan(app.keys.count, 0, "\(state.rawValue): the on-screen keyboard has no keys")
        XCTAssertGreaterThan(frame.height, 0, "\(state.rawValue): the on-screen keyboard has no height")
        XCTAssertEqual(app.alerts.count, 0, "\(state.rawValue): an alert is on screen")
        let cropTop = window.height * 3 / 5
        XCTAssertGreaterThanOrEqual(
            frame.minY, cropTop, "\(state.rawValue): the keyboard \(frame) starts above the crop's top, \(cropTop) pt")
        XCTAssertLessThanOrEqual(frame.maxY, window.maxY, "\(state.rawValue): the keyboard \(frame) runs off screen")
        let name = "apple-\(state.rawValue)-\(appearance)"
        let attachment = XCTAttachment(
            data: XCUIScreen.main.screenshot().pngRepresentation, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let environment = ProcessInfo.processInfo.environment
        // The device type the script made the simulator from; the simulator's own name is the script's.
        let device = environment["SPEAKBOARD_DEVICE_TYPE"] ?? environment["SIMULATOR_DEVICE_NAME"] ?? "unknown"
        let model = environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "unknown"
        print(
            "speakboard-apple-capture name=\(name).png state=\(state.rawValue) appearance=\(appearance)"
                + " ios=\(UIDevice.current.systemVersion) model=\(model)"
                + " window=\(Int(window.width))x\(Int(window.height))"
                + " keyboard=\(frame.minX),\(frame.minY),\(frame.width),\(frame.height) device=\(device)")
        say("screenshot \(name) taken; keyboard frame \(frame)")
    }

    @MainActor
    func testCapturesAppleKeyboard() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["SPEAKBOARD_APPLE_CAPTURES"] == "1",
            "only scripts/sim-keyboard.sh runs it, before Speakboard is enabled")
        testStart = Date()
        say("apple captures began, \(appearance)")
        let app = XCUIApplication()
        app.launchArguments = ["-SpeakboardFocusField"]
        app.launch()
        let field = app.textFields["TryField"]
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the app's field")
        let window = app.windows.firstMatch.frame
        say("window \(window)")

        // Apple's keyboard up, with its keys: with a hardware keyboard connected there would be no on-screen keyboard.
        var tree = try items(app)
        for _ in 0..<20 {
            if hasKey(tree, ["q"]) {
                break
            }
            sleep(1)
            tree = try items(app)
        }
        XCTAssertFalse(
            app.descendants(matching: .any)[keyboardID].exists, "Speakboard's keyboard is up: it must not be enabled")
        log(tree, "as it came up")
        XCTAssertTrue(
            hasKey(tree, ["q"]),
            "no on-screen keyboard with letter keys came up (is a hardware keyboard connected?)")
        expectValue(field, emptyValues, "before the captures")

        // 1. Letters, upper case: automatic Shift in the empty field, which capitalises sentences.
        try capture(app, .lettersUpper, window: window)
        try typeAndDelete(app, field, "a", expecting: "A")

        // 2. Letters, lower case: Shift off.
        let shift = try find(try items(app), "the shift key") { $0.isNamed(["shift"]) }
        tap(app, shift)
        sleep(1)
        log(try items(app), "after a tap on shift")
        try capture(app, .lettersLower, window: window)
        try typeAndDelete(app, field, "a", expecting: "a")

        // 3. Caps lock: a double tap on Shift, checked by "ab" typing "AB".
        tap(app, try find(try items(app), "the shift key") { $0.isNamed(["shift"]) }, double: true)
        sleep(1)
        log(try items(app), "after a double tap on shift")
        try capture(app, .capsLock, window: window)
        try typeAndDelete(app, field, "ab", expecting: "AB")
        tap(app, try find(try items(app), "the shift key") { $0.isNamed(["shift"]) })
        sleep(1)

        // 4. The numbers plane: "123", checked by its digit keys and no letter keys.
        let numbersKey = try find(try items(app), "the 123 key") {
            $0.isNamed(["123", "numbers", "more, numbers"]) || $0.identifier == "more"
        }
        tap(app, numbersKey)
        sleep(1)
        let numbers = try items(app)
        log(numbers, "after a tap on 123")
        XCTAssertTrue(hasKey(numbers, ["1"]) && hasKey(numbers, ["0"]), "123 did not bring up the numbers plane")
        XCTAssertFalse(hasKey(numbers, ["q"]), "the letter q is still on the keyboard after 123")
        try capture(app, .numbers, window: window)

        // 5. The symbols plane: "#+=", checked by no digit and no letter keys, and keys other than the numbers'.
        let symbolsKey = try find(numbers, "the #+= key") {
            $0.isNamed(["#+=", "symbols", "more, symbols"])
        }
        tap(app, symbolsKey)
        sleep(1)
        let symbols = try items(app)
        log(symbols, "after a tap on #+=")
        XCTAssertFalse(hasKey(symbols, ["1"]), "the digit 1 is still on the keyboard after #+=")
        XCTAssertFalse(hasKey(symbols, ["q"]), "the letter q is on the keyboard after #+=")
        XCTAssertNotEqual(labels(symbols), labels(numbers), "#+= did not change the keys")
        XCTAssertGreaterThanOrEqual(labels(symbols).count, 10, "the symbols plane has too few keys")
        try capture(app, .symbols, window: window)
        say("apple captures done, \(appearance)")
    }
}
