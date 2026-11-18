import AllocationCounter
import SpeakboardCore
import Testing

/// Every key in the English letters layout gets its look from the tokens, in both appearances.
@Suite("Key styles")
struct KeyStyleTests {
    /// Every kind of key the English letters layout holds, on any device class: letters and the bottom rows of
    /// iPhones with and without a home indicator.
    static func kindsInLayouts() throws -> [KeyKind] {
        var kinds: [KeyKind] = []
        for (deviceClass, orientation) in allClassesAndOrientations {
            for key in try englishLayout(deviceClass, orientation).keys where !kinds.contains(key.kind) {
                kinds.append(key.kind)
            }
        }
        return kinds
    }

    static func isFunctionKey(_ kind: KeyKind) -> Bool {
        switch kind {
        case .letter, .space: return false
        case .shift, .delete, .modeSwitch, .emoji, .globe, .dictation, .returnKey: return true
        }
    }

    @Test("The layouts hold every kind of key a style is given for")
    func layoutKinds() throws {
        let kinds = try Self.kindsInLayouts()
        #expect(kinds.count == 26 + 8, "26 letters, shift, delete, 123, emoji, globe, dictation, space, return")
        for kind in [KeyKind.shift, .delete, .modeSwitch, .emoji, .globe, .dictation, .space, .returnKey] {
            #expect(kinds.contains(kind), "\(kind)")
        }
    }

    @Test("Every key in every layout has a fill, a label style, a radius and a shadow from the tokens")
    func everyKey() throws {
        let kinds = try Self.kindsInLayouts()
        for appearance in Appearance.allCases {
            let palette = Palette.of(appearance)
            for (deviceClass, orientation) in allClassesAndOrientations {
                let metrics = Metrics.of(deviceClass, orientation)
                for face in [ReturnKeyFace.standard, .prominent] {
                    for kind in kinds {
                        let style = KeyStyle.of(kind, returnKey: face, appearance: appearance, metrics: metrics)
                        let context = "\(kind) \(appearance) \(deviceClass) \(orientation) \(face)"
                        let prominentReturn = kind == .returnKey && face == .prominent
                        #expect(style.cornerRadius == metrics.keyCornerRadius, "\(context)")
                        #expect(style.shadow.color == palette.keyShadowColor, "\(context)")
                        #expect(style.shadow.offsetY == metrics.keyShadowOffsetY, "\(context)")
                        #expect(style.label.size.value > 0, "\(context)")
                        #expect(style.fill.color.alpha > 0, "\(context)")
                        #expect(style.fill(pressed: false) == style.fill, "\(context)")
                        #expect(style.fill(pressed: true) == style.pressedFill, "\(context)")

                        switch kind {
                        case .letter:
                            #expect(style.fill == palette.keyLetterFill, "\(context)")
                            #expect(style.label.size == metrics.keyLetterLabelSize, "\(context)")
                            #expect(style.label.font?.weight == Typography.keyLetterLabelWeight, "\(context)")
                        case .space:
                            #expect(style.fill == palette.keyLetterFill, "\(context)")
                            #expect(style.label.size == metrics.keyFunctionLabelSize, "\(context)")
                            #expect(style.label.font?.weight == Typography.keyFunctionLabelWeight, "\(context)")
                        case .modeSwitch, .returnKey:
                            #expect(style.label.size == metrics.keyFunctionLabelSize, "\(context)")
                            #expect(style.label.font?.weight == Typography.keyFunctionLabelWeight, "\(context)")
                        case .shift, .delete, .emoji, .globe, .dictation:
                            #expect(style.label.size == metrics.keyFunctionGlyphSize, "\(context)")
                            #expect(style.label.font == nil, "\(context): a glyph has no font")
                        }
                        if let font = style.label.font {
                            #expect(font.typeface == Typography.typefaceFamily, "\(context)")
                        }

                        if prominentReturn {
                            #expect(style.fill == palette.keyReturnFillProminent, "\(context)")
                            #expect(style.label.color == palette.keyReturnLabelProminent, "\(context)")
                        } else {
                            #expect(style.label.color == palette.keyLabel, "\(context)")
                        }
                        if Self.isFunctionKey(kind) && !prominentReturn {
                            #expect(style.fill == palette.keyFunctionFill, "\(context)")
                        }

                        // A pressed face exists only where the export gives one: key.function.fillPressed. Letter
                        // keys, the space bar and the prominent return key have none in the export (a gap, not a
                        // value to invent).
                        if Self.isFunctionKey(kind) && !prominentReturn {
                            #expect(style.pressedFill == palette.keyFunctionFillPressed, "\(context)")
                        } else {
                            #expect(style.pressedFill == nil, "\(context)")
                        }
                    }
                }
            }
        }
    }

