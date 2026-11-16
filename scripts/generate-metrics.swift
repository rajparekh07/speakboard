// Generates the core's metrics tables from the pinned design token export.
//
// Usage (inside the Swift image, through scripts/metrics.sh, which checks the
// export's SHA-256 against the pin first):
//   swift scripts/generate-metrics.swift <speakboard-tokens.json> <tokens.pin>
// It writes Swift source to standard output.
//
// What it emits (DesignTokens/export-format.md, "What a generator emits",
// "Metrics tables"):
// - `DeviceClass`, one case per device class in the export, in its order.
// - `Metrics`, one row per device class and orientation, one column per token
//   whose axes are ["deviceClass", "orientation"]. Each cell carries the value,
//   the tolerance, the kind and a placeholder flag (confidence "none").
// - An alias column (`aliasOf`) is a computed property that reads the target
//   column's value, never a copy of the number.
//
// It copies every value exactly as the export gives it: no rounding, no
// fixing, nothing invented. It fails, writing nothing, on anything it does not
// know: a schema major version other than 1, an axis shape, unit, tolerance
// unit or provenance kind it does not know, a non-finite number, an alias
// whose target differs, or device classes out of the axis order.
//
// These are not all the checks the format note asks of a generator that does
// not run the validator. Of its extra checks it makes: check 1 (through
// scripts/metrics.sh); the name-collision part of check 2, for the columns it
// emits; the finite-number half of check 3; check 4 (alias axes, units and
// values), for the columns it emits, which covers 2 of the export's 12 aliases;
// and check 5. It skips: the rest of check 2 (prefix ids, reserved and keyword
// names); the integer-literal half of check 3 (a metrics column holds no
// `count`); check 4 for the tokens it does not emit (the appearance-axis
// aliases); check 6 (derived geometry); check 7 (method `derived` with another
// source); check 8 (no measured values with --no-measured); and check 9 (the
// summary recount). The validator, validate-tokens.py, runs when an export is
// pinned (CONTRIBUTING.md, "Design tokens", step 2), not in `make check`,
// because the Swift image has no Python. The hash pin keeps the export to the
// one that was validated.

import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("generate-metrics: FAIL: \(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fail("usage: generate-metrics.swift <speakboard-tokens.json> <tokens.pin>")
}

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

let names = columns.map { propertyName($0.id) }
guard Set(names).count == names.count else { fail("two tokens map to one Swift name") }
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
