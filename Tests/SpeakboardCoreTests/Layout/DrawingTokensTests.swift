import Foundation
import SpeakboardCore
import Testing

/// The generated drawing tokens carry exactly what the pinned export says, read here from the JSON itself rather
/// than through the generator.
@Suite("Drawing tokens against the pinned export")
struct DrawingTokensTests {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // Layout
        .deletingLastPathComponent()  // SpeakboardCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root

    static func export() throws -> [String: Any] {
        let url = repoRoot.appendingPathComponent("DesignTokens/speakboard-tokens.json")
        return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    static func tokens() throws -> [String: [String: Any]] {
        let ios = try #require((try export()["ios"] as? [String: Any])?["26"] as? [String: Any])
        return try #require(ios["tokens"] as? [String: [String: Any]])
    }

    /// "key.letter.fill" -> "keyLetterFill", the generator's naming.
    static func propertyName(_ id: String) -> String {
        let parts = id.split(separator: ".")
        return parts[0] + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    }

    /// "#ACB1BAFF" -> 0xACB1BAFF, read here by hand, not by the generator.
    static func rgba(_ hex: String) throws -> UInt32 {
        #expect(hex.count == 9 && hex.hasPrefix("#"), "\(hex) is not #RRGGBBAA")
        return try #require(UInt32(hex.dropFirst(), radix: 16))
    }

    /// The colour columns of a palette, by property name, through reflection, plus the aliases, which are
    /// computed and so read by name.
    static func cells(_ palette: Palette) -> [String: ColorCell] {
        var cells: [String: ColorCell] = [:]
        for child in Mirror(reflecting: palette).children {
            if let label = child.label, let cell = child.value as? ColorCell { cells[label] = cell }
        }
        let aliases: [String: KeyPath<Palette, ColorCell>] = [
            "dictationArmedGlyphColor": \.dictationArmedGlyphColor,
            "dictationArmedKeyFill": \.dictationArmedKeyFill,
            "dictationListeningGlyphColor": \.dictationListeningGlyphColor,
            "dictationListeningKeyFill": \.dictationListeningKeyFill,
            "dictationProcessingGlyphColor": \.dictationProcessingGlyphColor,
            "dictationProcessingKeyFill": \.dictationProcessingKeyFill,
            "dictationRecoveredGlyphColor": \.dictationRecoveredGlyphColor,
            "dictationRecoveredKeyFill": \.dictationRecoveredKeyFill,
            "dictationRestGlyphColor": \.dictationRestGlyphColor,
            "dictationRestKeyFill": \.dictationRestKeyFill,
        ]
        for (name, path) in aliases { cells[name] = palette[keyPath: path] }
        return cells
    }

    @Test("The generated file names the pinned export's version and SHA-256")
    func version() throws {
        let url = Self.repoRoot.appendingPathComponent("Sources/SpeakboardCore/Layout/GeneratedDrawingTokens.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        let export = try Self.export()
        let version = try #require(export["tokenSetVersion"] as? String)
        #expect(text.hasPrefix("// GENERATED FILE. Do not edit by hand"))
        #expect(text.contains("//   Token set version: \(version) "))
        #expect(text.contains("//   SHA-256 of speakboard-tokens.json: \(TokenExport.sha256)\n"))
        #expect(TokenExport.tokenSetVersion == version)
    }

    @Test("A sample of colours, read by hand from the export's text")
    func sample() throws {
        // The values as the pinned export writes them, read by eye from DesignTokens/speakboard-tokens.json; the
        // next test reads every one with JSONSerialization.
        let tokens = try Self.tokens()
        let light = Palette.of(.light)
        let dark = Palette.of(.dark)
        func value(_ id: String, _ appearance: String) throws -> String {
            let values = try #require(tokens[id]?["values"] as? [String: Any])
            return try #require((values[appearance] as? [String: Any])?["value"] as? String)
        }
        #expect(try value("key.letter.fill", "light") == "#FFFFFFFF")
        #expect(light.keyLetterFill.color.rgba == 0xFFFF_FFFF)
        #expect(try value("key.function.fill", "light") == "#ACB1BAFF")
        #expect(light.keyFunctionFill.color.rgba == 0xACB1_BAFF)
        #expect(light.keyFunctionFill.color.red == 172.0 / 255)
        #expect(light.keyFunctionFill.color.green == 177.0 / 255)
        #expect(light.keyFunctionFill.color.blue == 186.0 / 255)
        #expect(light.keyFunctionFill.color.alpha == 1)
        #expect(light.keyFunctionFill.tolerance == 12)
        #expect(light.keyFunctionFill.kind == .estimated && !light.keyFunctionFill.isPlaceholder)
        #expect(try value("key.function.fill", "dark") == "#474747FF")
        #expect(dark.keyFunctionFill.color.rgba == 0x4747_47FF)
        #expect(try value("keyboard.backdrop.fallback", "dark") == "#2C2C2EFF")
        #expect(dark.keyboardBackdropFallback.color.rgba == 0x2C2C_2EFF)
        #expect(try value("key.return.fillProminent", "dark") == "#0A84FFFF")
        #expect(dark.keyReturnFillProminent.color.rgba == 0x0A84_FFFF)
        // key.shadow.color's dark value has no basis in the export: a placeholder.
        #expect(dark.keyShadowColor.isPlaceholder && dark.keyShadowColor.tolerance == 30)
        #expect(!light.keyShadowColor.isPlaceholder)
        // An alias reads its target.
        #expect(dark.dictationRestKeyFill.color == dark.keyFunctionFill.color)
        #expect(dark.dictationRestKeyFill.kind == .invented && dark.dictationRestKeyFill.tolerance == nil)
    }

    @Test("Every colour token is a column, with the export's colour, tolerance, kind and placeholder flag")
    func everyColor() throws {
        let tokens = try Self.tokens()
        let colors = tokens.filter { ($0.value["axes"] as? [String]) == ["appearance"] }
        #expect(colors.count == 27)
        for appearance in Appearance.allCases {
            let cells = Self.cells(Palette.of(appearance))
            #expect(Set(cells.keys) == Set(colors.keys.map(Self.propertyName)), "the columns are the colour tokens")
            for (id, token) in colors {
                let values = try #require(token["values"] as? [String: Any])
                let leaf = try #require(values[appearance.rawValue] as? [String: Any])
                let provenance = try #require(leaf["provenance"] as? [String: Any])
                let cell = try #require(cells[Self.propertyName(id)])
                let hex = try #require(leaf["value"] as? String)
                let rgba = try Self.rgba(hex)
                #expect(cell.color.rgba == rgba, "\(id) \(appearance)")
                #expect(cell.color.red == Double(rgba >> 24) / 255, "\(id) \(appearance)")
                #expect(cell.color.alpha == Double(rgba & 0xFF) / 255, "\(id) \(appearance)")
                switch provenance["kind"] as? String {
                case "estimated":
                    let tolerance = try #require(provenance["tolerance"] as? [String: Any])
                    #expect(tolerance["unit"] as? String == "deltaE2000")
                    #expect(cell.tolerance == (tolerance["plusMinus"] as? NSNumber)?.doubleValue, "\(id)")
                    #expect(cell.kind == .estimated, "\(id)")
                    #expect(cell.isPlaceholder == (provenance["confidence"] as? String == "none"), "\(id)")
                case "invented":
                    #expect(cell.tolerance == nil && cell.kind == .invented && !cell.isPlaceholder, "\(id)")
                default:
                    Issue.record("\(id) \(appearance): a provenance kind this test does not expect")
                }
            }
        }
    }

    @Test("Light and dark differ exactly where the export's two values differ")
    func lightAndDark() throws {
        let colors = try Self.tokens().filter { ($0.value["axes"] as? [String]) == ["appearance"] }
        let light = Self.cells(Palette.of(.light))
        let dark = Self.cells(Palette.of(.dark))
        var differing = 0
        for (id, token) in colors {
            let values = try #require(token["values"] as? [String: [String: Any]])
            let exportDiffers = values["light"]?["value"] as? String != values["dark"]?["value"] as? String
            let name = Self.propertyName(id)
            #expect((light[name]?.color != dark[name]?.color) == exportDiffers, "\(id)")
            if exportDiffers { differing += 1 }
        }
        // In 0.2.2, the white labels on blue and red (key.return.labelProminent, its two aliases
        // dictation.listening.glyphColor and dictation.processing.glyphColor, and dictation.failed.glyphColor) are
        // the same in both; the other 23 colours differ.
        #expect(differing == 23)
    }

    @Test("The weights and the typeface are the export's")
    func typography() throws {
        let tokens = try Self.tokens()
        func leaf(_ id: String) throws -> (value: String, provenance: [String: Any]) {
            let values = try #require(tokens[id]?["values"] as? [String: Any])
            #expect(tokens[id]?["axes"] as? [String] == [])
            return (try #require(values["value"] as? String), try #require(values["provenance"] as? [String: Any]))
        }
        let typographyIDs = tokens.filter {
            ($0.value["unit"] as? String) == "uifont-weight" || ($0.value["unit"] as? String) == "font-family"
        }.keys.sorted()
        #expect(typographyIDs == ["key.function.labelWeight", "key.letter.labelWeight", "typeface.family"])
        for (id, cell) in [
            ("key.letter.labelWeight", Typography.keyLetterLabelWeight),
            ("key.function.labelWeight", Typography.keyFunctionLabelWeight),
        ] {
            let (value, provenance) = try leaf(id)
            #expect(cell.weight.rawValue == value, "\(id)")
            #expect(provenance["kind"] as? String == "estimated" && cell.kind == .estimated)
            let tolerance = try #require(provenance["tolerance"] as? [String: Any])
            #expect(tolerance["unit"] as? String == "weightSteps")
            #expect(cell.tolerance == (tolerance["plusMinus"] as? NSNumber)?.doubleValue)
            #expect(!cell.isPlaceholder)
        }
        let (family, provenance) = try leaf("typeface.family")
        #expect(Typography.typefaceFamily.typeface.rawValue == family)
        #expect(Typography.typefaceFamily.kind == .estimated && provenance["kind"] as? String == "estimated")
        #expect(Typography.typefaceFamily.tolerance == 0)
    }

    @Test("The export's weight names are FontWeight's cases, as its unit lists them")
    func weightNames() throws {
        let units = try #require(try Self.export()["units"] as? [String: String])
        let description = try #require(units["uifont-weight"])
        for weight in FontWeight.allCases {
            #expect(description.contains(" \(weight.rawValue),") || description.contains(" \(weight.rawValue)."))
        }
    }
}
