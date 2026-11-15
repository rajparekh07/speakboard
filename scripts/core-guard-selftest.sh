#!/usr/bin/env bash
# Proves the core guard works: it must pass on clean code and fail on each
# forbidden form. Runs on throwaway folders, never on the real core.
set -euo pipefail

guard="$(cd "$(dirname "$0")" && pwd)/core-guard.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0

expect() {  # expect pass|fail <description> <swift source>
    local want="$1" description="$2" source="$3"
    local dir="$work/case$RANDOM"
    mkdir -p "$dir/Area"
    printf '%s\n' "$source" > "$dir/Area/Case.swift"
    if "$guard" "$dir" > /dev/null 2>&1; then got=pass; else got=fail; fi
    if [ "$got" = "$want" ]; then
        echo "core guard self-test: ok: $description ($want)"
    else
        echo "core guard self-test: WRONG: $description (wanted $want, got $got)" >&2
        failures=$((failures + 1))
    fi
}

expect pass "Foundation only" 'import Foundation'
expect pass "a longer name is not a match" 'let mySessionURLSessionless = 1'
expect fail "plain import" 'import FoundationNetworking'
expect fail "preconcurrency import" '@preconcurrency import FoundationNetworking'
expect fail "scoped import" 'import struct FoundationNetworking.URLRequest'
expect fail "conditional import" '#if canImport(FoundationNetworking)
#endif'
expect fail "URLSession use" 'let session = URLSession.shared'
expect fail "qualified URLSession" 'let session = Foundation.URLSession.shared'
expect fail "a URLSession type" 'let configuration = URLSessionConfiguration.default'

if "$guard" "$work/missing" > /dev/null 2>&1; then
    echo "core guard self-test: WRONG: a missing folder passed" >&2
    failures=$((failures + 1))
else
    echo "core guard self-test: ok: a missing folder (fail)"
fi

if [ "$failures" -ne 0 ]; then
    echo "core guard self-test: FAIL ($failures wrong)" >&2
    exit 1
fi
echo "core guard self-test: OK"
