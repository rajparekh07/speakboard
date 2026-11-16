#!/usr/bin/env bash
# Proves the core imports guard works: it must pass on Foundation-only code and
# on code that only looks like an import, and fail on each way of importing
# another module, naming that module. It must also fail closed when the
# compiler frontend is missing, fails, or writes nothing. Each failing case
# must fail with its own message, so a case cannot pass by failing for another
# reason. Runs on throwaway folders outside Sources/. Runs inside the Swift
# image.
set -euo pipefail

guard="$(cd "$(dirname "$0")" && pwd)/core-imports-guard.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0

# expect pass <description> <swift source>
# expect fail <description> <swift source> <text the failure message must contain>
expect() {
    local want="$1" description="$2" source="$3" message="${4:-}"
    local dir="$work/case$RANDOM$RANDOM"
    mkdir -p "$dir/Area"
    printf '%s\n' "$source" > "$dir/Area/Case.swift"
    check "$want" "$description" "$message" "$guard" "$dir"
}

# check pass|fail <description> <message> <command...>
check() {
    local want="$1" description="$2" message="$3"
    shift 3
    local output got
    if output=$("$@" 2>&1); then got=pass; else got=fail; fi
    if [ "$got" != "$want" ]; then
        echo "core imports guard self-test: WRONG: $description (wanted $want, got $got)" >&2
        echo "$output" >&2
        failures=$((failures + 1))
    elif [ "$want" = fail ] && ! grep -qF -- "$message" <<< "$output"; then
        echo "core imports guard self-test: WRONG: $description (failed, but not with \"$message\")" >&2
        echo "$output" >&2
        failures=$((failures + 1))
    else
        echo "core imports guard self-test: ok: $description ($want)"
    fi
}

dispatch="Case.swift imports Dispatch"

expect pass "Foundation only" 'import Foundation

public struct X {}'
expect pass "no import" 'let x = 1'
expect pass "a regex holding a quote, then a string holding import" 'import Foundation

func quotes(_ s: String) -> Int { s.matches(of: /"/).count }
let after = "import Fake then"'
expect pass "import as an argument and tuple label" 'import Foundation

func load(import data: Int) -> Int { data }
let loaded = load(import: 1)
let pair = (import: 1, other: 2)'
expect pass "import in comments and strings" 'import Foundation
// import Dispatch
/* /* import Dispatch */ */
let s = "import Dispatch"
let r = #"import "Dispatch""#'
# The known limit, kept here so a change in it is noticed: an import in a branch
# that is inactive on Linux is not reported. macOS CI (KEY-8) must run the guard.
expect pass "an import in a branch inactive on Linux (known limit: not seen)" 'import Foundation
#if os(macOS)
import Dispatch
#endif'

expect fail "import Dispatch" 'import Dispatch' "$dispatch"
expect fail "a smart-quote regex, then import Dispatch" 'import Foundation
func smart(_ s: String) -> String { s.replacing(/["\u{201C}\u{201D}]/, with: "\u{22}") }
import Dispatch' "$dispatch"
expect fail "an @_spi import" '@_spi(Foo) import Dispatch' "$dispatch"
expect fail "an access-level import" '@preconcurrency internal import Dispatch' "$dispatch"
expect fail "a second import after ;" 'import Foundation; import Dispatch' "$dispatch"
expect fail "a backticked module" 'import `Dispatch`' "$dispatch"
expect fail "a kind import" 'import struct Dispatch.DispatchQueue' "$dispatch"
expect fail "a postfix ... on the line before" 'import Foundation
let range = 1...
import Dispatch' "$dispatch"
expect fail "an import split across lines" 'import
    Dispatch' "$dispatch"
expect fail "an import in a branch active on Linux" '#if os(Linux)
import Glibc
#endif' "Case.swift imports Glibc"
expect fail "a module that does not exist" 'import NoSuchModule' "Case.swift imports NoSuchModule"
expect fail "a file the compiler cannot parse" 'let x = (' "the compiler could not read the imports"

# Fail closed.
mkdir -p "$work/empty" "$work/good/Area"
printf 'import Foundation\n' > "$work/good/Area/Case.swift"
check fail "no Swift files" "no Swift files" "$guard" "$work/empty"
check fail "a missing folder" "folder not found" "$guard" "$work/missing"
check fail "no compiler frontend" "is not available" env SWIFT_FRONTEND="$work/no-such-frontend" "$guard" "$work/good"
printf '#!/bin/sh\nexit 0\n' > "$work/silent-frontend"
chmod +x "$work/silent-frontend"
check fail "a frontend that writes nothing" "wrote no list" env SWIFT_FRONTEND="$work/silent-frontend" \
    "$guard" "$work/good"
printf '#!/bin/sh\necho "error: unknown argument: -emit-imported-modules" >&2\nexit 1\n' > "$work/old-frontend"
chmod +x "$work/old-frontend"
check fail "a frontend that does not know the flag" "could not read the imports" \
    env SWIFT_FRONTEND="$work/old-frontend" "$guard" "$work/good"

if [ "$failures" -ne 0 ]; then
    echo "core imports guard self-test: FAIL ($failures wrong)" >&2
    exit 1
fi
echo "core imports guard self-test: OK"
