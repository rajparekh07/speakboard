import UIKit
import XCTest

// Measurements of Apple's own keyboard (KEY-71), on the simulator where the reference captures were taken, after all
// ten of them, in light appearance. scripts/sim-keyboard.sh runs this test alone, with SPEAKBOARD_APPLE_MEASUREMENTS=1
// (set through TEST_RUNNER_); without it the test skips. It measures four things, each logged as `speakboard-measure`
// lines an agent reads from the job log:
//   1. under the bottom row: taps under the space bar's face, 1 pt at a time from 1 pt to 7 pt past the keyboard
//      frame's bottom, each read as "typed a space or not"; and under the 123 key, inside the frame only (the emoji
//      button is below it), each read as "changed the plane or not";
//   2. between two rows: taps 1 pt apart from the bottom edge of a second-row letter to the top edge of the third-row
//      letter under it, and from a third-row letter to the space bar under it, each read as the letter (or space) it
//      typed, or none;
//   3. beside the "a" row: taps 2 pt apart from the screen's left edge to the "a" key, and from its right edge to "l";
//   4. what each key of the numbers and symbols planes' three upper rows types in an empty field (its label, the
//      string and its code points), and the plane after it; the double quote and the apostrophe also after a letter;
//      and the plane after a digit and a space, and after an apostrophe.
// Then a summary line for each of 1 to 3, and one for the planes.
//
// Where the keys are: the accessibility tree gives each key's frame, but those frames tile the keyboard (they are a
// row pitch tall, gaps included), so the edges of a key's visible face are read from a screenshot: along a line of
// pixels inside the key's frame, the face is the span of pixels within 8 of the line's most common colour. The test
// logs the frame and the face it found; if the screenshot gives no plausible face, it logs that and uses the frame.
//
// How a tap is read: the field holds one letter ("A", typed in the empty field) before each tap of 1 to 3, so
// autocorrection has nothing to correct and two spaces are never in a row (a typed space is deleted before the next
// tap, so the double-space full stop cannot happen). After a tap the test waits up to `bound` seconds for the field
// or the plane to change; no change by then is "nothing". It then deletes what was typed and returns to the letters
// plane. If a tap opens something (an alert, another plane, no keyboard), that is logged as the finding for the point,
// and the test gets back to a known state, relaunching the app if it must.
//
// What it is not: a synthesised tap has no contact area and no finger; this is simulator evidence of where iOS sends a
// tap at a point. A measurement that cannot go on fails the test with a line saying why, after the others have run.

/// Why a measurement could not go on.
struct MeasureError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

/// The span of a key's face along a line of pixels, in points.
struct FaceSpan {
    let start: Double
    let end: Double
    /// The face reaches the first or the last pixel of the line (the key's frame), so it may run past it.
    let touchesStart: Bool
    let touchesEnd: Bool
    /// The share of the line's pixels that are the face's colour.
    let fraction: Double
    let colour: String

    var plausible: Bool {
        fraction >= 0.4 && !(touchesStart && touchesEnd)
    }
}

/// A screenshot's pixels: 8-bit RGBA, rows from the top of the screen.
struct ScreenPixels {
    let width: Int
    let height: Int
    /// Pixels per point.
    let scale: Double
    let bytes: [UInt8]

    @MainActor
    init?(_ screenshot: XCUIScreenshot, screenWidth: Double) {
        guard let image = screenshot.image.cgImage, screenWidth > 0 else { return nil }
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.width = width
        self.height = height
        self.scale = Double(width) / screenWidth
        self.bytes = bytes
    }

    func colour(_ x: Int, _ y: Int) -> UInt32 {
        let index = (y * width + x) * 4
        return UInt32(bytes[index]) << 16 | UInt32(bytes[index + 1]) << 8 | UInt32(bytes[index + 2])
    }

    static func close(_ one: UInt32, _ other: UInt32) -> Bool {
        let shifts: [UInt32] = [16, 8, 0]
        return shifts.allSatisfy { shift in
            abs(Int((one >> shift) & 0xff) - Int((other >> shift) & 0xff)) <= 8
        }
    }

    /// The face along `samples`, the pixels from `first` on: the first and last pixel within 8 of their most common
    /// colour.
    func span(_ samples: [UInt32], from first: Int) -> FaceSpan? {
        var counts: [UInt32: Int] = [:]
        for sample in samples {
            counts[sample, default: 0] += 1
        }
        guard let mode = counts.max(by: { $0.value < $1.value })?.key else { return nil }
        let face = samples.indices.filter { ScreenPixels.close(samples[$0], mode) }
        guard let low = face.first, let high = face.last else { return nil }
        return FaceSpan(
            start: Double(first + low) / scale, end: Double(first + high + 1) / scale, touchesStart: low == 0,
            touchesEnd: high == samples.count - 1, fraction: Double(face.count) / Double(samples.count),
            colour: String(format: "#%06x", mode))
    }

