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

/// The keyboard's accessibility tree, from one snapshot, as a flat list; empty when no keyboard is up.
@MainActor
func keyboardTree(_ app: XCUIApplication) throws -> [KeyboardItem] {
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
        try keyboardTree(app)
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
        // The state itself, from a fresh read of the tree, at the moment of the capture (review round 1, finding 1).
        let tree = try items(app)
        let facts = tree.map {
            KeyFacts(type: $0.typeName, identifier: $0.identifier, label: $0.label, value: $0.value)
        }
        if let problem = stateProblem(facts, state) {
            log(tree, "\(state.rawValue) at its capture, which is not that state")
            XCTFail("\(state.rawValue) at its capture: \(problem)")
            return
        }
        say("\(state.rawValue) checked at its capture")
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

    /// The labels of the app's elements between the field and the keyboard's top, outside the keyboard's own tree:
    /// where the suggestion bar's candidates would be, if the tree shows them.
    @MainActor
    func suggestionTexts(_ app: XCUIApplication, field: CGRect, keyboard: CGRect) throws -> [String] {
        var texts: [String] = []
        func walk(_ snapshot: any XCUIElementSnapshot) {
            guard snapshot.elementType != .keyboard else { return }
            let frame = snapshot.frame
            if !snapshot.label.isEmpty && frame.minY >= field.maxY && frame.maxY <= keyboard.minY + 1
                && frame.height > 0 && frame.height < 80
            {
                texts.append(snapshot.label)
            }
            for child in snapshot.children {
                walk(child)
            }
        }
        walk(try app.snapshot())
        return texts
    }

    /// Before the first capture (KEY-70): its suggestion bar was sometimes empty, taken before the suggestions came.
    /// Waits up to 10 seconds for the tree to show candidates above the keyboard, and never fails: if the tree shows
    /// none, it says so and the capture is taken as it is.
    @MainActor
    func waitForSuggestions(_ app: XCUIApplication, field: XCUIElement) {
        let keyboard = app.keyboards.firstMatch.frame
        let start = Date()
        repeat {
            if let texts = try? suggestionTexts(app, field: field.frame, keyboard: keyboard), !texts.isEmpty {
                let seconds = String(format: "%.1f", Date().timeIntervalSince(start))
                say("suggestion candidates in the tree after \(seconds)s: \(texts)")
                return
            }
            sleep(1)
        } while Date().timeIntervalSince(start) < 10
        say(
            "the tree shows no suggestion candidates above the keyboard within 10s: the first capture is taken as it"
                + " is, and its bar may be empty")
    }

    /// The letters' case as the keys show it, "upper" or "lower" (from the Q key's label), or "unknown" when neither
    /// is found within `timeout` seconds. A query of two keys, much quicker than a snapshot of the tree.
    @MainActor
    func letterCase(_ app: XCUIApplication, timeout: TimeInterval) -> String {
        let upper = app.keys.matching(NSPredicate(format: "label == %@", "Q")).firstMatch
        let lower = app.keys.matching(NSPredicate(format: "label == %@", "q")).firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if upper.exists {
                return "upper"
            }
            if lower.exists {
                return "lower"
            }
        } while Date() < deadline
        return "unknown"
    }

    /// The seconds from now until the letters show `wanted` case ("upper" or "lower"), as a query of the Q key
    /// sees it (the time includes the query's own), or nil if they do not within `timeout` seconds (KEY-70).
    @MainActor
    func caseChange(_ app: XCUIApplication, to wanted: String, timeout: TimeInterval) -> TimeInterval? {
        let key = app.keys.matching(NSPredicate(format: "label == %@", wanted == "upper" ? "Q" : "q")).firstMatch
        let start = Date()
        repeat {
            if key.exists {
                return Date().timeIntervalSince(start)
            }
        } while Date().timeIntervalSince(start) < timeout
        return nil
    }

    /// Taps Shift once at a time until two taps in a row each change the letters' case within `quick` seconds (the
    /// keyboard answers quickly), or `bound` seconds pass, then leaves Shift off. Each tap waits for the case to
    /// change (KEY-70: before, the time measured only how long a query took), and logs how long it took.
    @MainActor
    func waitForQuickShift(_ app: XCUIApplication, quick: TimeInterval = 1.5, bound: TimeInterval = 30) {
        let start = Date()
        var quickInARow = 0
        while quickInARow < 2 && Date().timeIntervalSince(start) < bound {
            guard let shift = try? find(try items(app), "the shift key", { $0.isNamed(["shift"]) }) else { return }
            let before = letterCase(app, timeout: 2)
            let want = before == "upper" ? "lower" : "upper"
            let tapped = Date()
            tap(app, shift)
            let changed = caseChange(app, to: want, timeout: 3)
            let seconds = Date().timeIntervalSince(tapped)
            quickInARow = changed != nil && seconds <= quick ? quickInARow + 1 : 0
            let took = String(format: "%.2f", seconds)
            let now = changed != nil ? want : letterCase(app, timeout: 1)
            say(
                "a single tap on shift: \(before) to \(now), "
                    + (changed != nil ? "the case changed \(took)s after the tap" : "no change of case within 3s")
                    + " (\(quickInARow) quick in a row)")
        }
        if letterCase(app, timeout: 2) == "upper",
            let shift = try? find(try items(app), "the shift key", { $0.isNamed(["shift"]) })
        {
            tap(app, shift)
            say("Shift off again before the double tap: the letters \(letterCase(app, timeout: 3))")
        }
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
        waitForSuggestions(app, field: field)
        try capture(app, .lettersUpper, window: window, field: "empty")

        // 2. Letters, lower case: after "A", Shift is off mid-word; "b" typing "Ab" proves it.
        try typeAndCheck(app, field, "a", expecting: "A")
        try typeAndCheck(app, field, "b", expecting: "Ab")
        log(try items(app), "letters, lower case")
        try capture(app, .lettersLower, window: window, field: "Ab")

        // 3. Caps lock: a double tap on Shift from Shift off. "cd" typing "CD" proves it (with Shift alone the second
        // letter is lower case), and after deleting them it is still caps lock, which "e" typing "E" shows; deleted.
        // A synthesised double tap can land as two single taps on a loaded runner (run 44799266681, light: "cd"
        // typed "cd"), so it is tried again, the letters deleted back to "Ab" between tries (below).
        // A double tap on Shift missed in about 7 of 13 coordinate double taps seen (KEY-9), always with Shift off
        // right after it: likely two single taps (on, then off) on a keyboard slow to answer, as the first pass on a
        // fresh simulator is; not shown. So before each try the keyboard must answer two single taps on Shift quickly
        // (each waiting for the case to change); the tries alternate two public gestures, leading with the tighter
        // tap(withNumberOfTaps: 2) on the Shift button (KEY-70: it spanned 0.45 s against 0.96 to 1.28 s for the
        // coordinate doubleTap()), with the coordinate doubleTap() as the fallback; each logs its gesture, its times
        // and Shift's state straight after it. At most 6 tries, with a pause of 1 to 5 s after a miss, and 240 seconds
        // in all, so the step stays inside its limit (the sum is in .github/workflows/macos.yml).
        var capsLock = false
        let capsDeadline = Date().addingTimeInterval(240)
        for attempt in 1...6 where !capsLock && Date() < capsDeadline {
            waitForQuickShift(app)
            let shiftKey = try find(try items(app), "the shift key") { $0.isNamed(["shift"]) }
            let shiftElement = app.keyboards.buttons["shift"].firstMatch
            let element = attempt % 2 == 1 && shiftElement.exists
            let gesture = element ? "tap(withNumberOfTaps: 2) on the shift button" : "doubleTap() on its coordinate"
            let before = Date().timeIntervalSince(testStart)
            if element {
                shiftElement.tap(withNumberOfTaps: 2, numberOfTouches: 1)
            } else {
                tap(app, shiftKey, double: true)
            }
            let after = Date().timeIntervalSince(testStart)
            let value = shiftElement.exists ? (shiftElement.value.map { String(describing: $0) } ?? "") : "no element"
            let letters = letterCase(app, timeout: 1)
            let times = "from +\(String(format: "%.2f", before))s to +\(String(format: "%.2f", after))s"
            say(
                "double tap \(attempt) on shift (\(gesture)) \(times); right after it Shift's value is \"\(value)\","
                    + " the letters \(letters)")
            sleep(1)
            log(try items(app), "after double tap \(attempt) on shift")
            for character in "cd" {
                let key = try find(try items(app), "the key \(character)") {
                    $0.type == .key && $0.label.lowercased() == String(character)
                }
                tap(app, key)
            }
            sleep(1)
            let typed = (field.value as? String) ?? ""
            say("double tap \(attempt) on shift (\(gesture)), then cd: the field reads \(typed)")
            if typed == "AbCD" {
                capsLock = true
                say("caps lock from double tap \(attempt), \(gesture), in \(appearance) appearance")
            } else {
                if letters == "lower" && value.isEmpty {
                    say(
                        "double tap \(attempt) missed: Shift was off right after it, likely two single taps"
                            + " (on, then off)"
                    )
                }
                try delete(app, field, max(typed.count - 2, 0), expecting: ["Ab"])
                if attempt < 6 {
                    sleep(UInt32(attempt))
                }
            }
        }
        XCTAssertTrue(
            capsLock, "no double tap on Shift gave caps lock in 6 tries or 240 seconds (see the speakboard-ui lines)")
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
