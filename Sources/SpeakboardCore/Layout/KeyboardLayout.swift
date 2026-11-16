// The keyboard's layout: the frame of every key and the key under a touch point,
// for one locale, device class and orientation. Every length comes from the
// generated metrics tables (GeneratedMetrics.swift), so the core and the
// keyboard extension cannot drift from the design tokens.
//
// Hit-testing allocates nothing: the frames are computed once, when the layout
// is built, and `key(at:)` only reads them. Key and KeyKind are plain values
// with no references in them.
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
        self.keys = Self.keys(letters: letters, metrics: metrics, keyArea: keyArea, deviceClass: deviceClass)
    }

    /// The key whose frame contains `point`, or nil if none does: in the gaps between keys, in the insets and in
    /// the suggestion bar's strip. A key's left and top edges are inside it, its right and bottom edges outside.
    ///
    /// Allocates nothing, in debug builds too: it indexes the array in a `while` loop, because a `for`-`in` loop
    /// over an array calls the generic `IndexingIterator.next()`, which allocates once per element when the code
    /// is not optimised.
    public func key(at point: LayoutPoint) -> Key? {
        var index = 0
        while index < keys.count {
            let key = keys[index]
            if key.frame.contains(point) {
                return key
            }
            index += 1
        }
        return nil
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
