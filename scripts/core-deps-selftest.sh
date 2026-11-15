#!/usr/bin/env bash
# Proves the core dependency guard works: it must pass on a core with no
# dependencies, and fail on each way of adding one and on a core that sets
# `path`, `sources`, plugins or unsafe flags. Each failing case must fail with
# its own message, so a case cannot pass by failing for another reason. Runs on
# throwaway packages in .build, never on the real Package.swift. Runs inside the
# Swift image.
set -euo pipefail

guard="$(cd "$(dirname "$0")" && pwd)/core-deps-guard.sh"
work=".build/core-deps-selftest"
rm -rf "$work"
mkdir -p "$work"

failures=0

# expect pass <description> <targets>
# expect fail <description> <targets> <text the failure message must contain>
expect() {
    local want="$1" description="$2" targets="$3" message="${4:-}"
    local dir="$work/case$RANDOM"
    mkdir -p "$dir"
    cat > "$dir/Package.swift" <<EOF
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Case",
    dependencies: [.package(url: "https://example.invalid/net.git", from: "1.0.0")],
    targets: [$targets]
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
expect pass "a setting that is not an unsafe flag" \
    '.target(name: "SpeakboardCore", swiftSettings: [.define("SPEAKBOARD")])'
expect fail "a target in this package" \
    '.target(name: "Net"), .target(name: "SpeakboardCore", dependencies: ["Net"])' "$deps"
expect fail "a target, written as .target" \
    '.target(name: "Net"), .target(name: "SpeakboardCore", dependencies: [.target(name: "Net")])' "$deps"
expect fail "a product of another package" \
    '.target(name: "SpeakboardCore", dependencies: [.product(name: "Net", package: "net")])' "$deps"
expect fail "no SpeakboardCore target" '.target(name: "Net")' "FAIL: Package.swift has no SpeakboardCore target"
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

rm -rf "$work"

if [ "$failures" -ne 0 ]; then
    echo "core dependency guard self-test: FAIL ($failures wrong)" >&2
    exit 1
fi
echo "core dependency guard self-test: OK"
