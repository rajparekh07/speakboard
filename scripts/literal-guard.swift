// The literal guard's reader (KEY-62): judges the compiler's dumps of the
// keyboard's view code. scripts/literal-guard.sh runs the compiler and calls
// this; its header says what the guard catches and what it does not.
//
// Usage: swift scripts/literal-guard.swift (<source> <parse dump> <ast dump>)...
//   <parse dump>  `swift-frontend -dump-parse -dump-ast-format json <source>`,
//                 which must have succeeded: every rule is judged on it
//   <ast dump>    `swift-frontend -dump-ast -dump-ast-format json <source>`,
//                 whatever its exit status: used only to find the line of a
//                 finding (see "Lines" below)
// It prints each finding, `<source>:<line>:<column>: <what>`, and exits 1 if
// there is any, or if a parse dump is not what it reads. It exits 0 and prints
// the number of files and literals it read otherwise.
//
// Lines. As observed with the pinned Swift 6.4.2, the parse dump locates
// declarations and statements but no expression, and the type-checked dump
// locates every expression that got a type, error types included. Without
// UIKit (Linux) the type checker cannot resolve UIKit's names and replaces
// them with error nodes, so the rules cannot be judged on its dump. So a
// finding is judged on the parse dump and placed with the type-checked one:
// its key (the node's kind and spelling, for example an integer literal `15`)
// and its place among the parse dump's nodes with that key, in the order the
// dump lists them, pick the type-checked node with that key at the same place
// in source order. This file reads JSON itself, because JSONSerialization
// drops the order of an object's keys. The parse dump lists nodes in source
// order in every case the self-test has; if it listed two nodes with one key
// out of order, their lines would be swapped (both are still judged, so a
// finding is never missed, but its line could be the other one's). If the two
// dumps hold a different number of nodes with the key (the type-checked dump
// has no node for some default arguments, or there is no type-checked dump),
// the finding is placed at the start of the nearest declaration or statement
// around it that the parse dump locates, and says so. A finding is never
// dropped for want of a line.

import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("literal guard: FAIL: \(message)\n".utf8))
    exit(1)
}

// MARK: - JSON, in order

/// A JSON value with an object's members in the order the text gives them.
indirect enum JSON {
    case object([(key: String, value: JSON)])
    case array([JSON])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    subscript(_ key: String) -> JSON? {
        guard case .object(let members) = self else { return nil }
        return members.first { $0.key == key }?.value
    }

    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var int: Int? {
        if case .number(let value) = self { return Int(value) }
        return nil
    }

    var isTrue: Bool {
        if case .bool(true) = self { return true }
        return false
    }
}

struct JSONReader {
    let bytes: [UInt8]
    var index = 0

    enum Failure: Error { case bad(Int) }

    init(_ data: Data) { bytes = [UInt8](data) }

    static func read(_ data: Data) -> JSON? {
        var reader = JSONReader(data)
        guard let value = try? reader.value() else { return nil }
        reader.skipSpace()
        return reader.index == reader.bytes.count ? value : nil
    }

    mutating func skipSpace() {
        while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
    }

    mutating func expect(_ byte: UInt8) throws {
        skipSpace()
        guard index < bytes.count, bytes[index] == byte else { throw Failure.bad(index) }
        index += 1
    }

