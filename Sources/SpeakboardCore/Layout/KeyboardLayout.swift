// The keyboard's layout: the frame of every key and the key under a touch point,
// for one locale, device class and orientation. Every length comes from the
// generated metrics tables (GeneratedMetrics.swift), so the core and the
// keyboard extension cannot drift from the design tokens.
//
// Hit-testing allocates nothing: the frames are computed once, when the layout
// is built, and `key(at:)` and `keyIndex(nearest:)` only read them. Key and
// KeyKind are plain values with no references in them.
//
// Two hit-tests (KEY-24). `key(at:)` is exact: the key whose face contains the
// point, so a point in a gap between keys hits nothing. `keyIndex(nearest:)` is
// what touch handling uses: every point of `touchArea` belongs to a key, so a
// finger that lands or lifts in a gap, or in the margin beside the row that
// starts with "a", still types. `touchArea` is the view below the suggestion
// strip, reaching sideways beyond the outermost keys by the vertical gap between
// rows (`key.gap.vertical`) and no further, and never past the view. In portrait
// the side insets are narrower than that gap, so the whole width resolves; in
// landscape on Face ID classes the key area is inset 60 pt from each side, and
// only the first row gap's worth of each margin resolves. A finger that lands
// outside the touch area (a dead margin, or the strip) is on no key, but it is
// still a finger to touch handling (KeyTouches): its landing finishes the open
// finger (commits its letter, or ends a Delete hold), and if it slides into the
// touch area and lifts there, it types the key it lifts on. Only its own key
// is missing while it is outside: lifted outside, it types nothing. The rule is ours (the reach is the
// orchestrator's decision in KEY-24 review round 1), plain arithmetic on the
// frames, not measured from Apple's keyboard: Apple's keyboard also moves its
// hit targets with what is likely to be typed next, and nothing here does that
// or claims to match Apple's targets. Assumptions, for a device test (rung 4):
// that the nearest key by this rule is what a finger in a gap means, and that
// the reach beyond the outermost keys is right.
//
// The bottom row is Apple's default row, as the token export assumes it when it
// derives key.space.width: 123, emoji, space, return on iPhones with a home
// indicator; 123, globe, dictation, space, return on iPhones with a home button.
// It is not our final bottom row. Where our own mic key goes is an open
// decision, outside the tokens (the export calls it "a canvas decision, not a
// token"), and this layout does not make it.

/// What a key is.
public enum KeyKind: Equatable, Sendable {
    /// A letter key, with its lowercase letter.
    case letter(Unicode.Scalar)
    /// Shift, at the left of row 3.
    case shift
    /// Delete, at the right of row 3.
    case delete
    /// The "123" key, at the left of the bottom row.
    case modeSwitch
    /// The emoji key, in Apple's default bottom row on iPhones with a home indicator. Our mic key's slot is not
    /// decided yet; see the note at the top of this file.
    case emoji
    /// The globe key, in Apple's default bottom row on iPhones with a home button. Our mic key's slot is not
    /// decided yet; see the note at the top of this file.
    case globe
    /// Apple's dictation key, in Apple's default bottom row on iPhones with a home button. It is not our mic key,
    /// whose slot is not decided yet; see the note at the top of this file.
    case dictation
    /// The space bar.
    case space
    /// Return, at the right of the bottom row.
    case returnKey
}

/// Which key a touch belongs to: `KeyboardLayout.keyIndex(at:by:)`.
public enum HitTesting: Equatable, Sendable {
    /// Only the key whose frame contains the point (`keyIndex(at:)`): a touch in a gap belongs to no key. Touch
    /// handling used this before KEY-24; tests use it to show what the nearest-key rule changes.
    case exact
    /// The nearest key (`keyIndex(nearest:)`): a touch anywhere in `touchArea` belongs to a key. What touch
    /// handling uses.
    case nearest
}

/// A key and its frame in the keyboard view.
public struct Key: Equatable, Sendable {
    /// What the key is.
    public let kind: KeyKind
    /// The key face's frame, in the keyboard view's coordinates.
    public let frame: LayoutRect
}

