import Foundation
import Testing

/// The modules a Swift source file imports, in order: the first path component of every `import` declaration,
/// without backticks.
///
/// `import` is a keyword, so an `import` token in code always starts an import declaration, wherever it sits on
/// the line. The scan first blanks out comments (line and nested block comments) and string literals (plain,
/// multi-line and raw, with interpolations scanned as code), then reads, after each `import` token that does not
/// follow a `.`, an optional kind (`typealias`, `struct`, `class`, `enum`, `protocol`, `let`, `var`, `func`) and
/// the module name. Attributes, access levels, `;` and line breaks around it do not matter.
///
/// Not handled: regex literals (`/.../`), which could hide or fake an import only if they held the word.
func importedModules(in source: String) -> [String] {
    var scanner = CommentAndStringStripper(Array(source.utf8))
    scanner.code(inInterpolation: false)
    return ImportReader(scanner.output).modules()
}

/// Copies Swift source with every comment and string literal replaced by a space.
struct CommentAndStringStripper {
    let source: [UInt8]
    var index = 0
    var output: [UInt8] = []

    init(_ source: [UInt8]) { self.source = source }

    func byte(_ offset: Int) -> UInt8? {
        index + offset < source.count ? source[index + offset] : nil
    }

    func matches(_ text: String, at offset: Int = 0) -> Bool {
        let bytes = Array(text.utf8)
        guard index + offset + bytes.count <= source.count else { return false }
        return Array(source[(index + offset)..<(index + offset + bytes.count)]) == bytes
    }

    /// Code, up to the end of the source, or in an interpolation up to its closing parenthesis.
    mutating func code(inInterpolation: Bool) {
        var depth = 0
        while index < source.count {
            if matches("//") {
                while index < source.count && source[index] != UInt8(ascii: "\n") { index += 1 }
                output.append(UInt8(ascii: " "))
                continue
            }
            if matches("/*") {
                blockComment()
                output.append(UInt8(ascii: " "))
                continue
            }
            var hashes = 0
            while byte(hashes) == UInt8(ascii: "#") { hashes += 1 }
            if byte(hashes) == UInt8(ascii: "\"") {
                index += hashes
                stringLiteral(hashes: hashes)
                output.append(UInt8(ascii: " "))
                continue
            }
            let current = source[index]
            if inInterpolation {
                if current == UInt8(ascii: "(") { depth += 1 }
                if current == UInt8(ascii: ")") {
                    if depth == 0 {
                        index += 1
                        return
                    }
                    depth -= 1
                }
            }
            output.append(current)
            index += 1
        }
    }

    /// A block comment, which nests in Swift. `index` is at its opening `/*`.
    mutating func blockComment() {
        var depth = 0
        while index < source.count {
            if matches("/*") {
                depth += 1
                index += 2
            } else if matches("*/") {
                depth -= 1
                index += 2
                if depth == 0 { return }
            } else {
                index += 1
            }
        }
    }

    /// A string literal opened by `hashes` hash signs; `index` is at its first quote.
    mutating func stringLiteral(hashes: Int) {
        let multiLine = matches("\"\"\"")
        let close = (multiLine ? "\"\"\"" : "\"") + String(repeating: "#", count: hashes)
        let escape = "\\" + String(repeating: "#", count: hashes)
        index += multiLine ? 3 : 1
        while index < source.count {
            if matches(escape) {
                index += escape.utf8.count
                if byte(0) == UInt8(ascii: "(") {
                    index += 1
                    code(inInterpolation: true)
                } else {
                    index += 1  // the escaped character
                }
            } else if matches(close) {
                index += close.utf8.count
                return
            } else {
                index += 1
            }
        }
    }
}

/// Reads import declarations from source that has no comments or string literals left.
struct ImportReader {
    static let kinds: Set = ["typealias", "struct", "class", "enum", "protocol", "let", "var", "func"]

    /// The tokens: identifiers (backticks kept, so a backticked `import` is not the keyword), `.`, and any other
    /// character as itself. Whitespace is dropped.
    let tokens: [String]

    init(_ source: [UInt8]) {
        var tokens: [String] = []
        var index = 0
        func isIdentifier(_ byte: UInt8) -> Bool {
            byte == UInt8(ascii: "_") || (byte >= 0x30 && byte <= 0x39) || (byte | 0x20 >= 0x61 && byte | 0x20 <= 0x7A)
                || byte >= 0x80
        }
        while index < source.count {
            let byte = source[index]
            if byte == UInt8(ascii: "`") {
                var end = index + 1
                while end < source.count && source[end] != UInt8(ascii: "`") { end += 1 }
                tokens.append(String(decoding: source[index...min(end, source.count - 1)], as: UTF8.self))
                index = end + 1
            } else if isIdentifier(byte) {
                var end = index
                while end < source.count && isIdentifier(source[end]) { end += 1 }
                tokens.append(String(decoding: source[index..<end], as: UTF8.self))
                index = end
            } else {
                if ![UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\n"), UInt8(ascii: "\r")].contains(byte) {
                    tokens.append(String(UnicodeScalar(byte)))
                }
                index += 1
            }
        }
        self.tokens = tokens
    }

