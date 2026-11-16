#!/usr/bin/env bash
# The core imports guard. Fails unless every Swift file in the core imports
# Foundation and nothing else (AGENTS.md, ADR-0005).
#
# It does not read the source text. It asks the compiler which modules each
# file imports (`swift-frontend -emit-imported-modules`), so every spelling the
# compiler accepts is seen as the compiler sees it: attributes, access levels,
# `;`, backticks, regex literals and comments make no difference. The frontend
# only parses for this: it neither type-checks the file nor needs the module to
# exist.
#
# Allowed modules: Foundation only. The output lists only the file's own import
# declarations: for a file with no import it is empty (checked with the pinned
# Swift 6.4.2: no implicit module such as Swift or _Concurrency is listed), so
# nothing else needs allowing.
#
# It fails closed: if the frontend is missing, exits non-zero (for example on a
# syntax error, or a toolchain that no longer knows the flag) or writes no
# output file, the guard fails. Its self-test also proves the frontend still
# reports a real import, so a toolchain that writes an empty file always fails
# there.
#
# The limit: the compiler reports imports only in code it compiles. An import
# inside a conditional-compilation branch that is inactive here, on Linux (for
# example `#if os(macOS)`), is not reported (checked: `#if os(macOS)` around
# `import Dispatch` reports nothing). macOS CI (KEY-8) must run this same check
# to see those branches. The core guard's text search for FoundationNetworking
# and URLSession (scripts/core-guard.sh) does cover inactive branches.
#
# It follows symbolic links, as SwiftPM does.
# Runs inside the Swift image (make guard-imports).
#
# Usage: scripts/core-imports-guard.sh [folder]   (default: Sources/SpeakboardCore)
# SWIFT_FRONTEND overrides the frontend command (used by the self-test).
set -euo pipefail

folder="${1:-Sources/SpeakboardCore}"
frontend="${SWIFT_FRONTEND:-swift-frontend}"

fail() {
    echo "core imports guard: FAIL: $1" >&2
    exit 1
}

[ -d "$folder" ] || fail "folder not found: $folder"
command -v "$frontend" > /dev/null 2>&1 || fail "the compiler frontend \`$frontend\` is not available"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mapfile -t files < <(find -L "$folder" -name '*.swift' -type f | sort)
[ "${#files[@]}" -gt 0 ] || fail "no Swift files in $folder"

failures=0
for file in "${files[@]}"; do
    out="$work/modules.txt"
    rm -f "$out"
    if ! "$frontend" -emit-imported-modules "$file" -o "$out" -module-name CoreImportsGuard -swift-version 6 \
        > "$work/log.txt" 2>&1; then
        echo "core imports guard: FAIL: the compiler could not read the imports of $file:" >&2
        head -n 20 "$work/log.txt" >&2
        exit 1
    fi
    [ -f "$out" ] || fail "the compiler wrote no list of imported modules for $file"
    while IFS= read -r module; do
        [ -n "$module" ] || continue
        if [ "$module" != Foundation ]; then
            echo "core imports guard: FAIL: $file imports $module" >&2
            failures=$((failures + 1))
        fi
    done < "$out"
done

if [ "$failures" -ne 0 ]; then
    echo "The core imports Foundation and nothing else (AGENTS.md, ADR-0005)." >&2
    exit 1
fi
echo "core imports guard: OK (${#files[@]} files in $folder import Foundation or nothing)"