/// The letters layout of one locale on one device class in one orientation.
///
/// The keyboard view is the suggestion bar's strip on top and the key area below it, as wide as the screen in
/// this orientation. Its height is `keyboard.totalHeight`. The strip holds nothing yet.
public struct KeyboardLayout: Sendable {
    /// The locale whose letters layout this is: the one the data holds, which can be the language of the locale
    /// asked for (see `init`).
    public let locale: KeyboardLocale
    /// The device class.
    public let deviceClass: DeviceClass
    /// The orientation.
    public let orientation: Orientation
    /// The metrics row the layout was built from.
    public let metrics: Metrics
    /// The keyboard view's size: the screen width in this orientation by `keyboard.totalHeight`.
    public let size: LayoutSize
    /// The suggestion bar's strip, across the top of the view, `suggestionBar.height` high. Empty.
    public let suggestionStrip: LayoutRect
    /// The key area below the strip: `keyboard.keyArea.width` by `keyboard.keyArea.height`, inset from each
    /// screen edge by `keyboard.inset.side`.
    public let keyArea: LayoutRect
    /// Every key, row by row from the top, each row from left to right.
    public let keys: [Key]
    /// Where the nearest-key hit-test finds a key (`keyIndex(nearest:)`): from the strip's bottom to the view's
    /// bottom, and from `key.gap.vertical` left of the leftmost key's left edge to `key.gap.vertical` right of the
    /// rightmost key's right edge, clipped to the view.
    public let touchArea: LayoutRect

    /// The layout for `locale` on `deviceClass` in `orientation`, or nil if neither the locale nor its language
    /// has layout data. The data for the locale itself is used if there is any, otherwise its language's: "en-US",
    /// "en_GB", "en@calendar=gregorian" and "EN" all get the "en" layout (`KeyboardLocale.language`). "fr" gets nil
    /// today.
    public init?(locale: KeyboardLocale, deviceClass: DeviceClass, orientation: Orientation) {
        guard let (dataLocale, letters) = LetterLayouts.rows(for: locale) else { return nil }
        let metrics = Metrics.of(deviceClass, orientation)
        let width = orientation == .portrait ? deviceClass.screenWidth : deviceClass.screenHeight

        self.locale = dataLocale
        self.deviceClass = deviceClass
        self.orientation = orientation
        self.metrics = metrics
        self.size = LayoutSize(width: width, height: metrics.keyboardTotalHeight.value)
        self.suggestionStrip = LayoutRect(x: 0, y: 0, width: width, height: metrics.suggestionBarHeight.value)
        let keyArea = LayoutRect(
            x: metrics.keyboardInsetSide.value, y: metrics.suggestionBarHeight.value,
            width: metrics.keyboardKeyAreaWidth.value, height: metrics.keyboardKeyAreaHeight.value)
        self.keyArea = keyArea
        let keys = Self.keys(letters: letters, metrics: metrics, keyArea: keyArea, deviceClass: deviceClass)
        self.keys = keys
        let reach = metrics.keyGapVertical.value
        let left = max(0, (keys.map(\.frame.minX).min() ?? keyArea.minX) - reach)
        let right = min(width, (keys.map(\.frame.maxX).max() ?? keyArea.maxX) + reach)
        let top = metrics.suggestionBarHeight.value
        self.touchArea = LayoutRect(
            x: left, y: top, width: right - left, height: metrics.keyboardTotalHeight.value - top)
    }

    /// The key whose frame contains `point`, or nil if none does: in the gaps between keys, in the insets and in
    /// the suggestion bar's strip. A key's left and top edges are inside it, its right and bottom edges outside.
    ///
    /// Allocates nothing, in debug builds too: it indexes the array in a `while` loop, because a `for`-`in` loop
    /// over an array calls the generic `IndexingIterator.next()`, which allocates once per element when the code
    /// is not optimised.
    public func key(at point: LayoutPoint) -> Key? {
        guard let index = keyIndex(at: point) else { return nil }
        return keys[index]
    }

