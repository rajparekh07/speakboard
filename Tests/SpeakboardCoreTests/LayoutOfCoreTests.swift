import Foundation
import SpeakboardCore
import Testing

/// The core's source folders are the architecture layout in AGENTS.md.
/// This test fails if one of them is removed or renamed without updating it.
@Suite("Layout of the core")
struct LayoutOfCoreTests {
    static let areas = ["Layout", "Typing", "Autocorrect", "Cleanup", "Session", "Budgets"]

    static let coreSources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // SpeakboardCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root
        .appendingPathComponent("Sources/SpeakboardCore")

    @Test("Each area has its source folder", arguments: areas)
    func areaHasFolder(_ area: String) {
        var isDirectory: ObjCBool = false
        let path = Self.coreSources.appendingPathComponent(area).path
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        #expect(exists && isDirectory.boolValue, "missing folder: \(path)")
    }

    @Test("The core has no folders outside the six areas")
    func noOtherFolders() throws {
        let entries = try FileManager.default.contentsOfDirectory(atPath: Self.coreSources.path)
        let folders = entries.filter { entry in
            var isDirectory: ObjCBool = false
            let path = Self.coreSources.appendingPathComponent(entry).path
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
        #expect(Set(folders) == Set(Self.areas))
    }
}
