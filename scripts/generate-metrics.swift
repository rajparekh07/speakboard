// Generates the core's metrics tables and drawing tokens from the pinned design
// token export.
//
// Usage (inside the Swift image, through scripts/metrics.sh, which checks the
// export's SHA-256 against the pin first):
//   swift scripts/generate-metrics.swift <speakboard-tokens.json> <tokens.pin> metrics|drawing
// It writes Swift source to standard output: `metrics` writes
// GeneratedMetrics.swift, `drawing` writes GeneratedDrawingTokens.swift. Both
// read and check the whole export the same way, whichever they write.
//
// What `metrics` emits (DesignTokens/export-format.md, "What a generator emits",
// "Metrics tables"):
// - `TokenExport`: the pinned export's version, SHA-256 and publish label.
// - `DeviceClass`, one case per device class in the export, in its order.
// - `Metrics`, one row per device class and orientation, one column per token
//   whose axes are ["deviceClass", "orientation"]. Each cell carries the value,
//   the tolerance, the kind and a placeholder flag (confidence "none").
// - An alias column (`aliasOf`) is a computed property that reads the target
//   column's value, never a copy of the number.
//
// What `drawing` emits (KEY-62): what the keyboard needs to draw keys that the
// metrics tables do not hold, as plain values in the core (no UIKit types; the
// Apple side maps them, see Sources/SpeakboardCore/Layout/DrawingCells.swift):
// - `Palette`, one row per appearance (light, dark), one column per token whose
//   axes are ["appearance"]: every colour token. Each cell carries the colour
//   (`#RRGGBBAA` as `RGBAColor(0xRRGGBBAA)`), the tolerance (CIEDE2000), the
//   kind and a placeholder flag.
// - `Typography`, one member per token with no axes whose unit is
//   `uifont-weight` or `font-family`: the label weights and the typeface.
// - An alias is a computed property that reads its target, as in `Metrics`.
// Sizes, radii and the shadow offset vary by device class, so they are metrics
// columns. Tokens with no axes in other units (timings in ms, counts, glyph
// ids, the mic's invented sizes) are emitted by neither output: nothing that
// draws the letters keyboard reads them yet.
//
// It copies every value exactly as the export gives it: no rounding, no
// fixing, nothing invented. It fails, writing nothing, on anything it does not
// know: a schema major version other than 1, an axis shape, unit, tolerance
// unit or provenance kind it does not know, a non-finite number, a colour that
// is not `#RRGGBBAA` in uppercase hex, a weight that is not a UIFont.Weight
// name, a typeface other than "system", a colour token not on the appearance
// axis (or an appearance token that is not a colour), an alias whose target
// differs, or device classes out of the axis order.
//
// These are not all the checks the format note asks of a generator that does
// not run the validator. Of its extra checks it makes: check 1 (through
// scripts/metrics.sh); the name-collision part of check 2, for the columns and
// members it emits; the finite-number half of check 3; check 4 (alias axes,
// units and values), for the tokens it emits, which covers all 12 of the
// export's aliases (2 device class aliases, 10 colour aliases); and check 5. It
// skips: the rest of check 2 (prefix ids, reserved and keyword names); the
// integer-literal half of check 3 (neither output holds a `count`); check 6
// (derived geometry); check 7 (method `derived` with another source); check 8
// (no measured values with --no-measured); and check 9 (the summary recount).
// The validator, validate-tokens.py, runs when an export is pinned
// (CONTRIBUTING.md, "Design tokens", step 2), not in `make check`, because the
// Swift image has no Python. The hash pin keeps the export to the one that was
// validated.

import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("generate-metrics: FAIL: \(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 4, ["metrics", "drawing"].contains(arguments[3]) else {
    fail("usage: generate-metrics.swift <speakboard-tokens.json> <tokens.pin> metrics|drawing")
}
let output = arguments[3]

// MARK: - The pin

guard let pinText = try? String(contentsOfFile: arguments[2], encoding: .utf8) else {
    fail("cannot read the pin file \(arguments[2])")
}

var pin: [String: String] = [:]
for line in pinText.split(separator: "\n") where !line.hasPrefix("#") {
    guard let colon = line.firstIndex(of: ":") else { continue }
    let key = line[..<colon].trimmingCharacters(in: .whitespaces)
    let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    pin[key] = value
}