    mutating func value() throws -> JSON {
        skipSpace()
        guard index < bytes.count else { throw Failure.bad(index) }
        switch bytes[index] {
        case UInt8(ascii: "{"):
            index += 1
            var members: [(key: String, value: JSON)] = []
            skipSpace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "}") {
                index += 1
                return .object(members)
            }
            while true {
                skipSpace()
                let key = try string()
                try expect(UInt8(ascii: ":"))
                members.append((key, try value()))
                skipSpace()
                guard index < bytes.count else { throw Failure.bad(index) }
                index += 1
                if bytes[index - 1] == UInt8(ascii: "}") { return .object(members) }
                guard bytes[index - 1] == UInt8(ascii: ",") else { throw Failure.bad(index) }
            }
        case UInt8(ascii: "["):
            index += 1
            var elements: [JSON] = []
            skipSpace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "]") {
                index += 1
                return .array(elements)
            }
            while true {
                elements.append(try value())
                skipSpace()
                guard index < bytes.count else { throw Failure.bad(index) }
                index += 1
                if bytes[index - 1] == UInt8(ascii: "]") { return .array(elements) }
                guard bytes[index - 1] == UInt8(ascii: ",") else { throw Failure.bad(index) }
            }
        case UInt8(ascii: "\""):
            return .string(try string())
        case UInt8(ascii: "t"):
            try word("true")
            return .bool(true)
        case UInt8(ascii: "f"):
            try word("false")
            return .bool(false)
        case UInt8(ascii: "n"):
            try word("null")
            return .null
        default:
            let start = index
            while index < bytes.count, "+-.0123456789eE".utf8.contains(bytes[index]) { index += 1 }
            guard index > start, let text = String(bytes: bytes[start..<index], encoding: .utf8),
                Double(text) != nil
            else { throw Failure.bad(start) }
            return .number(text)
        }
    }

    mutating func word(_ text: String) throws {
        for byte in text.utf8 {
            guard index < bytes.count, bytes[index] == byte else { throw Failure.bad(index) }
            index += 1
        }
    }

    mutating func hex4() throws -> UInt32 {
        guard index + 4 <= bytes.count, let text = String(bytes: bytes[index..<index + 4], encoding: .utf8),
            let value = UInt32(text, radix: 16)
        else { throw Failure.bad(index) }
        index += 4
        return value
    }

    mutating func string() throws -> String {
        guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw Failure.bad(index) }
        index += 1
        var out: [UInt8] = []
        while true {
            guard index < bytes.count else { throw Failure.bad(index) }
            let byte = bytes[index]
            index += 1
            switch byte {
            case UInt8(ascii: "\""):
                guard let text = String(bytes: out, encoding: .utf8) else { throw Failure.bad(index) }
                return text
            case UInt8(ascii: "\\"):
                guard index < bytes.count else { throw Failure.bad(index) }
                let escape = bytes[index]
                index += 1
                switch escape {
                case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): out.append(escape)
                case UInt8(ascii: "b"): out.append(0x08)
                case UInt8(ascii: "f"): out.append(0x0C)
                case UInt8(ascii: "n"): out.append(0x0A)
                case UInt8(ascii: "r"): out.append(0x0D)
                case UInt8(ascii: "t"): out.append(0x09)
                case UInt8(ascii: "u"):
                    var scalar = try hex4()
                    if (0xD800..<0xDC00).contains(scalar) {
                        try word("\\u")
                        let low = try hex4()
                        guard (0xDC00..<0xE000).contains(low) else { throw Failure.bad(index) }
                        scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00)
                    }
                    guard let unicode = Unicode.Scalar(scalar) else { throw Failure.bad(index) }
                    out += Array(String(Character(unicode)).utf8)
                default: throw Failure.bad(index)
                }
            default:
                guard byte >= 0x20 else { throw Failure.bad(index) }
                out.append(byte)
            }
        }
    }
}

// MARK: - The rules

// Literal kinds the guard knows. A node whose kind names a literal and is not
// listed here fails the guard: it cannot judge what it does not know.
let numberKinds: Set = ["integer_literal_expr", "float_literal_expr"]
let passingLiteralKinds: Set = [
    "string_literal_expr", "interpolated_string_literal_expr", "boolean_literal_expr", "nil_literal_expr",
    "magic_identifier_literal_expr", "regex_literal_expr",
]
let objectLiteralKind = "object_literal"