    /// The index in `keys` of the key whose frame contains `point`, or nil: `key(at:)`, as an index. Allocates
    /// nothing.
    public func keyIndex(at point: LayoutPoint) -> Int? {
        var index = 0
        while index < keys.count {
            if keys[index].frame.contains(point) {
                return index
            }
            index += 1
        }
        return nil
    }

    /// The key nearest `point`: `keyIndex(nearest:)`, as a key.
    public func key(nearest point: LayoutPoint, showsInputModeSwitchKey: Bool = true) -> Key? {
        guard let index = keyIndex(nearest: point, showsInputModeSwitchKey: showsInputModeSwitchKey) else {
            return nil
        }
        return keys[index]
    }

    /// The index in `keys` of the key a touch at `point` belongs to, for touch handling (KEY-24). Every point of
    /// `touchArea` belongs to a key, so a touch in a gap between keys or rows, in the margin beside a row that does
    /// not reach the edge (the row that starts with "a"), or in an inset near the keys, still finds one. The rule,
    /// which is ours and not measured (see the note at the top of this file):
    ///
    /// 1. Nil for a point outside `touchArea`: in the suggestion strip (`y` below `suggestionStrip.maxY`), at or past
    ///    the view's bottom, more than `key.gap.vertical` to the left of the leftmost key or at or beyond that distance
    ///    to the right of the rightmost key (the area is half-open, like a frame), outside the view, or not a number.
    /// 2. The key whose frame contains the point, if one does (`keyIndex(at:)`), so a touch on a key is that key.
    /// 3. Otherwise the nearest row: the row whose keys' top-to-bottom span is the least vertical distance from the
    ///    point. Then the nearest key in that row: the one whose left-to-right span is the least horizontal distance
    ///    from it. A gap between two rows is split at its middle, as is a gap between two keys in a row, and a margin
    ///    or inset beside a row's end goes to the key at that end.
    /// 4. Ties go to the key that comes first in `keys`: a point exactly in the middle of the gap between two rows
    ///    goes to the upper row, and one exactly in the middle of the gap between two keys to the left key.
    ///
    /// When `showsInputModeSwitchKey` is false, the next-keyboard (globe) key is not drawn, and it is left out of every
    /// step: its frame and the gaps around it go to its visible neighbours. The keyboard view says whether it is
    /// shown (UIKit's `needsInputModeSwitchKey`); the core only takes the answer.
    ///
    /// Allocates nothing: two `while` loops over the frames.
    public func keyIndex(nearest point: LayoutPoint, showsInputModeSwitchKey: Bool = true) -> Int? {
        // Comparisons with NaN are false, so a point that is not a number fails here.
        guard point.x >= touchArea.minX, point.x < touchArea.maxX, point.y >= touchArea.minY,
            point.y < touchArea.maxY
        else {
            return nil
        }
        if let exact = keyIndex(at: point), showsInputModeSwitchKey || keys[exact].kind != .globe { return exact }

        // The nearest row, named by its keys' top edge: every key in a row has the same top and height.
        var rowTop = 0.0
        var rowDistance = Double.infinity
        var index = 0
        while index < keys.count {
            let frame = keys[index].frame
            if showsInputModeSwitchKey || keys[index].kind != .globe {
                let distance = Self.distance(point.y, from: frame.minY, to: frame.maxY)
                if distance < rowDistance {
                    rowDistance = distance
                    rowTop = frame.minY
                }
            }
            index += 1
        }

        // The nearest key in that row.
        var nearest: Int?
        var keyDistance = Double.infinity
        index = 0
        while index < keys.count {
            let frame = keys[index].frame
            if frame.minY == rowTop && (showsInputModeSwitchKey || keys[index].kind != .globe) {
                let distance = Self.distance(point.x, from: frame.minX, to: frame.maxX)
                if distance < keyDistance {
                    keyDistance = distance
                    nearest = index
                }
            }
            index += 1
        }
        return nearest
    }