func pinned(_ key: String) -> String {
    guard let value = pin[key], !value.isEmpty else { fail("the pin file has no `\(key)`") }
    return value
}

// MARK: - The export

guard let data = FileManager.default.contents(atPath: arguments[1]),
    let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
else {
    fail("cannot read the export \(arguments[1]) as a JSON object")
}

func string(_ object: [String: Any], _ key: String, _ context: String) -> String {
    guard let value = object[key] as? String else { fail("\(context): `\(key)` is not a string") }
    return value
}

func dictionary(_ object: [String: Any], _ key: String, _ context: String) -> [String: Any] {
    guard let value = object[key] as? [String: Any] else { fail("\(context): `\(key)` is not an object") }
    return value
}

func number(_ value: Any?, _ context: String) -> Double {
    // JSON true and false also arrive as NSNumber; their type is a Boolean
    // subclass. (`is Bool` cannot tell: it is true for every 0 and 1.)
    guard let value, let number = value as? NSNumber, !"\(type(of: number))".contains("Boolean") else {
        fail("\(context): not a number")
    }
    let double = number.doubleValue
    guard double.isFinite else { fail("\(context): not a finite number") }
    return double
}

let schemaVersion = string(root, "schemaVersion", "export")
guard schemaVersion.hasPrefix("1.") else {
    fail("schema version \(schemaVersion): this generator reads 1.x.y only")
}

let tokenSetVersion = string(root, "tokenSetVersion", "export")
guard tokenSetVersion == pinned("token-set-version") else {
    fail("the export is token set \(tokenSetVersion), the pin says \(pinned("token-set-version"))")
}

let knownUnits: Set = ["pt", "ms", "ratio", "count", "srgb-hex8", "uifont-weight", "font-family", "glyph-id"]
let numericUnits: Set = ["pt", "ms", "ratio", "count"]
let units = dictionary(root, "units", "export")
for unit in units.keys where !knownUnits.contains(unit) {
    fail("unknown unit `\(unit)`")
}

let axes = dictionary(root, "axes", "export")
guard let classIDs = axes["deviceClass"] as? [String], !classIDs.isEmpty else {
    fail("axes.deviceClass is not a list of ids")
}
guard axes["orientation"] as? [String] == ["portrait", "landscape"] else {
    fail("axes.orientation is not [portrait, landscape]")
}
let orientations = ["portrait", "landscape"]

let iosVersions = dictionary(root, "ios", "export")
guard iosVersions.count == 1, let (iosKey, iosAny) = iosVersions.first, let ios = iosAny as? [String: Any] else {
    fail("the export has \(iosVersions.count) iOS versions; this generator reads exactly one")
}
guard let iosMajor = Int(iosKey) else { fail("iOS version key `\(iosKey)` is not a number") }

// MARK: Device classes

struct DeviceClassRow {
    let id: String
    let width: Double
    let height: Double
    let homeIndicator: Bool
    let models: [String]
}

guard let deviceClassesAny = ios["deviceClasses"] as? [String: Any] else {
    fail("ios.\(iosKey).deviceClasses is not an object")
}
guard Set(deviceClassesAny.keys) == Set(classIDs) else {
    fail("ios.\(iosKey).deviceClasses does not hold exactly the classes in axes.deviceClass")
}
// JSON objects have no order once parsed, so the order check reads the text:
// each class id must first appear, as a key, in axis order.
let exportText = String(decoding: data, as: UTF8.self)
let keyPositions = classIDs.compactMap { exportText.range(of: "\"\($0)\": {")?.lowerBound }
guard keyPositions.count == classIDs.count, keyPositions == keyPositions.sorted() else {
    fail("device classes are not in the order of axes.deviceClass")
}

let deviceClasses: [DeviceClassRow] = classIDs.map { id in
    let context = "device class \(id)"
    guard let entry = deviceClassesAny[id] as? [String: Any] else { fail("\(context) is not an object") }
    let screen = dictionary(entry, "screen", context)
    guard screen["unit"] as? String == "pt", screen["orientation"] as? String == "portrait" else {
        fail("\(context): the screen is not in portrait points")
    }
    guard let homeIndicator = entry["homeIndicator"] as? Bool else { fail("\(context): homeIndicator") }
    guard let models = entry["models"] as? [String] else { fail("\(context): models") }
    return DeviceClassRow(
        id: id, width: number(screen["width"], "\(context) width"),
        height: number(screen["height"], "\(context) height"), homeIndicator: homeIndicator, models: models)
}