    /// The face down the column at `x`, between `top` and `bottom` (points).
    func vertical(x: Double, top: Double, bottom: Double) -> FaceSpan? {
        let column = Int(x * scale)
        let first = Int((top * scale).rounded())
        let last = Int((bottom * scale).rounded())
        guard column >= 0, column < width, first >= 0, last <= height, last - first > 2 else { return nil }
        return span((first..<last).map { colour(column, $0) }, from: first)
    }

    /// The face along the row at `y`, between `left` and `right` (points).
    func horizontal(y: Double, left: Double, right: Double) -> FaceSpan? {
        let row = Int(y * scale)
        let first = Int((left * scale).rounded())
        let last = Int((right * scale).rounded())
        guard row >= 0, row < height, first >= 0, last <= width, last - first > 2 else { return nil }
        return span((first..<last).map { colour($0, row) }, from: first)
    }
}

/// What one tap did.
struct TapOutcome {
    /// What the tap added to the field (the field's whole text if it did not just add to it).
    let typed: String
    let plane: String
    /// What else happened: an alert, another plane, no keyboard.
    let opened: String

    /// A short name of the outcome, for the summaries.
    var kind: String {
        var parts: [String] = []
        if !typed.isEmpty {
            parts.append(typed == " " ? "space" : "typed \(typed.debugDescription)")
        }
        if plane != "letters" {
            parts.append("the \(plane) plane")
        }
        if !opened.isEmpty {
            parts.append("opened \(opened)")
        }
        return parts.isEmpty ? "nothing" : parts.joined(separator: " and ")
    }
}

func pointText(_ point: CGPoint) -> String {
    String(format: "(%.1f,%.1f)", Double(point.x), Double(point.y))
}

func number(_ value: Double) -> String {
    String(format: "%.1f", value)
}

/// The code points of `text`, as U+XXXX, or "none".
func codePoints(_ text: String) -> String {
    text.isEmpty ? "none" : text.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
}

/// The runs of equal outcomes along a line of taps: "label-label: kind" each, joined with "; ".
func runs(_ taps: [(label: String, kind: String)]) -> [(first: String, last: String, kind: String)] {
    var found: [(first: String, last: String, kind: String)] = []
    for tap in taps {
        if let previous = found.last, previous.kind == tap.kind {
            found[found.count - 1] = (previous.first, tap.label, tap.kind)
        } else {
            found.append((tap.label, tap.label, tap.kind))
        }
    }
    return found
}

func runsText(_ found: [(first: String, last: String, kind: String)], unit: String) -> String {
    found.map { run in
        (run.first == run.last ? "\(run.first)\(unit)" : "\(run.first)-\(run.last)\(unit)") + ": \(run.kind)"
    }.joined(separator: "; ")
}

@MainActor
final class AppleKeyboardMeasurer {
    let app = XCUIApplication()
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let field: XCUIElement
    let deadline: Date
    /// How long a tap has to change the field or the plane before it counts as having done nothing.
    let bound: TimeInterval = 3
    let placeholder = "Type here"
    var taps = 0
    var window = CGRect.zero
    var keyboard = CGRect.zero
    var letters: [KeyboardItem] = []
    var numbers: [KeyboardItem] = []
    var symbols: [KeyboardItem] = []
    var pixels: ScreenPixels?
    /// What the field holds before each tap of measurements 1 to 3: one letter, typed in the empty field.
    var base = ""

    init(budget: TimeInterval) {
        field = app.textFields["TryField"]
        deadline = Date().addingTimeInterval(budget)
    }

    func record(_ line: String) {
        print("speakboard-measure \(line)")
    }

    // MARK: The keyboard and the field

    func launch() throws {
        app.launchArguments = ["-SpeakboardPlainField"]
        app.launch()
        guard field.waitForExistence(timeout: 20) else { throw MeasureError("the app's field did not come up") }
        for _ in 0..<20 {
            if plane() == "letters" {
                return
            }
            sleep(1)
        }
        throw MeasureError("no on-screen keyboard with letter keys came up (is a hardware keyboard connected?)")
    }

    func text() -> String {
        let value = (field.value as? String) ?? ""
        return value == placeholder ? "" : value
    }