    /// The index of the key under a touch at `point`, by `hitTesting`. With `showsInputModeSwitchKey` false, a hidden
    /// next-keyboard key is no key, for either hit-test.
    public func keyIndex(at point: LayoutPoint, by hitTesting: HitTesting, showsInputModeSwitchKey: Bool = true) -> Int?
    {
        switch hitTesting {
        case .exact:
            guard let index = keyIndex(at: point), showsInputModeSwitchKey || keys[index].kind != .globe else {
                return nil
            }
            return index
        case .nearest: return keyIndex(nearest: point, showsInputModeSwitchKey: showsInputModeSwitchKey)
        }
    }

    /// The distance from `value` to the span from `low` to `high`, both included: 0 inside it.
    private static func distance(_ value: Double, from low: Double, to high: Double) -> Double {
        if value < low { return low - value }
        if value > high { return value - high }
        return 0
    }

    private static func keys(
        letters: LetterRows, metrics: Metrics, keyArea: LayoutRect, deviceClass: DeviceClass
    ) -> [Key] {
        let letterWidth = metrics.keyLetterWidth.value
        let keyHeight = metrics.keyLetterHeight.value
        let gap = metrics.keyGapHorizontal.value
        var keys: [Key] = []

        func rowTop(_ row: Int) -> Double {
            keyArea.minY + metrics.keyboardInsetTop.value + Double(row) * (keyHeight + metrics.keyGapVertical.value)
        }

        // Lays out keys left to right from `x`, one gap apart. With `end`, the last key is placed so that it ends
        // at `end`, not where the running sum of widths and gaps puts it: the sum can land a rounding step past the
        // key area's edge.
        func append(_ row: [(KeyKind, Double)], from x: Double, top: Double, endingAt end: Double? = nil) {
            var x = x
            for (index, (kind, width)) in row.enumerated() {
                if let end, index == row.count - 1 { x = end - width }
                keys.append(Key(kind: kind, frame: LayoutRect(x: x, y: top, width: width, height: keyHeight)))
                x += width + gap
            }
        }

        // Lays out letter keys centred between `left` and `right`.
        func appendLetters(_ row: [Unicode.Scalar], between left: Double, and right: Double, top: Double) {
            let rowWidth = Double(row.count) * letterWidth + Double(row.count - 1) * gap
            append(row.map { (.letter($0), letterWidth) }, from: left + (right - left - rowWidth) / 2, top: top)
        }

        // Row 1: letters edge to edge across the key area. Row 2: letters centred in it.
        append(
            letters.rows[0].map { (.letter($0), letterWidth) }, from: keyArea.minX, top: rowTop(0),
            endingAt: keyArea.maxX)
        appendLetters(letters.rows[1], between: keyArea.minX, and: keyArea.maxX, top: rowTop(1))

        // Row 3: shift at the left edge, delete at the right, letters centred between them.
        let shiftWidth = metrics.keyShiftWidth.value
        let deleteWidth = metrics.keyDeleteWidth.value
        append([(.shift, shiftWidth)], from: keyArea.minX, top: rowTop(2))
        appendLetters(
            letters.rows[2], between: keyArea.minX + shiftWidth, and: keyArea.maxX - deleteWidth, top: rowTop(2))
        append([(.delete, deleteWidth)], from: keyArea.maxX - deleteWidth, top: rowTop(2))

        // Row 4, the bottom row: Apple's default, as the export's key.space.width derivation assumes it. Our mic
        // key's slot is an open decision outside the tokens (see the note at the top of this file).
        let utility = metrics.keyUtilityWidth.value
        let utilities: [(KeyKind, Double)] =
            deviceClass.hasHomeIndicator ? [(.emoji, utility)] : [(.globe, utility), (.dictation, utility)]
        let bottomRow =
            [(KeyKind.modeSwitch, metrics.keyModeSwitchWidth.value)] + utilities + [
                (.space, metrics.keySpaceWidth.value), (.returnKey, metrics.keyReturnWidth.value),
            ]
        append(bottomRow, from: keyArea.minX, top: rowTop(3), endingAt: keyArea.maxX)

        return keys
    }
}
