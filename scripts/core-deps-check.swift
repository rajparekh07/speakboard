// Reads the output of `swift package dump-package` on standard input, and fails
// if the SpeakboardCore target is not a regular target, declares any
// dependency, or sets `path`, `sources`, plugin usages or `unsafeFlags`, or if
// the SpeakboardCore product holds any target but SpeakboardCore.
//
// The core is Foundation only (AGENTS.md, ADR-0005). The core guard reads the
// folder Sources/SpeakboardCore, so it proves the core clean only while SwiftPM
// compiles exactly that folder into the core, with nothing added to it. A
// dependency, a `path` or `sources` that points elsewhere, a build tool plugin
// that generates code, and an unsafe flag that hands the compiler another file
// are four ways around that. A binary target named SpeakboardCore, and another
// target bundled into the SpeakboardCore library product, are two more. This
// check closes those six ways, not every way: it reads only these keys of the
// target and the product, and other settings are not checked.
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

// A binary, system library, plugin or macro target is not compiled from the
// core folder at all.
guard core["type"] as? String == "regular" else {
    fail("the SpeakboardCore target is of type `\(core["type"] ?? "unknown")`. The core is a regular target.")
}

guard let dependencies = core["dependencies"] as? [Any] else {
    fail("the SpeakboardCore target has no readable dependency list")
}

if !dependencies.isEmpty {
    fail("the SpeakboardCore target declares dependencies (\(dependencies.count)). The core depends on nothing.")
}

// SwiftPM leaves these keys out of the description when the target does not set
// them. Any value, even the default folder or an empty list, counts as set, so
// the core guard's folder is always the one SwiftPM compiles.
for key in ["path", "sources", "pluginUsages"] {
    if let value = core[key], !(value is NSNull) {
        fail(
            "the SpeakboardCore target sets `\(key)`. The core is the folder Sources/SpeakboardCore, as SwiftPM finds it."
        )
    }
}

// Unsafe flags can pass the compiler or linker anything, including a source
// file from outside the core. Any tool's unsafe flags count.
guard let settings = (core["settings"] ?? []) as? [[String: Any]] else {
    fail("the SpeakboardCore target has no readable settings list")
}

if settings.contains(where: { ($0["kind"] as? [String: Any])?["unsafeFlags"] != nil }) {
    fail("the SpeakboardCore target sets `unsafeFlags`. The core is built with no unsafe flags.")
}

// The library product is what an app links. A target bundled into it beside
// the core reaches the app without going through the core target's checks.
let products = manifest["products"] as? [[String: Any]] ?? []
guard let product = products.first(where: { $0["name"] as? String == "SpeakboardCore" }) else {
    fail("Package.swift has no SpeakboardCore product")
}

guard let productTargets = product["targets"] as? [String], productTargets == ["SpeakboardCore"] else {
    fail(
        "the SpeakboardCore product holds targets \(product["targets"] ?? "unknown"). It holds exactly"
            + " [\"SpeakboardCore\"]."
    )
}

print(
    "core dependency guard: OK (the SpeakboardCore target is regular and declares no dependencies, path,"
        + " sources, plugins or unsafe flags; the SpeakboardCore product holds only that target)"
)
