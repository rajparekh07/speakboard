#!/usr/bin/env bash
# Proves the core dependency guard works: it must pass on a core with no
# dependencies and fail on each way of adding one. Runs on throwaway packages
# in .build, never on the real Package.swift. Runs inside the Swift image.
set -euo pipefail

guard="$(cd "$(dirname "$0")" && pwd)/core-deps-guard.sh"
work=".build/core-deps-selftest"
rm -rf "$work"
mkdir -p "$work"

failures=0

expect() {  # expect pass|fail <description> <targets>
    local want="$1" description="$2" targets="$3"
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
    if "$guard" "$dir" > /dev/null 2>&1; then got=pass; else got=fail; fi
    if [ "$got" = "$want" ]; then
        echo "core dependency guard self-test: ok: $description ($want)"
    else
        echo "core dependency guard self-test: WRONG: $description (wanted $want, got $got)" >&2
        failures=$((failures + 1))
    fi
}

expect pass "no dependencies" '.target(name: "SpeakboardCore"), .target(name: "Net")'
expect fail "a target in this package" '.target(name: "Net"), .target(name: "SpeakboardCore", dependencies: ["Net"])'
expect fail "a target, written as .target" \
    '.target(name: "Net"), .target(name: "SpeakboardCore", dependencies: [.target(name: "Net")])'
expect fail "a product of another package" \
    '.target(name: "SpeakboardCore", dependencies: [.product(name: "Net", package: "net")])'
expect fail "no SpeakboardCore target" '.target(name: "Net")'

rm -rf "$work"

if [ "$failures" -ne 0 ]; then
    echo "core dependency guard self-test: FAIL ($failures wrong)" >&2
    exit 1
fi
echo "core dependency guard self-test: OK"