    /// The plane on screen, from one query: "letters", "numbers", "symbols", "other" (a keyboard with none of their
    /// keys, such as the emoji keyboard) or "none" (no keyboard).
    func plane() -> String {
        let probe = app.keyboards.keys.matching(NSPredicate(format: "label IN %@", ["q", "Q", "1", "["])).firstMatch
        guard probe.exists else {
            return app.keyboards.firstMatch.exists ? "other" : "none"
        }
        switch probe.label {
        case "1": return "numbers"
        case "[": return "symbols"
        default: return "letters"
        }
    }

    func alertTexts() -> [String] {
        (app.alerts.allElementsBoundByIndex + springboard.alerts.allElementsBoundByIndex).map(\.label)
    }

    func dismissAlerts() {
        let names = ["not now", "cancel", "don't allow", "don’t allow", "ok", "close", "done"]
        for alert in app.alerts.allElementsBoundByIndex + springboard.alerts.allElementsBoundByIndex {
            let buttons = alert.buttons.allElementsBoundByIndex
            let button = buttons.first { names.contains($0.label.lowercased()) } ?? buttons.first
            say("dismissing the alert \(alert.label.debugDescription) with \(button?.label.debugDescription ?? "none")")
            button?.tap()
        }
    }

    func tap(_ point: CGPoint) throws {
        guard Date() < deadline else { throw MeasureError("the measurement pass ran out of its time budget") }
        taps += 1
        app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: point.x, dy: point.y)).tap()
    }

    func centre(_ item: KeyboardItem) -> CGPoint {
        CGPoint(x: item.frame.midX, y: item.frame.midY)
    }

    /// Waits up to `bound` seconds for the field to differ from `text` or the plane from `plane`.
    func waitForChange(text before: String, plane planeBefore: String) -> (text: String, plane: String) {
        let start = Date()
        var now = text()
        var currentPlane = plane()
        while now == before && currentPlane == planeBefore && Date().timeIntervalSince(start) < bound {
            Thread.sleep(forTimeInterval: 0.1)
            now = text()
            currentPlane = plane()
        }
        if now != before || currentPlane != planeBefore {
            // Let a change finish (a replaced character), then read again.
            Thread.sleep(forTimeInterval: 0.3)
            now = text()
            currentPlane = plane()
        }
        return (now, currentPlane)
    }

    func key(_ items: [KeyboardItem], _ what: String, _ matches: (KeyboardItem) -> Bool) throws -> KeyboardItem {
        guard let item = items.first(where: matches) else { throw MeasureError("no \(what) in the tree") }
        return item
    }

    func items(of planeName: String) -> [KeyboardItem] {
        switch planeName {
        case "numbers": return numbers
        case "symbols": return symbols
        default: return letters
        }
    }

    /// Goes to `target` by its plane keys.
    func goTo(_ target: String) throws {
        for _ in 0..<4 {
            let now = plane()
            if now == target {
                return
            }
            let item: KeyboardItem
            switch (now, target) {
            case ("letters", _):
                item = try key(letters, "123 key") { $0.identifier == "more" }
            case ("numbers", "symbols"):
                item = try key(numbers, "#+= key") { $0.label.lowercased() == "symbols" }
            case ("symbols", "numbers"):
                item = try key(symbols, "123 key of the symbols plane") { $0.label.lowercased() == "numbers" }
            case ("numbers", "letters"), ("symbols", "letters"):
                item = try key(items(of: now), "ABC key") { $0.identifier == "more" }
            default:
                throw MeasureError("cannot go from the \(now) plane to the \(target) plane")
            }
            try tap(centre(item))
            _ = waitForChange(text: text(), plane: now)
        }
        throw MeasureError("did not reach the \(target) plane (now \(plane()))")
    }

    /// Taps delete `count` times in the plane on screen.
    func delete(_ count: Int) throws {
        for _ in 0..<count {
            let now = plane()
            let delete = try key(items(of: now), "delete key in the \(now) plane") { $0.identifier == "delete" }
            let before = text()
            try tap(centre(delete))
            _ = waitForChange(text: before, plane: now)
        }
    }

    /// Makes the field hold `target`, "" or `base`, by deletes and a tap on "a" in the letters plane.
    func setField(_ target: String) throws {
        var now = text()
        if now == target {
            return
        }
        if !now.isEmpty {
            guard now.count <= 8 else {
                throw MeasureError("the field holds \(now.debugDescription), too much to delete")
            }
            if !target.isEmpty && now.hasPrefix(target) {
                try delete(now.count - target.count)
            } else {
                try delete(now.count)
            }
            now = text()
        }
        if now.isEmpty && !target.isEmpty {
            try goTo("letters")
            let a = try key(letters, "the key a") { $0.type == .key && $0.label.lowercased() == "a" }
            try tap(centre(a))
            now = waitForChange(text: "", plane: "letters").text
        }
        guard now == target else {
            throw MeasureError("the field reads \(now.debugDescription), not \(target.debugDescription)")
        }
    }

    /// Back to the letters plane and the field holding `target`, relaunching the app if that is the only way.
    func recover(_ why: String, field target: String) throws {
        say("getting back to a known state: \(why)")
        if !alertTexts().isEmpty {
            dismissAlerts()
        }
        if ["numbers", "symbols"].contains(plane()) {
            try? goTo("letters")
        }
        if plane() != "letters" || (try? setField(target)) == nil {
            say("relaunching the app (plane \(plane()), field \(text().debugDescription))")
            app.terminate()
            try launch()
            try setField(target)
        }
    }

    /// Taps `point` with the field holding `base` in the letters plane, and reads what it did.
    func tapAndRead(_ point: CGPoint) throws -> TapOutcome {
        if text() != base || plane() != "letters" {
            try recover("the field reads \(text().debugDescription) in the \(plane()) plane before a tap", field: base)
        }
        try tap(point)
        let after = waitForChange(text: base, plane: "letters")
        var opened: [String] = []
        if after.text == base && after.plane == "letters" {
            let alerts = alertTexts()
            if !alerts.isEmpty {
                opened.append("an alert \(alerts)")
                dismissAlerts()
            }
        }
        if after.plane == "other" || after.plane == "none" {
            opened.append(after.plane == "none" ? "no keyboard" : "a keyboard with no letter, digit or symbol keys")
        }
        let typed = after.text.hasPrefix(base) ? String(after.text.dropFirst(base.count)) : after.text
        return TapOutcome(typed: typed, plane: after.plane, opened: opened.joined(separator: ", "))
    }

    /// After a tap: back to the letters plane and `base` in the field. Returns the plane it went back from, if any.
    func restore(_ outcome: TapOutcome) throws -> String {
        var back = ""
        if ["numbers", "symbols"].contains(outcome.plane) {
            try goTo("letters")
            back = " back=\(plane())"
        } else if outcome.plane != "letters" {
            try recover("a tap opened \(outcome.kind)", field: base)
            back = " back=\(plane())"
        }
        if text() != base {
            try setField(base)
        }
        return back
    }

    func line(_ outcome: TapOutcome) -> String {
        "typed=\(outcome.typed.debugDescription) \(codePoints(outcome.typed)) plane=\(outcome.plane)"
            + (outcome.opened.isEmpty ? "" : " opened=\(outcome.opened.debugDescription)")
    }

    // MARK: Faces

    /// The top and bottom of `item`'s face down the column at `x` (in its frame), from the screenshot, or its
    /// frame's when the screenshot gives no plausible face. Logged.
    func verticalFace(_ name: String, _ item: KeyboardItem, x: Double) -> (top: Double, bottom: Double) {
        let frame = item.frame
        let found = pixels?.vertical(x: x, top: Double(frame.minY), bottom: Double(frame.maxY))
        let frameText = "frame=\(frame)"
        if let found, found.plausible {
            record(
                "face \(name) column x=\(number(x)) \(frameText) top=\(number(found.start)) bottom=\(number(found.end))"
                    + " colour=\(found.colour) share=\(number(found.fraction * 100))%"
                    + (found.touchesStart || found.touchesEnd ? " (reaches the frame's edge)" : ""))
            return (found.start, found.end)
        }
        var detail = "none"
        if let found {
            detail = "\(number(found.start))-\(number(found.end)), share \(number(found.fraction * 100))%"
        }
        record(
            "face \(name) column x=\(number(x)) \(frameText): the screenshot gives no plausible face (\(detail));"
                + " the frame's edges are used")
        return (Double(frame.minY), Double(frame.maxY))
    }

    /// The left and right of `item`'s face along the row at `y`, as `verticalFace`.
    func horizontalFace(_ name: String, _ item: KeyboardItem, y: Double) -> (left: Double, right: Double) {
        let frame = item.frame
        let found = pixels?.horizontal(y: y, left: Double(frame.minX), right: Double(frame.maxX))
        if let found, found.plausible {
            record(
                "face \(name) row y=\(number(y)) frame=\(frame) left=\(number(found.start)) right=\(number(found.end))"
                    + " colour=\(found.colour) share=\(number(found.fraction * 100))%"
                    + (found.touchesStart || found.touchesEnd ? " (reaches the frame's edge)" : ""))
            return (found.start, found.end)
        }
        record(
            "face \(name) row y=\(number(y)) frame=\(frame): the screenshot gives no plausible face; the frame's edges"
                + " are used")
        return (Double(frame.minX), Double(frame.maxX))
    }

    func letterKeys() -> [KeyboardItem] {
        letters.filter { item in
            item.type == .key && item.label.count == 1 && item.label.first?.isLetter == true
        }
    }

    /// The letter rows, top to bottom, each left to right.
    func letterRows() -> [[KeyboardItem]] {
        let keys = letterKeys()
        let tops = Set(keys.map { Int(Double($0.frame.minY).rounded()) }).sorted()
        return tops.map { top in
            keys.filter { Int(Double($0.frame.minY).rounded()) == top }.sorted { $0.frame.minX < $1.frame.minX }
        }
    }

    // MARK: Setup

    func setUp() throws {
        try launch()
        window = app.windows.firstMatch.frame
        keyboard = app.keyboards.firstMatch.frame
        say("measurements: window \(window), keyboard \(keyboard), field \(field.frame)")
        try setField("")
        letters = try keyboardTree(app)
        say("measurements: the letters plane has \(letters.count) elements")
        // The faces, from a screenshot of the letters plane at rest.
        sleep(1)
        pixels = ScreenPixels(XCUIScreen.main.screenshot(), screenWidth: Double(window.width))
        if let pixels {
            say("measurements: screenshot \(pixels.width)x\(pixels.height) pixels, \(pixels.scale) a point")
        } else {
            say("measurements: no pixels from the screenshot")
        }
        try goTo("numbers")
        numbers = try keyboardTree(app)
        try goTo("symbols")
        symbols = try keyboardTree(app)
        try goTo("letters")
        for (name, items) in [("letters", letters), ("numbers", numbers), ("symbols", symbols)] {
            let keys = items.filter { $0.type == .key || $0.type == .button }
            let described = keys.map { "\($0.label)@\(pointText(CGPoint(x: $0.frame.minX, y: $0.frame.minY)))" }
            say(
                "measurements: the \(name) plane's keys and buttons (label@origin): \(described.joined(separator: " "))"
            )
        }
        try setField("")
        let a = try key(letters, "the key a") { $0.type == .key && $0.label.lowercased() == "a" }
        try tap(centre(a))
        base = waitForChange(text: "", plane: "letters").text
        say("measurements: the field's state before each tap of 1 to 3: \(base.debugDescription)")
        guard base.count == 1 else { throw MeasureError("a tap on a typed \(base.debugDescription)") }
    }

    // MARK: 1. Under the bottom row

    func underBottomRow() throws {
        let space = try key(letters, "space bar") { $0.identifier == "space" }
        let x = Double(space.frame.midX)
        let face = verticalFace("space", space, x: x)
        let frameGap = Double(keyboard.maxY) - face.bottom
        let last = Int(frameGap.rounded(.down)) + 7
        record(
            "under-space: the keyboard frame ends \(number(frameGap)) pt under the space bar's face;"
                + " taps 1 to \(last) pt")
        var spaceTaps: [(label: String, kind: String)] = []
        for d in 1...last {
            let point = CGPoint(x: x, y: face.bottom + Double(d))
            let outcome = try tapAndRead(point)
            let back = try restore(outcome)
            record("under-space d=\(d) point=\(pointText(point)) \(line(outcome))\(back)")
            spaceTaps.append(("\(d)", outcome.kind))
        }
        let found = runs(spaceTaps)
        var statement = "runs: \(runsText(found, unit: " pt"))"
        if found.count == 2, found[0].first == "1", found[0].kind == "space", found[1].kind == "nothing" {
            statement =
                "a tap up to \(found[0].last) pt under the space bar's face types a space; from \(found[1].first) pt"
                + " to \(found[1].last) pt it types nothing (the keyboard frame ends \(number(frameGap)) pt under it)"
        } else if found.count == 1 {
            statement = "every tap from 1 to \(last) pt under the space bar's face: \(found[0].kind)"
        }
        record("summary under-space: \(statement)")

        let more = try key(letters, "123 key") { $0.identifier == "more" }
        let moreX = Double(more.frame.midX)
        let moreFace = verticalFace("123", more, x: moreX)
        let inside = Double(keyboard.maxY) - moreFace.bottom
        var offsets: [Double] = []
        var d = 1.0
        while d < inside {
            offsets.append(d)
            d += 1
        }
        if inside - 0.5 > (offsets.last ?? 0) {
            offsets.append(inside - 0.5)
        }
        var moreTaps: [(label: String, kind: String)] = []
        for d in offsets {
            let point = CGPoint(x: moreX, y: moreFace.bottom + d)
            let outcome = try tapAndRead(point)
            let back = try restore(outcome)
            record("under-123 d=\(number(d)) point=\(pointText(point)) \(line(outcome))\(back)")
            moreTaps.append((number(d), outcome.kind))
        }
        let moreRuns = runs(moreTaps)
        var moreStatement = "runs: \(runsText(moreRuns, unit: " pt"))"
        if moreRuns.count == 1 {
            moreStatement =
                "every tap from 1 to \(number(offsets.last ?? 0)) pt under the 123 key's face, inside the keyboard"
                + " frame: \(moreRuns[0].kind)"
        } else if moreRuns.count == 2, moreRuns[1].kind == "nothing" {
            moreStatement =
                "a tap up to \(moreRuns[0].last) pt under the 123 key's face gives \(moreRuns[0].kind); from"
                + " \(moreRuns[1].first) pt to the frame's bottom it does nothing"
        }
        record("summary under-123: \(moreStatement)")
    }

    // MARK: 2. Between two rows

    /// Taps from `upper`'s face bottom to `lower`'s face top, 1 pt apart, at `x` (a third-row letter's centre).
    func between(_ name: String, upper: KeyboardItem, lower: KeyboardItem, x: Double) throws {
        let upperName = upper.identifier == "space" ? "space" : upper.label.lowercased()
        let lowerName = lower.identifier == "space" ? "space" : lower.label.lowercased()
        let upperFace = verticalFace(upperName, upper, x: x)
        let lowerFace = verticalFace(lowerName, lower, x: x)
        let gap = lowerFace.top - upperFace.bottom
        record(
            "between \(name): the gap is \(number(gap)) pt, from y \(number(upperFace.bottom))"
                + " to \(number(lowerFace.top))")
        var taps: [(label: String, kind: String)] = []
        for k in 0...max(Int(gap.rounded()), 0) {
            let point = CGPoint(x: x, y: upperFace.bottom + Double(k))
            let outcome = try tapAndRead(point)
            let back = try restore(outcome)
            let over = lowerFace.top - Double(point.y)
            record(
                "between \(name) y=\(number(Double(point.y))) under-\(upperName)=\(k) over-\(lowerName)=\(number(over))"
                    + " point=\(pointText(point)) \(line(outcome))\(back)")
            taps.append(("\(k)", outcome.kind))
        }
        let found = runs(taps)
        var statement = "runs, in pt under \(upperName)'s face: \(runsText(found, unit: ""))"
        if found.count == 2 {
            let last = Int(found[0].last) ?? 0
            statement =
                "in the \(number(gap)) pt between \(upperName) and \(lowerName), a tap 0 to \(found[0].last) pt under"
                + " \(upperName)'s face gives \(found[0].kind); from \(found[1].first) pt under it"
                + " (\(number(gap - Double(last + 1))) pt over \(lowerName)'s face) it gives \(found[1].kind)"
        } else if found.count == 1 {
            statement = "every tap in the \(number(gap)) pt between \(upperName) and \(lowerName): \(found[0].kind)"
        }
        record("summary between \(name): \(statement)")
    }

    func betweenRows() throws {
        let rows = letterRows()
        guard rows.count == 3 else { throw MeasureError("\(rows.count) letter rows, not 3") }
        // A third-row letter with a second-row letter straight above it: the pair whose centres are closest in x.
        var best: (upper: KeyboardItem, lower: KeyboardItem, offset: CGFloat)?
        for lower in rows[2] {
            for upper in rows[1] where upper.frame.minX <= lower.frame.midX && lower.frame.midX <= upper.frame.maxX {
                let offset = abs(upper.frame.midX - lower.frame.midX)
                if best == nil || offset < best?.offset ?? 0 {
                    best = (upper, lower, offset)
                }
            }
        }
        guard let pair = best else { throw MeasureError("no third-row letter with a second-row letter above it") }
        say("between: \(pair.lower.label) under \(pair.upper.label), centres \(number(Double(pair.offset))) pt apart")
        try between(
            "\(pair.upper.label.lowercased())-\(pair.lower.label.lowercased())", upper: pair.upper, lower: pair.lower,
            x: Double(pair.lower.frame.midX))

        let space = try key(letters, "space bar") { $0.identifier == "space" }
        let overSpace = rows[2].filter { space.frame.minX <= $0.frame.midX && $0.frame.midX <= space.frame.maxX }
        guard
            let letter = overSpace.min(by: {
                abs($0.frame.midX - space.frame.midX) < abs($1.frame.midX - space.frame.midX)
            })
        else { throw MeasureError("no third-row letter over the space bar") }
        try between("\(letter.label.lowercased())-space", upper: letter, lower: space, x: Double(letter.frame.midX))
    }

    // MARK: 3. Beside the "a" row

    func besideRow() throws {
        let a = try key(letters, "the key a") { $0.type == .key && $0.label.lowercased() == "a" }
        let l = try key(letters, "the key l") { $0.type == .key && $0.label.lowercased() == "l" }
        let aFace = verticalFace("a", a, x: Double(a.frame.midX))
        let y = (aFace.top + aFace.bottom) / 2
        let left = horizontalFace("a", a, y: y).left
        let right = horizontalFace("l", l, y: y).right
        let width = Double(window.width)
        var leftPoints: [Double] = []
        var x = 0.5
        while x < left {
            leftPoints.append(x)
            x += 2
        }
        if let lastPoint = leftPoints.last, left - 0.5 > lastPoint + 0.5 {
            leftPoints.append(left - 0.5)
        }
        var rightPoints: [Double] = []
        x = width - 0.5
        while x > right {
            rightPoints.append(x)
            x -= 2
        }
        if let lastPoint = rightPoints.last, right + 0.5 < lastPoint - 0.5 {
            rightPoints.append(right + 0.5)
        }
        for (side, points, edge, letter) in [
            ("left-of-a", leftPoints, left, "a"), ("right-of-l", rightPoints, right, "l"),
        ] {
            var taps: [(label: String, kind: String)] = []
            for pointX in points {
                let point = CGPoint(x: pointX, y: y)
                let outcome = try tapAndRead(point)
                let back = try restore(outcome)
                record(
                    "beside \(side) x=\(number(pointX)) from-\(letter)=\(number(abs(edge - pointX)))"
                        + " point=\(pointText(point)) \(line(outcome))\(back)")
                taps.append((number(pointX), outcome.kind))
            }
            let found = runs(taps)
            var statement = "runs, by x: \(runsText(found, unit: ""))"
            if found.count == 1 {
                statement =
                    "every tap from x \(number(points.first ?? 0)) to \(number(points.last ?? 0)) (the \(letter) key's"
                    + " face edge is at x \(number(edge))): \(found[0].kind)"
            }
            record("summary beside \(side): \(statement)")
        }
    }

    // MARK: 4. What the number and symbol keys type

    /// The keys of a plane's three upper rows, but delete and the plane keys, top to bottom, left to right.
    func upperKeys(_ items: [KeyboardItem]) -> [KeyboardItem] {
        let bottomRow = items.first { $0.identifier == "space" }?.frame.minY ?? .greatestFiniteMagnitude
        return items.filter { item in
            item.type == .key && !["delete", "more", "space"].contains(item.identifier)
                && !item.label.hasPrefix("Padding") && item.frame.midY < bottomRow
        }.sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
    }

    /// Taps `item` in `planeName` with the field holding `before`, and reads what it typed and the plane after it.
    func typeKey(_ item: KeyboardItem, in planeName: String, after before: String) throws -> (
        typed: String, plane: String
    ) {
        try setField(before)
        try goTo(planeName)
        guard text() == before else { throw MeasureError("the field reads \(text().debugDescription) before a key") }
        try tap(centre(item))
        let after = waitForChange(text: before, plane: planeName)
        let typed = after.text.hasPrefix(before) ? String(after.text.dropFirst(before.count)) : after.text
        return (typed, after.plane)
    }

    func planeKeys() throws {
        var backToLetters: [String: [String]] = [:]
        for (planeName, items) in [("numbers", numbers), ("symbols", symbols)] {
            let keys = upperKeys(items)
            say("keys: \(keys.count) keys in the \(planeName) plane's upper rows")
            for item in keys {
                // One key that cannot be read is reported, and the next is tried from a known state.
                do {
                    let result = try typeKey(item, in: planeName, after: "")
                    try delete(result.typed.count)
                    let cleared = plane()
                    record(
                        "key plane=\(planeName) label=\(item.label.debugDescription)"
                            + " typed=\(result.typed.debugDescription) \(codePoints(result.typed))"
                            + " after=\(result.plane) cleared=\(cleared)")
                    if result.plane != planeName {
                        backToLetters[planeName, default: []].append("\(item.label) (to \(result.plane))")
                    }
                } catch {
                    guard Date() < deadline else { throw error }
                    record("failed key plane=\(planeName) label=\(item.label.debugDescription): \(error)")
                    XCTFail("the key \(item.label) in the \(planeName) plane: \(error)")
                }
                if text() != "" {
                    try recover("the field is not empty after a key and its deletes", field: "")
                }
            }
        }
        for label in ["\"", "'"] {
            let item = try key(numbers, "the \(label) key") { $0.type == .key && $0.label == label }
            try setField("")
            try setField(base)
            let result = try typeKey(item, in: "numbers", after: base)
            record(
                "key-after-letter plane=numbers label=\(label.debugDescription) before=\(base.debugDescription)"
                    + " typed=\(result.typed.debugDescription) \(codePoints(result.typed)) after=\(result.plane)")
            try delete(result.typed.count)
            try goTo("letters")
            try setField("")
        }
        // The rules for going back to letters.
        let one = try key(numbers, "the 1 key") { $0.type == .key && $0.label == "1" }
        let digit = try typeKey(one, in: "numbers", after: "")
        let space = try key(numbers, "the numbers plane's space bar") { $0.identifier == "space" }
        let beforeSpace = text()
        try tap(centre(space))
        let afterSpace = waitForChange(text: beforeSpace, plane: digit.plane)
        record(
            "plane-rule digit-then-space: \"1\" typed \(digit.typed.debugDescription)"
                + " and left the \(digit.plane) plane;"
                + " then the space bar typed \(String(afterSpace.text.dropFirst(beforeSpace.count)).debugDescription)"
                + " and left the \(afterSpace.plane) plane")
        try delete(afterSpace.text.count)
        try goTo("letters")
        try setField("")
        let apostrophe = try key(numbers, "the ' key") { $0.type == .key && $0.label == "'" }
        let quote = try typeKey(apostrophe, in: "numbers", after: "")
        record(
            "plane-rule apostrophe: \"'\" typed \(quote.typed.debugDescription) \(codePoints(quote.typed)) and left the"
                + " \(quote.plane) plane")
        try delete(quote.typed.count)
        try goTo("letters")
        for planeName in ["numbers", "symbols"] {
            let keys = backToLetters[planeName] ?? []
            record(
                "summary planes \(planeName): "
                    + (keys.isEmpty
                        ? "no key of the upper rows left the plane"
                        : "the keys after which the keyboard left the plane: \(keys.joined(separator: ", "))"))
        }
    }

    // MARK: The pass

    func attempt(_ name: String, _ body: () throws -> Void) {
        let start = Date()
        let before = taps
        do {
            try body()
        } catch {
            record("failed \(name): \(error)")
            XCTFail("measurement \(name): \(error)")
            if Date() < deadline {
                do {
                    try recover("after the failure of \(name)", field: "")
                } catch {
                    say("could not get back to a known state: \(error)")
                }
            }
        }
        let seconds = String(format: "%.0f", Date().timeIntervalSince(start))
        record("time \(name): \(taps - before) taps in \(seconds) s")
    }

    func run() {
        let start = Date()
        attempt("setup") { try setUp() }
        guard !base.isEmpty else {
            record("done: the setup failed, so nothing was measured")
            return
        }
        attempt("under the bottom row") { try underBottomRow() }
        attempt("between two rows") { try betweenRows() }
        attempt("beside the a row") { try besideRow() }
        attempt("what the number and symbol keys type") { try planeKeys() }
        let seconds = String(format: "%.0f", Date().timeIntervalSince(start))
        record("done: \(taps) taps in \(seconds) s (a tap with no change in \(number(bound)) s counts as nothing)")
    }
}

final class AppleKeyboardMeasurementsUITests: XCTestCase {
    override func setUp() {
        // A measurement that fails is reported, and the others still run.
        continueAfterFailure = true
    }

    @MainActor
    func testMeasuresAppleKeyboard() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["SPEAKBOARD_APPLE_MEASUREMENTS"] == "1",
            "only scripts/sim-keyboard.sh runs it, on the capture simulator after the captures")
        testStart = Date()
        say("apple measurements began, \(ProcessInfo.processInfo.environment["SPEAKBOARD_APPEARANCE"] ?? "light")")
        // A budget of 20 minutes, so the simulator step stays inside its limit: past it, no more taps.
        AppleKeyboardMeasurer(budget: 20 * 60).run()
        say("apple measurements done")
    }
}