// MARK: Tokens

struct Cell {
    let value: Double
    let tolerance: Double?
    let kind: String
    let isPlaceholder: Bool
}

struct Column {
    let id: String
    let description: String
    let unit: String
    let aliasOf: String?
    var cells: [String: Cell]  // keyed "<class id> <orientation>"
}

guard let tokens = ios["tokens"] as? [String: Any] else { fail("ios.\(iosKey).tokens is not an object") }

let knownAxes: [[String]] = [[], ["appearance"], ["deviceClass", "orientation"]]
var columns: [Column] = []

for id in tokens.keys.sorted() {
    guard let token = tokens[id] as? [String: Any] else { fail("token \(id) is not an object") }
    let unit = string(token, "unit", "token \(id)")
    guard knownUnits.contains(unit) else { fail("token \(id): unknown unit `\(unit)`") }
    guard let tokenAxes = token["axes"] as? [String], knownAxes.contains(tokenAxes) else {
        fail("token \(id): unknown axis shape \(token["axes"] ?? "none")")
    }
    guard tokenAxes == ["deviceClass", "orientation"] else { continue }
    guard numericUnits.contains(unit) else { fail("token \(id): a metrics column needs a number, not `\(unit)`") }

    let values = dictionary(token, "values", "token \(id)")
    var column = Column(
        id: id, description: string(token, "description", "token \(id)"), unit: unit, aliasOf: nil, cells: [:])
    var aliases: Set<String> = []

    for classID in classIDs {
        let byOrientation = dictionary(values, classID, "token \(id)")
        for orientation in orientations {
            let context = "token \(id), \(classID), \(orientation)"
            let leaf = dictionary(byOrientation, orientation, context)
            guard leaf["unit"] as? String == unit else { fail("\(context): the leaf unit differs from the token's") }
            let value = number(leaf["value"], "\(context) value")
            let provenance = dictionary(leaf, "provenance", context)

            func tolerance() -> Double? {
                guard let tolerance = provenance["tolerance"] as? [String: Any] else { return nil }
                guard tolerance["unit"] as? String == unit else {
                    fail("\(context): tolerance unit \(tolerance["unit"] ?? "none") is not the value's unit \(unit)")
                }
                return number(tolerance["plusMinus"], "\(context) tolerance")
            }

            let cell: Cell
            switch string(provenance, "kind", context) {
            case "estimated":
                guard let plusMinus = tolerance() else { fail("\(context): an estimated cell has no tolerance") }
                let confidence = string(provenance, "confidence", context)
                guard ["medium", "low", "none"].contains(confidence) else {
                    fail("\(context): unknown confidence `\(confidence)`")
                }
                cell = Cell(value: value, tolerance: plusMinus, kind: "estimated", isPlaceholder: confidence == "none")
            case "measured":
                // A measured cell that states no tolerance counts as 0, as in the derived rule.
                cell = Cell(value: value, tolerance: tolerance() ?? 0, kind: "measured", isPlaceholder: false)
            case "invented":
                if let target = provenance["aliasOf"] as? String { aliases.insert(target) }
                cell = Cell(value: value, tolerance: nil, kind: "invented", isPlaceholder: false)
            case let kind:
                fail("\(context): unknown provenance kind `\(kind)`")
            }
            column.cells["\(classID) \(orientation)"] = cell
        }
    }

    guard aliases.count <= 1 else { fail("token \(id) is an alias of more than one token") }
    column = Column(
        id: column.id, description: column.description, unit: column.unit, aliasOf: aliases.first,
        cells: column.cells)
    columns.append(column)
}

// An alias must have its target's axes and unit, and equal it in every cell.
for column in columns {
    guard let target = column.aliasOf else { continue }
    guard let targetColumn = columns.first(where: { $0.id == target }), targetColumn.aliasOf == nil else {
        fail("token \(column.id) is an alias of \(target), which is not a plain device class token")
    }
    guard targetColumn.unit == column.unit else { fail("alias \(column.id) and \(target) differ in unit") }
    for (key, cell) in column.cells where cell.kind != "invented" || cell.value != targetColumn.cells[key]?.value {
        fail("alias \(column.id) differs from \(target) at \(key), or is not invented there")
    }
}

// MARK: Drawing tokens