    func modules() -> [String] {
        var modules: [String] = []
        for (position, token) in tokens.enumerated() where token == "import" {
            if position > 0 && tokens[position - 1] == "." { continue }  // a member named import
            var next = position + 1
            if next + 1 < tokens.count && Self.kinds.contains(tokens[next]) { next += 1 }
            guard next < tokens.count else {
                modules.append("?")
                continue
            }
            modules.append(tokens[next].replacingOccurrences(of: "`", with: ""))
        }
        return modules
    }
}

/// Nothing under Sources/SpeakboardCore imports anything but Foundation (AGENTS.md, ADR-0005).
@Suite("Core imports")
struct CoreImportsTests {
    @Test("Every import in the core is Foundation")
    func foundationOnly() throws {
        let core = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SpeakboardCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("Sources/SpeakboardCore")
        let files = try #require(FileManager.default.enumerator(atPath: core.path)).compactMap { $0 as? String }
            .filter { $0.hasSuffix(".swift") }
        #expect(!files.isEmpty)
        for file in files {
            let text = try String(contentsOf: core.appendingPathComponent(file), encoding: .utf8)
            for module in importedModules(in: text) {
                #expect(module == "Foundation", "\(file) imports \(module)")
            }
        }
    }

    /// Import spellings, each with the modules the scan must report. Includes every spelling the KEY-21 reviews
    /// tried.
    static let spellings: [(source: String, modules: [String])] = [
        ("import Foundation", ["Foundation"]),
        ("import Foundation\n\npublic struct X {}", ["Foundation"]),
        ("import Foundation\nextension Int {}\nenum E {}", ["Foundation"]),
        ("import Foundation\nlet x = 1", ["Foundation"]),
        ("internal import Dispatch", ["Dispatch"]),
        ("public import Dispatch", ["Dispatch"]),
        ("package import Dispatch", ["Dispatch"]),
        ("fileprivate import Dispatch", ["Dispatch"]),
        ("private import Dispatch", ["Dispatch"]),
        ("@preconcurrency internal import Dispatch\nstruct X {}", ["Dispatch"]),
        ("@_exported import Dispatch", ["Dispatch"]),
        ("@_implementationOnly import Dispatch", ["Dispatch"]),
        ("@_spi(Foo) import Dispatch", ["Dispatch"]),
        ("import Foundation; import Dispatch", ["Foundation", "Dispatch"]),
        ("import `Dispatch`", ["Dispatch"]),
        ("/* x */ import Dispatch", ["Dispatch"]),
        ("/* outer /* nested */ import Fake */ import Dispatch", ["Dispatch"]),
        ("// import Fake\nimport Dispatch", ["Dispatch"]),
        ("import Dispatch // import Fake", ["Dispatch"]),
        ("import struct Dispatch.DispatchQueue", ["Dispatch"]),
        ("import func Glibc.exit", ["Glibc"]),
        ("import class Foundation.NSString", ["Foundation"]),
        ("import Foundation.NSString", ["Foundation"]),
        ("#if canImport(Glibc)\n    import Glibc\n#endif", ["Glibc"]),
        ("import\n    Dispatch", ["Dispatch"]),
        ("let importantValue = 1\nfunc reimport() {}", []),
        ("let s = \"import Fake\"", []),
        ("let s = \"a \\\" import Fake\"\nimport Dispatch", ["Dispatch"]),
        ("let s = \"\"\"\n    import Fake\n    \"\"\"\nimport Dispatch", ["Dispatch"]),
        ("let s = #\"import \"Fake\" \\\"#\nimport Dispatch", ["Dispatch"]),
        ("let s = \"\\(f(\"import Fake\")) x\"\nimport Dispatch", ["Dispatch"]),
        ("let s = \"\\(g(\"(\")) import Fake\"\nimport Dispatch", ["Dispatch"]),
        ("let p = x.import", []),
        ("let `import` = 1", []),
    ]

    @Test("The scan reads each import spelling", arguments: spellings.indices)
    func spelling(_ index: Int) {
        let (source, modules) = Self.spellings[index]
        #expect(importedModules(in: source) == modules, "source: \(source)")
    }
}
