#!/usr/bin/env bash
# Proves the core dependency guard works: it must pass on a core with no
# dependencies, and fail on each way of adding one, on a core that sets
# `path`, `sources`, plugins or any build setting, on a package that could build
# the core in a language mode other than Swift 6, on a core that is not a
# regular target, and on a SpeakboardCore product that holds another target.
# Each failing case must fail with
# its own message, so a case cannot pass by failing for another reason. Runs on
# throwaway packages in .build, never on the real Package.swift. Runs inside the
# Swift image, or natively (make check-native).
set -euo pipefail

guard="$(cd "$(dirname "$0")" && pwd)/core-deps-guard.sh"
check="$(cd "$(dirname "$0")" && pwd)/core-deps-check.swift"
work=".build/core-deps-selftest"
rm -rf "$work"
mkdir -p "$work"

failures=0

core_product='.library(name: "SpeakboardCore", targets: ["SpeakboardCore"])'

# expect pass <description> <targets> [""] [products]
# expect fail <description> <targets> <text the failure message must contain> [products]
# Products default to a SpeakboardCore library holding only the core target.
# Set `tools` to change the tools version (default 6.0), and `extra` to add
# arguments to Package(...) after the targets.
expect() {
    local want="$1" description="$2" targets="$3" message="${4:-}" products="${5-$core_product}"
    local dir="$work/case$RANDOM"
    mkdir -p "$dir"
    cat > "$dir/Package.swift" <<EOF
// swift-tools-version: ${tools:-6.0}
import PackageDescription
let package = Package(
    name: "Case",
    products: [$products],
    dependencies: [.package(url: "https://example.invalid/net.git", from: "1.0.0")],
    targets: [$targets]${extra:+,
    $extra}
)
EOF
    local output got
    if output=$("$guard" "$dir" 2>&1); then got=pass; else got=fail; fi
    if [ "$got" != "$want" ]; then
        echo "core dependency guard self-test: WRONG: $description (wanted $want, got $got)" >&2
        failures=$((failures + 1))
    elif [ "$want" = fail ] && ! grep -qF -- "$message" <<< "$output"; then
        echo "core dependency guard self-test: WRONG: $description (failed, but not with \"$message\")" >&2
        echo "$output" >&2
        failures=$((failures + 1))
    else
        echo "core dependency guard self-test: ok: $description ($want)"
    fi
}

deps="FAIL: the SpeakboardCore target declares dependencies"
sets="FAIL: the SpeakboardCore target sets"

expect pass "no dependencies" '.target(name: "SpeakboardCore"), .target(name: "Net")'
expect fail "a target in this package" \
    '.target(name: "Net"), .target(name: "SpeakboardCore", dependencies: ["Net"])' "$deps"
expect fail "a target, written as .target" \
    '.target(name: "Net"), .target(name: "SpeakboardCore", dependencies: [.target(name: "Net")])' "$deps"
expect fail "a product of another package" \
    '.target(name: "SpeakboardCore", dependencies: [.product(name: "Net", package: "net")])' "$deps"
expect fail "no SpeakboardCore target" '.target(name: "Net")' "FAIL: Package.swift has no SpeakboardCore target" ''
expect fail "a path to another folder" \
    '.target(name: "SpeakboardCore", path: "Sources/Elsewhere")' "$sets \`path\`"
expect fail "a path to the default folder" \
    '.target(name: "SpeakboardCore", path: "Sources/SpeakboardCore")' "$sets \`path\`"
expect fail "a sources list" \
    '.target(name: "SpeakboardCore", sources: ["../Elsewhere/Net.swift"])' "$sets \`sources\`"
expect fail "an empty sources list" '.target(name: "SpeakboardCore", sources: [])' "$sets \`sources\`"
expect fail "a build tool plugin" \
    '.plugin(name: "Gen", capability: .buildTool()), .target(name: "SpeakboardCore", plugins: ["Gen"])' \
    "$sets \`pluginUsages\`"
expect fail "an empty plugin list" '.target(name: "SpeakboardCore", plugins: [])' "$sets \`pluginUsages\`"
expect fail "an unsafe Swift flag" \
    '.target(name: "SpeakboardCore", swiftSettings: [.unsafeFlags(["../Elsewhere/Net.swift"])])' \
    "$sets \`unsafeFlags\`"
expect fail "an unsafe linker flag" \
    '.target(name: "SpeakboardCore", linkerSettings: [.unsafeFlags(["-lnet"])])' "$sets \`unsafeFlags\`"
expect fail "a Swift define" \
    '.target(name: "SpeakboardCore", swiftSettings: [.define("SPEAKBOARD")])' "$sets \`define\`"