let appearances = ["light", "dark"]
guard axes["appearance"] as? [String] == appearances else {
    fail("axes.appearance is not [light, dark]")
}

// The units the drawing output reads, each with the one tolerance unit it accepts.
let drawingToleranceUnits = ["srgb-hex8": "deltaE2000", "uifont-weight": "weightSteps", "font-family": "enum"]
// UIFont.Weight's names, as the export's `uifont-weight` unit lists them.
let fontWeights = ["ultraLight", "thin", "light", "regular", "medium", "semibold", "bold", "heavy", "black"]

struct DrawingCell {
    let value: String
    let tolerance: Double?
    let kind: String
    let isPlaceholder: Bool
}

struct DrawingToken {
    let id: String
    let description: String
    let unit: String
    let aliasOf: String?
    let cells: [String: DrawingCell]  // keyed by appearance, or "" for a token with no axes
}

func drawingCell(_ leaf: [String: Any], unit: String, context: String) -> (cell: DrawingCell, aliasOf: String?) {
    guard leaf["unit"] as? String == unit else { fail("\(context): the leaf unit differs from the token's") }
    guard let value = leaf["value"] as? String else { fail("\(context): the value is not a string") }
    switch unit {
    case "srgb-hex8":
        guard value.range(of: "^#[0-9A-F]{8}$", options: .regularExpression) != nil else {
            fail("\(context): colour \(value) is not #RRGGBBAA in uppercase hex")
        }
    case "uifont-weight":
        guard fontWeights.contains(value) else { fail("\(context): \(value) is not a UIFont.Weight name") }
    default:
        guard value == "system" else { fail("\(context): typeface \(value) is not \"system\"") }
    }
    let provenance = dictionary(leaf, "provenance", context)

    func tolerance() -> Double? {
        guard let tolerance = provenance["tolerance"] as? [String: Any] else { return nil }
        guard let want = drawingToleranceUnits[unit], tolerance["unit"] as? String == want else {
            fail("\(context): tolerance unit \(tolerance["unit"] ?? "none") is not the one \(unit) takes")
        }
        return number(tolerance["plusMinus"], "\(context) tolerance")
    }

    switch string(provenance, "kind", context) {
    case "estimated":
        guard let plusMinus = tolerance() else { fail("\(context): an estimated value has no tolerance") }
        let confidence = string(provenance, "confidence", context)
        guard ["medium", "low", "none"].contains(confidence) else {
            fail("\(context): unknown confidence `\(confidence)`")
        }
        return (
            DrawingCell(value: value, tolerance: plusMinus, kind: "estimated", isPlaceholder: confidence == "none"), nil
        )
    case "measured":
        // A measured value that states no tolerance counts as 0, as in the metrics tables.
        return (DrawingCell(value: value, tolerance: tolerance() ?? 0, kind: "measured", isPlaceholder: false), nil)
    case "invented":
        return (
            DrawingCell(value: value, tolerance: nil, kind: "invented", isPlaceholder: false),
            provenance["aliasOf"] as? String
        )
    case let kind:
        fail("\(context): unknown provenance kind `\(kind)`")
    }
}

var colorTokens: [DrawingToken] = []
var typographyTokens: [DrawingToken] = []

for id in tokens.keys.sorted() {
    guard let token = tokens[id] as? [String: Any] else { fail("token \(id) is not an object") }
    let unit = string(token, "unit", "token \(id)")
    guard let tokenAxes = token["axes"] as? [String] else { fail("token \(id): no axes") }
    let isColor = unit == "srgb-hex8"
    let isTypography = unit == "uifont-weight" || unit == "font-family"
    if tokenAxes == ["appearance"] {
        guard isColor else { fail("token \(id) varies by appearance but is not a colour (`\(unit)`)") }
    } else if isColor {
        fail("token \(id) is a colour that does not vary by appearance")
    } else if !(tokenAxes.isEmpty && isTypography) {
        // Device class tokens are metrics columns; other tokens with no axes are not drawing tokens.
        guard !isTypography else { fail("token \(id): a `\(unit)` token with axes \(tokenAxes)") }
        continue
    }

    let values = dictionary(token, "values", "token \(id)")
    var cells: [String: DrawingCell] = [:]
    var aliases: Set<String> = []
    if tokenAxes.isEmpty {
        let (cell, alias) = drawingCell(values, unit: unit, context: "token \(id)")
        cells[""] = cell
        if let alias { aliases.insert(alias) }
    } else {
        guard Set(values.keys) == Set(appearances) else { fail("token \(id) does not hold exactly light and dark") }
        for appearance in appearances {
            let context = "token \(id), \(appearance)"
            let (cell, alias) = drawingCell(dictionary(values, appearance, context), unit: unit, context: context)
            cells[appearance] = cell
            if let alias { aliases.insert(alias) }
        }
    }
    guard aliases.count <= 1 else { fail("token \(id) is an alias of more than one token") }
    let drawingToken = DrawingToken(
        id: id, description: string(token, "description", "token \(id)"), unit: unit, aliasOf: aliases.first,
        cells: cells)
    if isColor {
        colorTokens.append(drawingToken)
    } else {
        typographyTokens.append(drawingToken)
    }
}