// Types whose initialisers and static members make colours.
let colorTypes: Set = ["UIColor", "CGColor", "CIColor", "NSColor", "Color"]
// Functions that make a colour from their arguments.
let colorFunctions: Set = [
    "CGColorCreate", "CGColorCreateSRGB", "CGColorCreateGenericRGB", "CGColorCreateGenericGray",
    "CGColorCreateGenericGrayGamma2_2", "CGColorCreateGenericCMYK", "CGColorCreateCopyWithAlpha",
    "CGColorCreateWithPattern", "withAlphaComponent",
]
// UIColor's named colours, which a leading-dot member (`.white`) can name where the type is a colour.
let namedColors: Set = [
    "black", "darkGray", "lightGray", "white", "gray", "red", "green", "blue", "cyan", "yellow", "magenta",
    "orange", "purple", "brown", "clear", "systemRed", "systemGreen", "systemBlue", "systemOrange", "systemYellow",
    "systemPink", "systemPurple", "systemTeal", "systemIndigo", "systemBrown", "systemMint", "systemCyan",
    "systemGray", "systemGray2", "systemGray3", "systemGray4", "systemGray5", "systemGray6", "label",
    "secondaryLabel", "tertiaryLabel", "quaternaryLabel", "link", "placeholderText", "separator",
    "opaqueSeparator", "systemBackground", "secondarySystemBackground", "tertiarySystemBackground",
    "systemGroupedBackground", "secondarySystemGroupedBackground", "tertiarySystemGroupedBackground",
    "systemFill", "secondarySystemFill", "tertiarySystemFill", "quaternarySystemFill", "lightText", "darkText",
    "tintColor", "groupTableViewBackground",
]
let hexColor = "^(#|0[xX])([0-9A-Fa-f]{3}|[0-9A-Fa-f]{4}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$"

/// The name a callee or a type expression ends with: `UIColor` for `UIColor`, `UIKit.UIColor` and
/// `UIColor.init`; nil for anything else.
func finalName(_ node: JSON) -> String? {
    switch node["_kind"]?.string {
    case "unresolved_decl_ref_expr":
        return node["name"]?.string.map { String($0.prefix { $0 != "(" }) }
    case "unresolved_dot_expr":
        guard let field = node["field"]?.string.map({ String($0.prefix { $0 != "(" }) }) else { return nil }
        if field == "init", let base = node["base"] { return finalName(base) }
        return field
    default:
        return nil
    }
}

/// What a finding is about, as both dumps can name it: the node's kind and spelling.
struct Key: Hashable {
    let kind: String
    let spelling: String
}

func key(of node: JSON) -> Key? {
    guard let kind = node["_kind"]?.string else { return nil }
    switch kind {
    case _ where numberKinds.contains(kind):
        return Key(kind: kind, spelling: (node["negative"]?.isTrue == true ? "-" : "") + (node["value"]?.string ?? ""))
    case "string_literal_expr":
        return Key(kind: kind, spelling: node["value"]?.string ?? "")
    case "unresolved_dot_expr":
        return Key(kind: kind, spelling: node["field"]?.string ?? "")
    case "unresolved_member_expr":
        return Key(kind: kind, spelling: node["name"]?.string ?? "")
    case objectLiteralKind:
        return Key(kind: kind, spelling: node["kind"]?.string ?? "")
    default:
        return nil
    }
}

struct Finding {
    let key: Key
    let ordinal: Int  // its place among the parse dump's nodes with this key, in source order
    let enclosingStart: Int?  // byte offset of the nearest located declaration or statement around it
    let message: String
}

/// Where a node sits, for the allowances: the operator before it in a sequence (`a += 1` is the sequence
/// `a`, `+=`, `1`), whether it ends the sequence, and the colour call it is an argument of, if any.
struct Place {
    var operatorBefore: String? = nil
    var endsSequence = false
    var colorCall: String? = nil
    var enclosingStart: Int? = nil
}

final class FileReader {
    var findings: [Finding] = []
    var keyCounts: [Key: Int] = [:]
    var literals = 0
    var seenDecls: Set<String> = []
    var ancestorDecls: [String] = []

    func note(_ node: JSON, _ place: Place, _ message: String?) {
        guard let key = key(of: node) else { return }
        let ordinal = keyCounts[key, default: 0]
        keyCounts[key] = ordinal + 1
        if let message {
            findings.append(Finding(key: key, ordinal: ordinal, enclosingStart: place.enclosingStart, message: message))
        }
    }

