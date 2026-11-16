import Testing

@testable import SpeakboardCore

/// Every device class in both orientations.
let allClassesAndOrientations: [(DeviceClass, Orientation)] = DeviceClass.allCases.flatMap { deviceClass in
    Orientation.allCases.map { (deviceClass, $0) }
}

/// The English layout, which exists for every class and orientation.
func englishLayout(_ deviceClass: DeviceClass, _ orientation: Orientation) throws -> KeyboardLayout {
    try #require(KeyboardLayout(locale: .english, deviceClass: deviceClass, orientation: orientation))
}

/// Equal within floating-point rounding of sums of the token values.
func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

func close(_ a: LayoutRect, _ b: LayoutRect) -> Bool {
    close(a.x, b.x) && close(a.y, b.y) && close(a.width, b.width) && close(a.height, b.height)
}

/// The keys of the layout, split into its four rows by their top edge.
func rows(_ layout: KeyboardLayout) -> [[Key]] {
    var rows: [[Key]] = []
    for key in layout.keys {
        if let last = rows.last?.last, close(last.frame.minY, key.frame.minY) {
            rows[rows.count - 1].append(key)
        } else {
            rows.append([key])
        }
    }
    return rows
}

func letters(_ row: [Key]) -> String {
    String(
        String.UnicodeScalarView(
            row.compactMap {
                if case .letter(let scalar) = $0.kind { return scalar }
                return nil
            }))
}

@Suite("Keyboard layout: frames against the token values")
struct KeyboardLayoutFrameTests {
    @Test("The English rows hold QWERTY, with shift, delete and the bottom row the export assumes")
    func keyOrder() throws {
        for (deviceClass, orientation) in allClassesAndOrientations {
            let layout = try englishLayout(deviceClass, orientation)
            let rows = rows(layout)
            try #require(rows.count == 4, "\(deviceClass) \(orientation)")
            #expect(letters(rows[0]) == "qwertyuiop")
            #expect(letters(rows[1]) == "asdfghjkl")
            #expect(rows[2].map(\.kind) == [.shift] + "zxcvbnm".unicodeScalars.map { .letter($0) } + [.delete])
            let utilities: [KeyKind] = deviceClass.hasHomeIndicator ? [.emoji] : [.globe, .dictation]
            #expect(rows[3].map(\.kind) == [.modeSwitch] + utilities + [.space, .returnKey])
        }
    }

    @Test("Every key's size is its token's value", arguments: DeviceClass.allCases)
    func keySizes(_ deviceClass: DeviceClass) throws {
        for orientation in Orientation.allCases {
            let layout = try englishLayout(deviceClass, orientation)
            let metrics = Metrics.of(deviceClass, orientation)
            for key in layout.keys {
                let width: Double
                switch key.kind {
                case .letter: width = metrics.keyLetterWidth.value
                case .shift: width = metrics.keyShiftWidth.value
                case .delete: width = metrics.keyDeleteWidth.value
                case .modeSwitch: width = metrics.keyModeSwitchWidth.value
                case .emoji, .globe, .dictation: width = metrics.keyUtilityWidth.value
                case .space: width = metrics.keySpaceWidth.value
                case .returnKey: width = metrics.keyReturnWidth.value
                }
                #expect(key.frame.width == width, "\(deviceClass) \(orientation) \(key.kind)")
                #expect(key.frame.height == metrics.keyLetterHeight.value, "\(deviceClass) \(orientation) \(key.kind)")
            }
        }
    }

    @Test("Rows sit at the top inset and the vertical gap, and the bottom inset closes the key area")
    func rowPositions() throws {
        for (deviceClass, orientation) in allClassesAndOrientations {
            let layout = try englishLayout(deviceClass, orientation)
            let metrics = Metrics.of(deviceClass, orientation)
            let rows = rows(layout)
            let firstTop = metrics.suggestionBarHeight.value + metrics.keyboardInsetTop.value
            let pitch = metrics.keyLetterHeight.value + metrics.keyGapVertical.value
            for (index, row) in rows.enumerated() {
                #expect(close(row[0].frame.minY, firstTop + Double(index) * pitch), "\(deviceClass) \(orientation)")
            }
            let lastBottom = try #require(rows.last?.first).frame.maxY
            #expect(close(lastBottom + metrics.keyboardInsetBottom.value, layout.keyArea.maxY))
            #expect(close(layout.keyArea.maxY, layout.size.height), "\(deviceClass) \(orientation)")
        }
    }