    @Test("Light and dark differ for every key's fill and label, as the export's colours do")
    func appearancesDiffer() throws {
        let metrics = Metrics.of(.iphone393x852, .portrait)
        for kind in try Self.kindsInLayouts() {
            for face in [ReturnKeyFace.standard, .prominent] {
                let light = KeyStyle.of(kind, returnKey: face, appearance: .light, metrics: metrics)
                let dark = KeyStyle.of(kind, returnKey: face, appearance: .dark, metrics: metrics)
                #expect(light.fill.color != dark.fill.color, "\(kind) \(face)")
                #expect(light.shadow.color.color != dark.shadow.color.color, "\(kind) \(face)")
                if kind == .returnKey && face == .prominent {
                    // key.return.labelProminent is white in both appearances in the export.
                    #expect(light.label.color.color == dark.label.color.color)
                } else {
                    #expect(light.label.color.color != dark.label.color.color, "\(kind) \(face)")
                }
                // Sizes, weights and radii do not vary by appearance in the export.
                #expect(light.label.size == dark.label.size && light.label.font == dark.label.font)
                #expect(light.cornerRadius == dark.cornerRadius)
            }
        }
    }

    @Test("The return key's face: prominent only for the kinds the export names")
    func returnKeyFaces() {
        for type in ReturnKeyType.allCases {
            switch type {
            case .default: #expect(ReturnKeyFace(type) == .standard)
            case .go, .search, .send, .done: #expect(ReturnKeyFace(type) == .prominent, "\(type)")
            default: #expect(ReturnKeyFace(type) == nil, "\(type): the export does not say")
            }
        }
    }

    @Test(
        "Asking for every key's style allocates nothing",
        .enabled(
            if: allocation_counter_available(),
            """
            Skipped: no heap allocation counter on this platform. Tests/AllocationCounter works on Linux with \
            glibc only.
            """))
    func allocatesNothing() throws {
        let kinds = try Self.kindsInLayouts()
        let metrics = allClassesAndOrientations.map { Metrics.of($0.0, $0.1) }
        let appearances = Appearance.allCases
        let faces = [ReturnKeyFace.standard, .prominent]
        var checksum = 0.0
        var count = 0

        // No warm-up. Once, in KEY-24, one local run of the whole suite counted 1 allocation here; the cause is
        // unknown. This test alone in a fresh process, with no warm-up, counts 0, and 8 runs of the whole suite with
        // no warm-up passed (KEY-24 review round 1, and the builder again). If it recurs, record the count.
        // `while` loops, not `for`-`in`: see HitTestAllocationTests.
        allocation_counter_start()
        var m = 0
        while m < metrics.count {
            var a = 0
            while a < appearances.count {
                var f = 0
                while f < faces.count {
                    var k = 0
                    while k < kinds.count {
                        let style = KeyStyle.of(
                            kinds[k], returnKey: faces[f], appearance: appearances[a], metrics: metrics[m])
                        checksum += style.fill.color.red + style.label.size.value + style.cornerRadius.value
                        if let pressed = style.fill(pressed: true) { checksum += pressed.color.alpha }
                        count += 1
                        k += 1
                    }
                    f += 1
                }
                a += 1
            }
            m += 1
        }
        let allocations = allocation_counter_stop()

        #expect(count == metrics.count * appearances.count * faces.count * kinds.count)
        #expect(HitTestAllocationTests.keep(checksum) > 0)
        #expect(allocations == 0, "\(count) style lookups made \(allocations) heap allocations")
    }
}