    func visit(_ node: JSON, _ place: Place) {
        switch node {
        case .array(let elements):
            for element in elements { visit(element, place) }
        case .object(let members):
            visitObject(node, members, place)
        default:
            break
        }
    }

    func visitObject(_ node: JSON, _ members: [(key: String, value: JSON)], _ place: Place) {
        let kind = node["_kind"]?.string ?? ""
        var inner = Place(colorCall: place.colorCall, enclosingStart: place.enclosingStart)
        if let start = node["range"]?["start"]?.int { inner.enclosingStart = start }

        // The parse dump lists some declarations twice (an enum's elements, under their case and as members).
        // A declaration with the same kind and range as one already read is skipped, unless it is inside it.
        var declKey: String? = nil
        if kind.hasSuffix("_decl"), let start = node["range"]?["start"]?.int, let end = node["range"]?["end"]?.int {
            let id = "\(kind) \(start) \(end)"
            if seenDecls.contains(id) && !ancestorDecls.contains(id) { return }
            seenDecls.insert(id)
            declKey = id
        }
        if let declKey { ancestorDecls.append(declKey) }
        defer { if declKey != nil { ancestorDecls.removeLast() } }

        if kind.contains("literal") {
            literals += 1
            judgeLiteral(node, kind, place)
        } else if kind == "unresolved_dot_expr", let field = node["field"]?.string, !field.hasPrefix("init"),
            let base = node["base"], let type = finalName(base), colorTypes.contains(type)
        {
            note(node, place, "a named colour: \(type).\(field). Colours come from the tokens (KeyStyle, Palette)")
        } else if kind == "unresolved_member_expr", let name = node["name"]?.string, namedColors.contains(name) {
            note(node, place, "a named colour: .\(name). Colours come from the tokens (KeyStyle, Palette)")
        } else {
            note(node, place, nil)
        }

        // A colour call: every literal in its arguments is a colour made from literals.
        if kind == "call_expr", let fn = node["fn"], let name = finalName(fn),
            colorTypes.contains(name) || colorFunctions.contains(name)
                || (name == "copy" && node["args"]?["labels"]?.string == "alpha:")
        {
            inner.colorCall = name
        }

        for member in members {
            // The parse dump repeats an initialiser as `processed_init`; `original_init` is the source's.
            if member.key == "processed_init" { continue }
            if kind == "sequence_expr", member.key == "elements", case .array(let elements) = member.value {
                for (index, element) in elements.enumerated() {
                    var elementPlace = inner
                    if index >= 2, elements[index - 1]["_kind"]?.string == "unresolved_decl_ref_expr" {
                        elementPlace.operatorBefore = elements[index - 1]["name"]?.string
                    }
                    elementPlace.endsSequence = index == elements.count - 1
                    visit(element, elementPlace)
                }
            } else {
                visit(member.value, inner)
            }
        }
    }

    func judgeLiteral(_ node: JSON, _ kind: String, _ place: Place) {
        if numberKinds.contains(kind) {
            let negative = node["negative"]?.isTrue == true
            let spelling = (negative ? "-" : "") + (node["value"]?.string ?? "?")
            if let call = place.colorCall {
                note(node, place, "a colour made from literals: \(spelling) in a call to \(call)")
            } else if allowed(node, kind, negative, place) {
                note(node, place, nil)
            } else {
                note(node, place, "a number typed into view code: \(spelling). Metrics come from the tokens")
            }
        } else if kind == objectLiteralKind {
            note(
                node, place,
                "a playground literal (#\(node["kind"]?.string ?? "?")Literal): colours come from the tokens")
        } else if passingLiteralKinds.contains(kind) {
            let value = node["value"]?.string ?? ""
            if kind == "string_literal_expr", let call = place.colorCall {
                note(node, place, "a colour made from literals: the string \"\(value)\" in a call to \(call)")
            } else if kind == "string_literal_expr", value.range(of: hexColor, options: .regularExpression) != nil {
                note(node, place, "a colour as a hex string: \"\(value)\"")
            } else {
                note(node, place, nil)
            }
        } else {
            fail("the parse dump has a literal of a kind the guard does not know: \(kind)")
        }
    }

