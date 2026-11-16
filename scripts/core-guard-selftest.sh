#!/usr/bin/env bash
# Proves the core guard works: it must pass on clean code and fail on each
# forbidden form. Runs on throwaway folders, never on the real core.
set -euo pipefail

guard="$(cd "$(dirname "$0")" && pwd)/core-guard.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0

report() {  # report pass|fail <description> <folder to guard>
    local want="$1" description="$2" folder="$3"
    if "$guard" "$folder" > /dev/null 2>&1; then got=pass; else got=fail; fi
    if [ "$got" = "$want" ]; then
        echo "core guard self-test: ok: $description ($want)"
    else
        echo "core guard self-test: WRONG: $description (wanted $want, got $got)" >&2
        failures=$((failures + 1))
    fi
}

expect() {  # expect pass|fail <description> <swift source>
    local dir="$work/case$RANDOM"
    mkdir -p "$dir/Area"
    printf '%s\n' "$3" > "$dir/Area/Case.swift"
    report "$1" "$2" "$dir"
}

expect pass "Foundation only" 'import Foundation'
expect pass "a longer name is not a match" 'let mySessionURLSessionless = 1'
expect fail "plain import" 'import FoundationNetworking'
expect fail "preconcurrency import" '@preconcurrency import FoundationNetworking'
expect fail "scoped import" 'import struct FoundationNetworking.URLRequest'
expect fail "access-level import" 'internal import FoundationNetworking'
expect fail "public import" 'public import FoundationNetworking'
expect fail "conditional import" '#if canImport(FoundationNetworking)
#endif'
expect fail "URLSession use" 'let session = URLSession.shared'
expect fail "qualified URLSession" 'let session = Foundation.URLSession.shared'
expect fail "a URLSession type" 'let configuration = URLSessionConfiguration.default'

# A forbidden file outside the core, linked into it. SwiftPM compiles it.
mkdir -p "$work/outside/Shared" "$work/linked-file/Area"
printf 'import FoundationNetworking\n' > "$work/outside/Shared/Net.swift"
ln -s "$work/outside/Shared/Net.swift" "$work/linked-file/Area/Net.swift"
report fail "a symlinked file" "$work/linked-file"

mkdir -p "$work/linked-folder"
ln -s "$work/outside/Shared" "$work/linked-folder/Area"
report fail "a symlinked folder" "$work/linked-folder"

mkdir -p "$work/dangling/Area"
ln -s "$work/does-not-exist.swift" "$work/dangling/Area/Gone.swift"
report fail "a link that points nowhere" "$work/dangling"

report fail "a missing folder" "$work/missing"

if [ "$failures" -ne 0 ]; then
    echo "core guard self-test: FAIL ($failures wrong)" >&2
    exit 1
fi
echo "core guard self-test: OK"