expect pass "an empty swiftSettings list (no setting)" '.target(name: "SpeakboardCore", swiftSettings: [])'
expect fail "Swift 5 language mode on the core (the KEY-21 round 5 reproduction)" \
    '.target(name: "SpeakboardCore", swiftSettings: [.swiftLanguageMode(.v5)])' "$sets \`swiftLanguageMode\`"
expect fail "an upcoming feature" \
    '.target(name: "SpeakboardCore", swiftSettings: [.enableUpcomingFeature("ExistentialAny")])' \
    "$sets \`enableUpcomingFeature\`"
expect fail "a C setting" '.target(name: "SpeakboardCore", cSettings: [.define("NET")])' "$sets \`define\` (a c setting"
expect fail "a linked library" \
    '.target(name: "SpeakboardCore", linkerSettings: [.linkedLibrary("net")])' "$sets \`linkedLibrary\`"
extra='swiftLanguageModes: [.v5]' expect fail "Swift 5 language mode on the package" \
    '.target(name: "SpeakboardCore")' "FAIL: the package sets \`swiftLanguageModes\`"
extra='swiftLanguageModes: [.v6]' expect fail "Swift 6 language mode named on the package" \
    '.target(name: "SpeakboardCore")' "FAIL: the package sets \`swiftLanguageModes\`"
tools=5.10 expect fail "tools version 5.10 (Swift 5 mode by default)" '.target(name: "SpeakboardCore")' \
    "FAIL: the package's tools version is 5.10.0"
tools=6.1 expect pass "tools version 6.1" '.target(name: "SpeakboardCore")'
# The pinned toolchain refuses a manifest newer than itself, so today a 7.0 package fails before the check runs.
tools=7.0 expect fail "tools version 7.0 (the toolchain refuses it)" '.target(name: "SpeakboardCore")' \
    "FAIL: could not read the package"

# A later toolchain would read such a package, so the check itself must refuse a major tools version above 6. It is
# fed the description of a valid package with its tools version changed, as that toolchain would print it.
check_tools() {
    local version="$1" want="$2" message="${3:-}" description="tools version $1 in the package description"
    local dir="$work/tools$RANDOM" output got
    mkdir -p "$dir"
    printf '// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name: "Case", products: [%s], targets: [.target(name: "SpeakboardCore")])\n' \
        "$core_product" > "$dir/Package.swift"
    if ! output=$(swift package --package-path "$dir" dump-package 2>&1); then
        echo "core dependency guard self-test: WRONG: $description (could not dump the package)" >&2
        failures=$((failures + 1))
        return
    fi
    output=$(printf '%s' "$output" | sed "s/\"_version\" : \"6.0.0\"/\"_version\" : \"$version\"/")
    if ! grep -qF "\"_version\" : \"$version\"" <<< "$output"; then
        echo "core dependency guard self-test: WRONG: $description (the tools version was not replaced)" >&2
        failures=$((failures + 1))
        return
    fi
    if output=$(printf '%s' "$output" | swift "$check" 2>&1); then got=pass; else got=fail; fi
    if [ "$got" != "$want" ]; then
        echo "core dependency guard self-test: WRONG: $description (wanted $want, got $got)" >&2
        echo "$output" >&2
        failures=$((failures + 1))
    elif [ "$want" = fail ] && ! grep -qF -- "$message" <<< "$output"; then
        echo "core dependency guard self-test: WRONG: $description (failed, but not with \"$message\")" >&2
        echo "$output" >&2
        failures=$((failures + 1))
    else
        echo "core dependency guard self-test: ok: $description ($want)"
    fi
}
check_tools 6.9.0 pass
check_tools 7.0.0 fail "FAIL: the package's tools version is 7.0.0. This guard vouches only for 6.x"
check_tools 10.0.0 fail "FAIL: the package's tools version is 10.0.0. This guard vouches only for 6.x"

expect fail "a binary target named SpeakboardCore" \
    '.binaryTarget(name: "SpeakboardCore", url: "https://example.invalid/core.zip", checksum: "'"$(printf '0%.0s' {1..64})"'")' \
    "FAIL: the SpeakboardCore target is of type \`binary\`"
expect fail "another target in the SpeakboardCore product" \
    '.target(name: "SpeakboardCore"), .target(name: "Net")' "FAIL: the SpeakboardCore product holds targets" \
    '.library(name: "SpeakboardCore", targets: ["SpeakboardCore", "Net"])'
expect fail "no SpeakboardCore product" '.target(name: "SpeakboardCore")' \
    "FAIL: Package.swift has no SpeakboardCore product" ''

rm -rf "$work"

if [ "$failures" -ne 0 ]; then
    echo "core dependency guard self-test: FAIL ($failures wrong)" >&2
    exit 1
fi
echo "core dependency guard self-test: OK"
