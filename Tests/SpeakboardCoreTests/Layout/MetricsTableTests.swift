import Foundation
import SpeakboardCore
import Testing

/// The generated metrics tables carry exactly what the pinned export says, read here from the JSON itself
/// rather than through the generator.
@Suite("Metrics tables against the pinned export")
struct MetricsTableTests {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // Layout
        .deletingLastPathComponent()  // SpeakboardCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root

    static func export() throws -> [String: Any] {
        let url = repoRoot.appendingPathComponent("DesignTokens/speakboard-tokens.json")
        return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    /// "key.letter.width" -> "keyLetterWidth", the generator's naming.
    static func propertyName(_ id: String) -> String {
        let parts = id.split(separator: ".")
        return parts[0] + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    }

    /// The cells of a row, by property name, through reflection. Aliases are computed and read separately.
    static func cells(_ metrics: Metrics) -> [String: MetricCell] {
        var cells: [String: MetricCell] = [:]
        for child in Mirror(reflecting: metrics).children {
            if let label = child.label, let cell = child.value as? MetricCell { cells[label] = cell }
        }
        cells["micGlyphSize"] = metrics.micGlyphSize
        cells["dictationTranscriptLabelSize"] = metrics.dictationTranscriptLabelSize
        return cells
    }

    /// The "key: value" lines of DesignTokens/tokens.pin.
    static func pin() throws -> [String: String] {
        let url = repoRoot.appendingPathComponent("DesignTokens/tokens.pin")
        var pin: [String: String] = [:]
        for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") where !line.hasPrefix("#") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            pin[line[..<colon].trimmingCharacters(in: .whitespaces)] =
                line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return pin
    }

    @Test("The version the tables name is the pinned export's")
    func version() throws {
        let export = try Self.export()
        let pin = try Self.pin()
        #expect(TokenExport.tokenSetVersion == export["tokenSetVersion"] as? String)
        #expect(TokenExport.tokenSetVersion == pin["token-set-version"])
        #expect(TokenExport.publishLabel == pin["publish-label"])
        #expect(TokenExport.sha256 == pin["sha256"])
    }

    @Test("Device classes are the export's, in its order, with its screen sizes")
    func deviceClasses() throws {
        let export = try Self.export()
        let axes = try #require(export["axes"] as? [String: Any])
        #expect(DeviceClass.allCases.map(\.rawValue) == axes["deviceClass"] as? [String])
        let ios = try #require((export["ios"] as? [String: Any])?["26"] as? [String: Any])
        let classes = try #require(ios["deviceClasses"] as? [String: Any])
        for deviceClass in DeviceClass.allCases {
            let entry = try #require(classes[deviceClass.rawValue] as? [String: Any])
            let screen = try #require(entry["screen"] as? [String: Any])
            #expect(deviceClass.screenWidth == (screen["width"] as? NSNumber)?.doubleValue)
            #expect(deviceClass.screenHeight == (screen["height"] as? NSNumber)?.doubleValue)
            #expect(deviceClass.hasHomeIndicator == entry["homeIndicator"] as? Bool)
        }
    }

    @Test("Every cell holds the export's value, tolerance, kind and placeholder flag")
    func everyCell() throws {
        let export = try Self.export()
        let ios = try #require((export["ios"] as? [String: Any])?["26"] as? [String: Any])
        let tokens = try #require(ios["tokens"] as? [String: [String: Any]])
        let columns = tokens.filter { ($0.value["axes"] as? [String]) == ["deviceClass", "orientation"] }
        #expect(columns.count == Self.cells(Metrics.of(.iphone393x852, .portrait)).count)

        var checked = 0
        var placeholders = 0
        for (deviceClass, orientation) in allClassesAndOrientations {
            let cells = Self.cells(Metrics.of(deviceClass, orientation))
            for (id, token) in columns {
                let values = try #require(token["values"] as? [String: [String: [String: Any]]])
                let leaf = try #require(values[deviceClass.rawValue]?[orientation.rawValue])
                let provenance = try #require(leaf["provenance"] as? [String: Any])
                let cell = try #require(cells[Self.propertyName(id)], "no column for \(id)")
                let context = "\(id) \(deviceClass) \(orientation)"

                #expect(cell.value == (leaf["value"] as? NSNumber)?.doubleValue, "\(context)")
                let tolerance = (provenance["tolerance"] as? [String: Any])?["plusMinus"] as? NSNumber
                switch provenance["kind"] as? String {
                case "estimated":
                    #expect(cell.kind == .estimated && cell.tolerance == tolerance?.doubleValue, "\(context)")
                    #expect(cell.isPlaceholder == (provenance["confidence"] as? String == "none"), "\(context)")
                case "invented":
                    #expect(cell.kind == .invented && cell.tolerance == nil && !cell.isPlaceholder, "\(context)")
                default:
                    Issue.record("\(context): a kind this test does not expect: \(provenance["kind"] ?? "none")")
                }
                checked += 1
                placeholders += cell.isPlaceholder ? 1 : 0
            }
        }
        #expect(checked == 20 * columns.count)
        #expect(placeholders > 0, "the export has placeholder cells; the table lost their flags")
    }
}