// An alias must have its target's axes and unit, and equal it in every cell, as for the metrics columns.
for group in [colorTokens, typographyTokens] {
    for token in group {
        guard let target = token.aliasOf else { continue }
        guard let targetToken = group.first(where: { $0.id == target }), targetToken.aliasOf == nil else {
            fail("token \(token.id) is an alias of \(target), which is not a plain token of the same kind")
        }
        guard targetToken.unit == token.unit else { fail("alias \(token.id) and \(target) differ in unit") }
        guard Set(targetToken.cells.keys) == Set(token.cells.keys) else {
            fail("alias \(token.id) and \(target) differ in axes")
        }
        for (key, cell) in token.cells where cell.kind != "invented" || cell.value != targetToken.cells[key]?.value {
            fail(
                "alias \(token.id) differs from \(target) at \(key.isEmpty ? "its value" : key), or is not invented there"
            )
        }
    }
}

// MARK: - Swift names

func camelCase(_ id: String, separators: Set<Character>) -> String {
    var result = ""
    var upperNext = false
    for character in id {
        if separators.contains(character) {
            upperNext = true
        } else if upperNext {
            result += character.uppercased()
            upperNext = false
        } else {
            result.append(character)
        }
    }
    return result
}

func propertyName(_ tokenID: String) -> String { camelCase(tokenID, separators: ["."]) }
func caseName(_ classID: String) -> String { classID.replacingOccurrences(of: "-", with: "") }

for names in [columns.map(\.id), colorTokens.map(\.id), typographyTokens.map(\.id)].map({ $0.map(propertyName) }) {
    guard Set(names).count == names.count else { fail("two tokens map to one Swift name") }
}
for classID in classIDs where caseName(classID).range(of: "^[a-z][a-z0-9]*$", options: .regularExpression) == nil {
    fail("device class id \(classID) does not make a Swift case name")
}

func literal(_ value: Double) -> String { "\(value)" }

// A cell as one of MetricCell's constructors: .estimated(value, tolerance),
// .placeholder(value, tolerance) for an estimate with confidence "none",
// .measured(value, tolerance) and .invented(value).
func cellLiteral(_ cell: Cell) -> String {
    let tolerance = cell.tolerance.map(literal) ?? ""
    switch (cell.kind, cell.isPlaceholder) {
    case ("estimated", false): return ".estimated(\(literal(cell.value)), \(tolerance))"
    case ("estimated", true): return ".placeholder(\(literal(cell.value)), \(tolerance))"
    case ("measured", _): return ".measured(\(literal(cell.value)), \(tolerance))"
    default: return ".invented(\(literal(cell.value)))"
    }
}

// A drawing cell as one of ColorCell's, FontWeightCell's or TypefaceCell's
// constructors, as for the metrics cells. A colour #RRGGBBAA is written
// RGBAColor(0xRRGGBBAA); a weight or a typeface is its case.
func drawingValueLiteral(_ value: String, unit: String) -> String {
    unit == "srgb-hex8" ? "RGBAColor(0x\(value.dropFirst()))" : ".\(value)"
}

func drawingCellLiteral(_ cell: DrawingCell, unit: String) -> String {
    let value = drawingValueLiteral(cell.value, unit: unit)
    let tolerance = cell.tolerance.map(literal) ?? ""
    switch (cell.kind, cell.isPlaceholder) {
    case ("estimated", false): return ".estimated(\(value), \(tolerance))"
    case ("estimated", true): return ".placeholder(\(value), \(tolerance))"
    case ("measured", _): return ".measured(\(value), \(tolerance))"
    default: return ".invented(\(value))"
    }
}