    /// The allowances, listed with their reasons in scripts/literal-guard.sh.
    func allowed(_ node: JSON, _ kind: String, _ negative: Bool, _ place: Place) -> Bool {
        guard !negative, let value = node["value"]?.string else { return false }
        if (kind == "integer_literal_expr" && value == "0") || (kind == "float_literal_expr" && value == "0.0") {
            return true
        }
        if kind == "integer_literal_expr", value == "1", place.endsSequence,
            place.operatorBefore == "+=" || place.operatorBefore == "-="
        {
            return true
        }
        return kind == "integer_literal_expr" && value == "2" && place.operatorBefore == "/"
    }
}

// MARK: - Lines from the type-checked dump

/// The located nodes of the type-checked dump, by key, in source order. Implicit nodes, which the compiler made
/// and the source does not hold, are left out; a node dumped twice (an initialiser's original and processed form)
/// counts once.
func locatedNodes(_ ast: JSON?) -> [Key: [Int]] {
    var found: [Key: Set<Int>] = [:]
    func walk(_ node: JSON) {
        switch node {
        case .array(let elements):
            for element in elements { walk(element) }
        case .object(let members):
            if node["implicit"]?.isTrue != true, let key = key(of: node), let start = node["range"]?["start"]?.int {
                found[key, default: []].insert(start)
            }
            for member in members { walk(member.value) }
        default:
            break
        }
    }
    if let ast { walk(ast) }
    return found.mapValues { $0.sorted() }
}

func lineAndColumn(_ offset: Int, in source: [UInt8]) -> (Int, Int) {
    var line = 1
    var lineStart = 0
    var index = 0
    while index < min(offset, source.count) {
        if source[index] == 0x0A {
            line += 1
            lineStart = index + 1
        }
        index += 1
    }
    return (line, offset - lineStart + 1)
}

// MARK: - Main

let arguments = Array(CommandLine.arguments.dropFirst())
guard !arguments.isEmpty, arguments.count % 3 == 0 else {
    fail("usage: literal-guard.swift (<source> <parse dump> <ast dump>)...")
}

var problems = 0
var literalCount = 0
for index in stride(from: 0, to: arguments.count, by: 3) {
    let (path, parsePath, astPath) = (arguments[index], arguments[index + 1], arguments[index + 2])
    guard let source = FileManager.default.contents(atPath: path) else { fail("cannot read \(path)") }
    guard let parseData = FileManager.default.contents(atPath: parsePath), let parse = JSONReader.read(parseData),
        parse["_kind"]?.string == "source_file", case .array = parse["items"] ?? .null,
        parse["compiler_version"]?["major"]?.string == "6"
    else {
        fail("the compiler's parse dump of \(path) is not the Swift 6 JSON AST dump this guard reads")
    }
    let reader = FileReader()
    reader.visit(parse, Place())
    literalCount += reader.literals
    if reader.findings.isEmpty { continue }

    let ast = FileManager.default.contents(atPath: astPath).flatMap(JSONReader.read)
    let located = locatedNodes(ast?["_kind"]?.string == "source_file" ? ast : nil)
    let bytes = [UInt8](source)
    for finding in reader.findings {
        let offsets = located[finding.key] ?? []
        let location: String
        if offsets.count == reader.keyCounts[finding.key], finding.ordinal < offsets.count {
            let (line, column) = lineAndColumn(offsets[finding.ordinal], in: bytes)
            location = "\(path):\(line):\(column)"
        } else if let start = finding.enclosingStart {
            let (line, _) = lineAndColumn(start, in: bytes)
            location =
                "\(path):\(line): (in the declaration or statement starting here; the compiler gives no closer place)"
        } else {
            location = "\(path): (the compiler gives no line)"
        }
        FileHandle.standardError.write(Data("literal guard: FAIL: \(location): \(finding.message)\n".utf8))
        problems += 1
    }
}
if problems > 0 { exit(1) }
print("Swift files: \(arguments.count / 3), literals read: \(literalCount)")
