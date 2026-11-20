import UIKit
import XCTest

// Reference captures of Apple's own keyboard (KEY-9), for measuring the design tokens from. scripts/sim-keyboard.sh
// runs this test, alone, on a fresh simulator before Speakboard is enabled, so the keyboard on screen can only be
// Apple's, once in light and once in dark appearance; SPEAKBOARD_APPLE_CAPTURES=1 (set by the script through
// TEST_RUNNER_) turns it on, and without it the test skips, so a run of the whole scheme does not depend on it.
//
// It launches the app with only its field, at the top of a plain screen (-SpeakboardPlainField), the default keyboard
// type, and drives Apple's keyboard through five states, proving each state before it captures it: letters upper
// case (automatic Shift in the empty field: "a" types "A", then deleted), letters lower case (after "A", "b" types
// "Ab": Shift is off mid-word), caps lock (a double tap on Shift; "cd" types "CD", and after deleting them the
// keyboard is still in caps lock), the numbers plane ("123": its digit keys and no letter keys) and the symbols
// plane (no digit or letter keys, and keys other than the numbers'). Before all that, it dismisses iOS's first-run slide-to-type card if it is up (it covered the keyboard on run 44793753513), and
// proves the keyboard takes taps. It finds Apple's keys in the accessibility tree by their labels and identifiers and
// logs the tree, on one line, at each step. Each screenshot is attached as a lossless PNG, apple-<state>-<appearance>,
// and a `speakboard-apple-capture` line gives the facts its marker needs. It fails, with the tree in the log, if a
// key, a plane or a state is not what it should be, if the card is still up, or if no on-screen keyboard is up (with
// a hardware keyboard connected, iOS shows none).

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

    /// Types `text` on Apple's letter or digit keys (found by label, either case) and checks the field reads
    /// `expected`.
    @MainActor
    func typeAndCheck(_ app: XCUIApplication, _ field: XCUIElement, _ text: String, expecting expected: String) throws {
        for character in text {
            let letter = String(character)
            let key = try find(try items(app), "the key \(letter)") {
                $0.type == .key && $0.label.lowercased() == letter
            }
            tap(app, key)
        }
        expectValue(field, [expected], "after typing \(text) on Apple's keyboard")
    }

    /// Taps Apple's delete key `count` times and checks the field reads one of `expected`.
    @MainActor
    func delete(_ app: XCUIApplication, _ field: XCUIElement, _ count: Int, expecting expected: [String]) throws {
        for _ in 0..<count {
            tap(app, try find(try items(app), "the delete key") { $0.isNamed(["delete"]) })
        }
        expectValue(field, expected, "after \(count) deletes")
    }

    /// Checks that Apple's on-screen keyboard is up and wholly inside the crop the screenshots jobs make (the bottom
    /// 2/5 of the screen), then attaches a lossless screenshot and prints its facts.
    @MainActor
    func capture(_ app: XCUIApplication, _ state: AppleKeyboardState, window: CGRect, field: String) throws {
        sleep(1)
        XCTAssertTrue(try introduction(app).isEmpty, "\(state.rawValue): the slide-to-type card is up")
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
                + " keyboard=\(frame.minX),\(frame.minY),\(frame.width),\(frame.height) field=\(field)"
                + " behind=plain-system-background device=\(device)")
        say("screenshot \(name) taken; keyboard frame \(frame)")
    }

    /// The texts of the app's tree that belong to iOS's first-run slide-to-type card, if it is up.
    @MainActor
    func introduction(_ app: XCUIApplication) throws -> [String] {
        var texts: [String] = []
        func walk(_ snapshot: any XCUIElementSnapshot) {
            let label = snapshot.label.lowercased()
            if label.contains("sliding your finger") || label.contains("slide to type") {
                texts.append(snapshot.label)
            }
            for child in snapshot.children {
                walk(child)
            }
        }
        walk(try app.snapshot())
        return texts
    }

    /// Dismisses the slide-to-type card if it is up: a button that continues, or else a tap on its text. Fails if it
    /// is still up after three tries.
    @MainActor
    func dismissIntroduction(_ app: XCUIApplication) throws {
        for attempt in 0..<3 {
            let texts = try introduction(app)
            if texts.isEmpty {
                say("no slide-to-type card in the tree (attempt \(attempt))")
                return
            }
            say("the slide-to-type card is up (attempt \(attempt)): \(texts)")
            let buttons = app.buttons.allElementsBoundByIndex.map { "\($0.identifier)/\($0.label)" }
            say("buttons in the tree: \(buttons.joined(separator: " | "))")
            let names = ["continue", "ok", "done", "got it", "not now", "close"]
            let button = app.buttons.allElementsBoundByIndex.first {
                names.contains($0.label.lowercased()) || names.contains($0.identifier.lowercased())
            }
            if let button {
                say("tapping the card's button \(button.label)")
                button.tap()
            } else {
                let text = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'sliding your finger'"))
                    .firstMatch
                say("no button on the card: tapping its text")
                if text.exists {
                    text.tap()
                }
            }
            sleep(2)
        }
        XCTAssertTrue(
            try introduction(app).isEmpty, "the slide-to-type card is still up after three tries to dismiss it")
    }

    @MainActor
    func testCapturesAppleKeyboard() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["SPEAKBOARD_APPLE_CAPTURES"] == "1",
            "only scripts/sim-keyboard.sh runs it, before Speakboard is enabled")
        testStart = Date()
        say("apple captures began, \(appearance)")
        let app = XCUIApplication()
        app.launchArguments = ["-SpeakboardPlainField"]
        app.launch()
        let field = app.textFields["TryField"]
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the app's field")
        let window = app.windows.firstMatch.frame
        say("window \(window); field \(field.frame)")

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
        try dismissIntroduction(app)

        // 1. Letters, upper case: automatic Shift in the empty field, which capitalises sentences. Proved by "a"
        // typing "A", which also proves the keyboard takes taps (the slide-to-type card does not); deleted again, the
        // field is empty and automatic Shift is back.
        try typeAndCheck(app, field, "a", expecting: "A")
        try delete(app, field, 1, expecting: emptyValues)
        log(try items(app), "letters, upper case")
        try capture(app, .lettersUpper, window: window, field: "empty")

        // 2. Letters, lower case: after "A", Shift is off mid-word; "b" typing "Ab" proves it.
        try typeAndCheck(app, field, "a", expecting: "A")
        try typeAndCheck(app, field, "b", expecting: "Ab")
        log(try items(app), "letters, lower case")
        try capture(app, .lettersLower, window: window, field: "Ab")

        // 3. Caps lock: a double tap on Shift from Shift off. "cd" typing "CD" proves it (with Shift alone the second
        // letter is lower case), and after deleting them it is still caps lock, which "e" typing "E" shows; deleted.
        tap(app, try find(try items(app), "the shift key") { $0.isNamed(["shift"]) }, double: true)
        sleep(1)
        try typeAndCheck(app, field, "cd", expecting: "AbCD")
        try delete(app, field, 2, expecting: ["Ab"])
        try typeAndCheck(app, field, "e", expecting: "AbE")
        try delete(app, field, 1, expecting: ["Ab"])
        log(try items(app), "caps lock")
        try capture(app, .capsLock, window: window, field: "Ab")

        // Caps lock off, and the field emptied, for the numbers and symbols planes.
        tap(app, try find(try items(app), "the shift key") { $0.isNamed(["shift"]) })
        sleep(1)
        try delete(app, field, 2, expecting: emptyValues)

        // 4. The numbers plane: "123", proved by its digit keys and no letter keys.
        let numbersKey = try find(try items(app), "the 123 key") {
            $0.isNamed(["123", "numbers", "more, numbers"]) || $0.identifier == "more"
        }
        tap(app, numbersKey)
        sleep(1)
        let numbers = try items(app)
        log(numbers, "after a tap on 123")
        XCTAssertTrue(hasKey(numbers, ["1"]) && hasKey(numbers, ["0"]), "123 did not bring up the numbers plane")
        XCTAssertFalse(hasKey(numbers, ["q"]), "the letter q is still on the keyboard after 123")
        try capture(app, .numbers, window: window, field: "empty")

        // 5. The symbols plane: "#+=", proved by no digit and no letter keys, and keys other than the numbers'.
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
        try capture(app, .symbols, window: window, field: "empty")
        say("apple captures done, \(appearance)")
    }
}