func docLines(_ text: String, indent: String) -> [String] {
    let width = 116 - indent.count - 4
    var lines: [String] = []
    var line = ""
    for word in text.split(separator: " ") {
        if !line.isEmpty, line.count + 1 + word.count > width {
            lines.append(line)
            line = ""
        }
        line += line.isEmpty ? String(word) : " " + word
    }
    if !line.isEmpty { lines.append(line) }
    return lines.map { "\(indent)/// \($0)" }
}

// MARK: - Output

var out: [String] = []
func emit(_ line: String = "") { out.append(line) }

emit("// GENERATED FILE. Do not edit by hand: run `make metrics`. `make check` fails if this file differs")
emit("// from what scripts/generate-metrics.swift makes from the pinned export.")
emit("//")
emit("// Source: the design token export pinned in DesignTokens/tokens.pin.")
emit("//   Design system: \(pinned("design-system"))")
emit("//   Publish label: \(pinned("publish-label"))")
emit("//   Token set version: \(tokenSetVersion) (schema \(schemaVersion)), iOS \(iosMajor)")
emit("//   SHA-256 of speakboard-tokens.json: \(pinned("sha256"))")
emit("//")
emit("// Every value is copied from the export as it is: estimates and placeholders until the measured")
emit("// tokens ticket replaces them. Each cell keeps its tolerance, kind and placeholder flag.")
emit()

// MARK: Drawing tokens

func emitDrawingDoc(_ token: DrawingToken, indent: String) {
    var doc = "`\(token.id)` (\(token.unit)). \(token.description)"
    if let target = token.aliasOf { doc += " An alias of `\(target)`: it reads that token's value." }
    out += docLines(doc, indent: indent)
}

if output == "drawing" {
    emit("// The drawing tokens: every colour token (axes [\"appearance\"]) as a column of `Palette`, one row per")
    emit("// appearance, and every weight and typeface token (no axes) as a member of `Typography`. Sizes, radii and")
    emit("// the key shadow's offset vary by device class: they are columns of `Metrics` (GeneratedMetrics.swift).")
    emit()
    emit("/// The colours of one appearance: one cell per colour token in the export, each of which varies by")
    emit("/// appearance. Read a row with `Palette.of(_:)`.")
    emit("public struct Palette: Equatable, Sendable {")
    for (index, token) in colorTokens.enumerated() {
        if index > 0 { emit() }
        emitDrawingDoc(token, indent: "    ")
        if let target = token.aliasOf {
            emit("    public var \(propertyName(token.id)): ColorCell {")
            emit("        .invented(\(propertyName(target)).color)")
            emit("    }")
        } else {
            emit("    public let \(propertyName(token.id)): ColorCell")
        }
    }
    emit("}")
    emit()
    emit("extension Palette {")
    emit("    /// The palette for an appearance.")
    emit("    public static func of(_ appearance: Appearance) -> Palette {")
    emit("        switch appearance {")
    let storedColors = colorTokens.filter { $0.aliasOf == nil }
    for appearance in appearances {
        emit("        case .\(appearance):")
        emit("            return Palette(")
        for (index, token) in storedColors.enumerated() {
            guard let cell = token.cells[appearance] else { fail("missing cell") }
            let comma = index == storedColors.count - 1 ? "" : ","
            emit("                \(propertyName(token.id)): \(drawingCellLiteral(cell, unit: token.unit))\(comma)")
        }
        emit("            )")
    }
    emit("        }")
    emit("    }")
    emit("}")
    emit()
    emit("/// The weight and typeface tokens: those with no axes, one value for every device class, orientation and")
    emit("/// appearance. Each member is computed, so reading one allocates nothing and holds no global state.")
    emit("public enum Typography {")
    for (index, token) in typographyTokens.enumerated() {
        if index > 0 { emit() }
        emitDrawingDoc(token, indent: "    ")
        let type = token.unit == "uifont-weight" ? "FontWeightCell" : "TypefaceCell"
        let member = token.unit == "uifont-weight" ? "weight" : "typeface"
        guard let cell = token.cells[""] else { fail("missing cell") }
        if let target = token.aliasOf {
            emit(
                "    public static var \(propertyName(token.id)): \(type) { .invented(\(propertyName(target)).\(member)) }"
            )
        } else {
            emit(
                "    public static var \(propertyName(token.id)): \(type) { \(drawingCellLiteral(cell, unit: token.unit)) }"
            )
        }
    }
    emit("}")
    for line in out where line.count > 120 {
        fail("a generated line is longer than 120 characters: \(line)")
    }
    print(out.joined(separator: "\n"))
    exit(0)
}