    @Test("Keys in a row are one horizontal gap apart, and rows fit the key area as the tokens describe")
    func rowEdges() throws {
        for (deviceClass, orientation) in allClassesAndOrientations {
            let layout = try englishLayout(deviceClass, orientation)
            let metrics = Metrics.of(deviceClass, orientation)
            let gap = metrics.keyGapHorizontal.value
            let side = metrics.keyboardInsetSide.value
            let context = "\(deviceClass) \(orientation)"
            let rows = rows(layout)

            #expect(close(layout.keyArea.minX, side), "\(context)")
            #expect(close(layout.keyArea.maxX, layout.size.width - side), "\(context)")

            for row in rows {
                for (left, right) in zip(row, row.dropFirst()) where left.kind != .shift && right.kind != .delete {
                    #expect(close(right.frame.minX - left.frame.maxX, gap), "\(context) \(left.kind) \(right.kind)")
                }
            }
            // Row 1 and the bottom row run edge to edge across the key area.
            for row in [rows[0], rows[3]] {
                #expect(close(try #require(row.first).frame.minX, layout.keyArea.minX), "\(context)")
                #expect(close(try #require(row.last).frame.maxX, layout.keyArea.maxX), "\(context)")
            }
            // Row 2 is centred in the key area.
            let leftMargin = rows[1][0].frame.minX - layout.keyArea.minX
            let rightMargin = layout.keyArea.maxX - rows[1][rows[1].count - 1].frame.maxX
            #expect(close(leftMargin, rightMargin), "\(context)")
            // Row 3: shift and delete at the edges, the letters centred between them.
            let row3 = rows[2]
            let shift = row3[0]
            let delete = row3[row3.count - 1]
            #expect(close(shift.frame.minX, layout.keyArea.minX) && close(delete.frame.maxX, layout.keyArea.maxX))
            let afterShift = row3[1].frame.minX - shift.frame.maxX
            let beforeDelete = delete.frame.minX - row3[row3.count - 2].frame.maxX
            #expect(close(afterShift, beforeDelete), "\(context)")
            #expect(afterShift >= gap, "\(context): the letters crowd shift and delete")
        }
    }

    // Spot checks with the numbers written out from DesignTokens/speakboard-tokens.json, so a mistake in the
    // generator or in the table lookup that keeps the layout self-consistent still fails.
    @Test("Reference class iphone-393x852 in portrait, numbers from the export")
    func reference393Portrait() throws {
        let layout = try englishLayout(.iphone393x852, .portrait)
        // key area 387 x 216 at side inset 3, suggestion bar 44, top inset 9, keys 33.3 x 42, gaps 6 and 12.
        #expect(layout.size == LayoutSize(width: 393, height: 260))
        #expect(layout.suggestionStrip == LayoutRect(x: 0, y: 0, width: 393, height: 44))
        #expect(layout.keyArea == LayoutRect(x: 3, y: 44, width: 387, height: 216))
        let q = try #require(layout.keys.first)
        #expect(q.kind == .letter("q") && close(q.frame, LayoutRect(x: 3, y: 53, width: 33.3, height: 42)))
        let p = layout.keys[9]
        #expect(p.kind == .letter("p") && close(p.frame.minX, 3 + 9 * (33.3 + 6)) && close(p.frame.maxX, 390))
        let a = layout.keys[10]
        #expect(a.kind == .letter("a") && close(a.frame.minX, 3 + (387 - (9 * 33.3 + 8 * 6)) / 2))
        #expect(close(a.frame.minY, 53 + 42 + 12))
        let shift = layout.keys[19]
        #expect(shift.kind == .shift && shift.frame.width == 44.3 && close(shift.frame.minX, 3))
        let space = try #require(layout.keys.first { $0.kind == .space })
        // 123 (44.3), emoji (44.3), then space (187.2), each 6 apart; bottom row top 53 + 3 * 54.
        #expect(close(space.frame.minX, 3 + 44.3 + 6 + 44.3 + 6) && space.frame.width == 187.2)
        #expect(close(space.frame.minY, 215))
        let returnKey = try #require(layout.keys.last)
        #expect(returnKey.kind == .returnKey && returnKey.frame.width == 93.2 && close(returnKey.frame.maxX, 390))
    }

