// Reads the output of `swift package dump-package` on standard input, and fails
// if the SpeakboardCore target declares any dependency.
//
// The core is Foundation only (AGENTS.md, ADR-0005). The core guard reads the
// core's own files, so a dependency is the other way networking code could
// reach the core. This check closes that way.
//
// Run by scripts/core-deps-guard.sh inside the Swift image.

import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("core dependency guard: FAIL: \(message)\n".utf8))
    exit(1)
}

let input = FileHandle.standardInput.readDataToEndOfFile()

guard
    let manifest = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
    let targets = manifest["targets"] as? [[String: Any]]
else {
    fail("could not read the package description")
}

guard let core = targets.first(where: { $0["name"] as? String == "SpeakboardCore" }) else {
    fail("Package.swift has no SpeakboardCore target")
}

guard let dependencies = core["dependencies"] as? [Any] else {
    fail("the SpeakboardCore target has no readable dependency list")
}

if !dependencies.isEmpty {
    fail("the SpeakboardCore target declares dependencies (\(dependencies.count)). The core depends on nothing.")
}

print("core dependency guard: OK (the SpeakboardCore target declares no dependencies)")