// MARK: Metrics tables

emit("/// The pinned token export these tables were generated from.")
emit("public enum TokenExport {")
emit("    /// The export's token set version.")
emit("    public static let tokenSetVersion = \"\(tokenSetVersion)\"")
emit()
emit("    /// The SHA-256 of the pinned speakboard-tokens.json.")
emit("    public static let sha256 = \"\(pinned("sha256"))\"")
emit()
emit("    /// The publish label of the export in the design system.")
emit("    public static let publishLabel = \"\(pinned("publish-label"))\"")
emit()
emit("    /// The iOS major version the tokens describe.")
emit("    public static let iosMajorVersion = \(iosMajor)")
emit("}")
emit()
emit("/// An iPhone size class in the token export, named by its portrait screen size in points.")
emit("public enum DeviceClass: String, CaseIterable, Sendable {")
for (index, deviceClass) in deviceClasses.enumerated() {
    if index > 0 { emit() }
    let button = deviceClass.homeIndicator ? "Home indicator" : "Home button"
    out += docLines("\(deviceClass.models.joined(separator: ", ")). \(button).", indent: "    ")
    emit("    case \(caseName(deviceClass.id)) = \"\(deviceClass.id)\"")
}
emit("}")
emit()
func emitDeviceClassProperty(_ declaration: String, _ doc: String, _ valueOf: (DeviceClassRow) -> String) {
    emit("    /// \(doc)")
    emit("    public var \(declaration) {")
    emit("        switch self {")
    for deviceClass in deviceClasses {
        emit("        case .\(caseName(deviceClass.id)): return \(valueOf(deviceClass))")
    }
    emit("        }")
    emit("    }")
}

emit("extension DeviceClass {")
emitDeviceClassProperty("screenWidth: Double", "The screen width in portrait, in points.") { literal($0.width) }
emit()
emitDeviceClassProperty("screenHeight: Double", "The screen height in portrait, in points.") { literal($0.height) }
emit()
emitDeviceClassProperty(
    "hasHomeIndicator: Bool", "Whether the class has a home indicator (Face ID) rather than a home button."
) { "\($0.homeIndicator)" }
emit("}")
emit()
emit("/// The metrics for one device class and orientation: one cell per token in the export that varies by")
emit("/// device class and orientation. Read a row with `Metrics.of(_:_:)`.")
emit("public struct Metrics: Equatable, Sendable {")
for (index, column) in columns.enumerated() {
    if index > 0 { emit() }
    let name = propertyName(column.id)
    var doc = "`\(column.id)` (\(column.unit)). \(column.description)"
    if let target = column.aliasOf { doc += " An alias of `\(target)`: it reads that token's value." }
    out += docLines(doc, indent: "    ")
    if let target = column.aliasOf {
        emit("    public var \(name): MetricCell {")
        emit("        .invented(\(propertyName(target)).value)")
        emit("    }")
    } else {
        emit("    public let \(name): MetricCell")
    }
}
emit("}")
emit()
emit("extension Metrics {")
emit("    /// The metrics row for a device class and orientation.")
emit("    public static func of(_ deviceClass: DeviceClass, _ orientation: Orientation) -> Metrics {")
emit("        switch (deviceClass, orientation) {")
let stored = columns.filter { $0.aliasOf == nil }
for deviceClass in deviceClasses {
    for orientation in orientations {
        emit("        case (.\(caseName(deviceClass.id)), .\(orientation)):")
        emit("            return Metrics(")
        for (index, column) in stored.enumerated() {
            guard let cell = column.cells["\(deviceClass.id) \(orientation)"] else { fail("missing cell") }
            let comma = index == stored.count - 1 ? "" : ","
            emit("                \(propertyName(column.id)): \(cellLiteral(cell))\(comma)")
        }
        emit("            )")
    }
}
emit("        }")
emit("    }")
emit("}")

for line in out where line.count > 120 {
    fail("a generated line is longer than 120 characters: \(line)")
}
print(out.joined(separator: "\n"))
