// Reads the output of `swift package dump-package` on standard input, and fails
// if the SpeakboardCore target is not a regular target, declares any
// dependency, or sets `path`, `sources`, plugin usages or any build setting, if
// the package could build the core in a language mode other than Swift 6, or if
// the SpeakboardCore product holds any target but SpeakboardCore.
//
// The core is Foundation only (AGENTS.md, ADR-0005). The core guard reads the
// folder Sources/SpeakboardCore, so it proves the core clean only while SwiftPM
// compiles exactly that folder into the core, with nothing added to it. A
// dependency, a `path` or `sources` that points elsewhere, a build tool plugin
// that generates code, and an unsafe flag that hands the compiler another file
// are four ways around that. A binary target named SpeakboardCore, and another
// target bundled into the SpeakboardCore library product, are two more.
//
// The core imports guard reads every core file as Swift 6 (`-swift-version 6`).
// In another language mode the same text can mean other code: with Swift 5 and
// custom prefix and postfix `/` operators, `let a = /b; import X; let c = b/`
// is a regex literal to Swift 6 and an import to Swift 5 (KEY-56). So the core
// is always built as Swift 6: the core target sets no build settings at all
// (no `swiftSettings`, `cSettings`, `cxxSettings` or `linkerSettings`, which
// also rules out a language mode, defines, upcoming features and unsafe flags),
// the package sets no `swiftLanguageModes`, and its tools version is 6.x:
// below 6.0 a target defaults to Swift 5 mode, and a later major version may
// default to a later mode than the imports guard reads.
//
// This check closes those ways, not every way: it reads only these keys of the
// package, the target and the product.
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

// Build settings. Unsafe flags can pass the compiler or linker anything,
// including a source file from outside the core, and a language mode changes
// how the imports guard's Swift 6 reading of a file relates to the build. The
// core needs no setting, so any setting, for any tool, fails.
guard let settings = (core["settings"] ?? []) as? [[String: Any]] else {
    fail("the SpeakboardCore target has no readable settings list")
}

if let setting = settings.first {
    let kind = (setting["kind"] as? [String: Any])?.keys.sorted().first ?? "unknown"
    let tool = setting["tool"] as? String ?? "unknown"
    fail(
        "the SpeakboardCore target sets `\(kind)` (a \(tool) setting, \(settings.count) in all). The core is built"
            + " with no settings, as Swift 6."
    )
}

// The package's language modes apply to every target that sets none.
if let modes = manifest["swiftLanguageVersions"], !(modes is NSNull) {
    fail("the package sets `swiftLanguageModes` (\(modes)). The core is built as Swift 6, the default.")
}

// Below tools version 6.0 a target defaults to Swift 5 language mode.
guard
    let toolsVersion = (manifest["toolsVersion"] as? [String: Any])?["_version"] as? String,
    let major = Int(toolsVersion.prefix(while: { $0 != "." }))
else {
    fail("could not read the package's tools version")
}

if major < 6 {
    fail("the package's tools version is \(toolsVersion). Below 6.0 the core would build as Swift 5.")
}

// A later major tools version may default to a later language mode, while the
// imports guard reads every file as Swift 6. Fail closed: moving to it means
// changing both guards together (KEY-56 review round 1).
if major > 6 {
    fail(
        "the package's tools version is \(toolsVersion). This guard vouches only for 6.x, whose default language mode"
            + " is Swift 6, the mode the imports guard reads core files in (-swift-version 6). Change both guards"
            + " together to move past 6."
    )
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
        + " sources, plugins or settings; it builds as Swift 6; the SpeakboardCore product holds only that target)"
)