    @Test("Reference class iphone-393x852 in landscape, numbers from the export")
    func reference393Landscape() throws {
        let layout = try englishLayout(.iphone393x852, .landscape)
        // side inset 60 (a placeholder), key area 732 x 162, bar 38, top inset 8, keys 67.8 x 32, gaps 6 and 6.
        #expect(layout.size == LayoutSize(width: 852, height: 200))
        #expect(layout.suggestionStrip == LayoutRect(x: 0, y: 0, width: 852, height: 38))
        #expect(layout.keyArea == LayoutRect(x: 60, y: 38, width: 732, height: 162))
        #expect(close(layout.keys[0].frame, LayoutRect(x: 60, y: 46, width: 67.8, height: 32)))
        #expect(layout.metrics.keyboardInsetSide.isPlaceholder)
        #expect(layout.metrics.keyboardInsetSide.tolerance == 30)
    }

    @Test("Home-button class iphone-375x667 in portrait: globe and dictation, numbers from the export")
    func homeButton375Portrait() throws {
        let layout = try englishLayout(.iphone375x667, .portrait)
        let bottom = Array(layout.keys.suffix(5))
        #expect(bottom.map(\.kind) == [.modeSwitch, .globe, .dictation, .space, .returnKey])
        // 123, globe and dictation 41.9 each, space 131.1, return 88.2, gaps 6, from the side inset 3.
        #expect(bottom.map(\.frame.width) == [41.9, 41.9, 41.9, 131.1, 88.2])
        #expect(close(bottom[3].frame.minX, 3 + 3 * (41.9 + 6)))
        #expect(close(bottom[4].frame.maxX, 372))
    }
}

@Suite("Keyboard layout: the suggestion bar's strip")
struct SuggestionStripTests {
    @Test("The strip is present, empty, across the top, with its height from the tokens")
    func strip() throws {
        for (deviceClass, orientation) in allClassesAndOrientations {
            let layout = try englishLayout(deviceClass, orientation)
            let metrics = Metrics.of(deviceClass, orientation)
            let strip = layout.suggestionStrip
            let context = "\(deviceClass) \(orientation)"
            #expect(strip.height == metrics.suggestionBarHeight.value && strip.height > 0, "\(context)")
            #expect(strip.minX == 0 && strip.minY == 0 && strip.width == layout.size.width, "\(context)")
            #expect(layout.keyArea.minY == strip.maxY, "\(context)")
            #expect(close(strip.height + layout.keyArea.height, metrics.keyboardTotalHeight.value), "\(context)")
            #expect(layout.keys.allSatisfy { $0.frame.minY >= strip.maxY }, "\(context): a key overlaps the strip")
            #expect(layout.key(at: strip.center) == nil, "\(context): a touch on the strip hits a key")
        }
    }
}

@Suite("Keyboard layout: locale")
struct LayoutLocaleTests {
    @Test("English has a layout for every device class and orientation")
    func english() {
        for (deviceClass, orientation) in allClassesAndOrientations {
            let layout = KeyboardLayout(locale: .english, deviceClass: deviceClass, orientation: orientation)
            #expect(layout?.locale == .english)
        }
    }

    @Test("The data holds one letters layout per locale, and English is the only locale with data")
    func data() throws {
        #expect(Array(LetterLayouts.byLocale.keys) == [.english])
        let english = try #require(LetterLayouts.byLocale[.english])
        #expect(english.rows.map(\.count) == [10, 9, 7])
    }

    @Test(
        "A locale with a region or another spelling gets its language's layout",
        arguments: [
            "en-US", "en-GB", "en_GB", "EN", "en-Latn-US", "en@calendar=gregorian", "en_US@rg=gbzzzz",
        ])
    func languageFallback(_ identifier: String) throws {
        let layout = try #require(
            KeyboardLayout(
                locale: LayoutLocale(identifier: identifier), deviceClass: .iphone393x852, orientation: .portrait))
        #expect(layout.locale == .english)
        #expect(layout.keys == (try englishLayout(.iphone393x852, .portrait)).keys)
    }

    @Test(
        "A locale whose language has no layout data gives no layout",
        arguments: ["fr", "de-DE", "e", "", "-en", "@en", "fr@calendar=gregorian"])
    func otherLocale(_ identifier: String) {
        let layout = KeyboardLayout(
            locale: LayoutLocale(identifier: identifier), deviceClass: .iphone393x852, orientation: .portrait)
        #expect(layout == nil)
    }
}
