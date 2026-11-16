import Foundation
import Testing

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
        // An import line: optional attributes, an optional access level (Swift 6: `internal import X` and so
        // on), `import`, an optional kind (struct, func, ...), then the module.
        let pattern = try Regex(
            #"^\s*(?:@\w+\s+)*(?:(?:public|package|internal|fileprivate|private)\s+)?import\s+(?:\w+\s+)?([\w.]+)"#
        ).anchorsMatchLineEndings()
        for file in files {
            let text = try String(contentsOf: core.appendingPathComponent(file), encoding: .utf8)
            for match in text.matches(of: pattern) {
                let module = String(match.output[1].substring ?? "").split(separator: ".").first.map(String.init)
                #expect(module == "Foundation", "\(file) imports \(module ?? "?")")
            }
        }
    }
}
