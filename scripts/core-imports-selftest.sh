#!/usr/bin/env bash
# Proves the core imports guard works: it must pass on Foundation-only code and
# on code that only looks like an import or a directive, fail on every
# conditional-compilation directive the compiler honours, and fail on each way
# of importing another module, naming that module. It must also fail closed when
# grep cannot read a file, and when the compiler frontend is missing, fails, or
# writes nothing. Each failing case
# must fail with its own message, so a case cannot pass by failing for another
# reason. Runs on throwaway folders outside Sources/. Runs inside the Swift
# image, or natively (make check-native).
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
expect pass "other uses of #: raw strings, regex literals, #file, #selector-like macros" 'import Foundation

let raw = #"say "hi" #ok"#
let regex = #/a#b/#
let file = #file
let line = #line
let column = #column
let function = #function'

# Conditional compilation: every spelling the compiler honours must fail.
cond="conditional compilation"
expect fail "#if os(macOS) around an import (inactive on Linux)" 'import Foundation
#if os(macOS)
import Dispatch
#endif' "Case.swift:2: $cond"
expect fail "#if DEBUG around an import (active in swift build)" 'import Foundation
#if DEBUG
import RegexBuilder
func debugRegex() -> Regex<Substring> { Regex { "a" } }
#endif' "Case.swift:2: $cond"
expect fail "#if SWIFT_PACKAGE" '#if SWIFT_PACKAGE
import Dispatch
#endif' "Case.swift:1: $cond"
expect fail "#if canImport(UIKit)" '#if canImport(UIKit)
import UIKit
#endif' "Case.swift:1: $cond"
expect fail "#if os(iOS)" '#if os(iOS)
import UIKit
#endif' "Case.swift:1: $cond"
expect fail "an #if with no import in it" 'import Foundation
#if DEBUG
let debug = true
#else
let debug = false
#endif' "Case.swift:2: $cond"
expect fail "an indented #if" 'struct S {
    #if DEBUG
    let x = 1
    #endif
}' "Case.swift:2: $cond"
expect fail "a tab-indented #if" "$(printf '\t#if DEBUG\nimport Dispatch\n#endif')" "Case.swift:1: $cond"
expect fail "an #if after ; on the same line" 'let x = 1; #if DEBUG
import Dispatch
#endif' "Case.swift:1: $cond"
expect fail "an #if after { on the same line" 'func f() { #if DEBUG
    _ = 1
    #endif
}' "Case.swift:1: $cond"
expect fail "#if(DEBUG) with no space" '#if(DEBUG)
import Dispatch
#endif' "Case.swift:1: $cond"
expect fail "a postfix #if before .member" 'let s = [1].count
    #if DEBUG
    .description
    #endif' "Case.swift:2: $cond"
expect fail "an #if after a BOM" "$(printf '\xef\xbb\xbf#if DEBUG\nimport Dispatch\n#endif')" "Case.swift:1: $cond"
expect fail "an #if after a CR line ending" "$(printf 'let x = 1\r#if DEBUG\r\nimport Dispatch\r#endif')" \
    "Case.swift:1: $cond"
expect fail "an #if in a comment (a false hit, on purpose)" 'import Foundation
// #if DEBUG' "Case.swift:2: $cond"

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
expect fail "#if os(Linux) around an import (active on Linux)" '#if os(Linux)
import Glibc
#endif' "Case.swift:1: $cond"
expect fail "a module that does not exist" 'import NoSuchModule' "Case.swift imports NoSuchModule"
expect fail "a file the compiler cannot parse" 'let x = (' "the compiler could not read the imports"

# More than one file: each is read, not only the last one listed. A.swift sorts first and imports Dispatch.
mkdir -p "$work/two/Area"
printf 'import Dispatch\n' > "$work/two/Area/A.swift"
printf 'import Foundation\n' > "$work/two/Area/B.swift"
check fail "two files, the first importing Dispatch" "A.swift imports Dispatch" "$guard" "$work/two"
# The mirror: B.swift sorts last and imports Dispatch, so a guard that reads only the first file fails here.
mkdir -p "$work/two-last/Area"
printf 'import Foundation\n' > "$work/two-last/Area/A.swift"
printf 'import Dispatch\n' > "$work/two-last/Area/B.swift"
check fail "two files, the last importing Dispatch" "B.swift imports Dispatch" "$guard" "$work/two-last"

# Fail closed.
mkdir -p "$work/empty" "$work/good/Area"
printf 'import Foundation\n' > "$work/good/Area/Case.swift"
check fail "no Swift files" "no Swift files" "$guard" "$work/empty"
check fail "a missing folder" "folder not found" "$guard" "$work/missing"
# find fails (exit 1, a message on stderr). A fake find on PATH, as for grep below, so the case does not depend on
# what the platform's find does with any particular tree.
mkdir -p "$work/broken-find"
printf '#!/bin/sh\necho "find: read error" >&2\nexit 1\n' > "$work/broken-find/find"
chmod +x "$work/broken-find/find"
check fail "find fails" "could not list the Swift files in $work/good" \
    env PATH="$work/broken-find:$PATH" "$guard" "$work/good"

# A symbolic link loop. GNU find -L reports it and exits 1, so the guard fails with "could not list the Swift
# files". macOS's find -L skips the looping link silently, lists each file once and exits 0, so the guard reads
# the files. Either way a loop must not hide a file, nor make the guard hang or read a file twice:
# - beside a loop, a file that imports Dispatch fails the guard, by either path;
# - beside a loop, a clean file either fails the guard with "could not list" or passes with exactly 1 file read.
mkdir -p "$work/loop-dispatch/Area" "$work/loop-clean/Area"
printf 'import Dispatch\n' > "$work/loop-dispatch/Area/Case.swift"
ln -s .. "$work/loop-dispatch/Area/Loop"
printf 'import Foundation\n' > "$work/loop-clean/Area/Case.swift"
ln -s .. "$work/loop-clean/Area/Loop"
loop_case() {  # loop_case <description> <folder> <text a pass must contain, or "" if it must fail> <failure text>...
    local description="$1" folder="$2" passing="$3" output wanted message
    shift 3
    if output=$("$guard" "$folder" 2>&1); then
        if [ -n "$passing" ] && grep -qF -- "$passing" <<< "$output"; then
            echo "core imports guard self-test: ok: $description (pass: $passing)"
            return
        fi
        wanted="${passing:+pass with \"$passing\", or }fail"
    else
        for message in "$@"; do
            if grep -qF -- "$message" <<< "$output"; then
                echo "core imports guard self-test: ok: $description (fail: $message)"
                return
            fi
        done
        wanted="fail with one of:"
        for message in "$@"; do wanted="$wanted \"$message\""; done
    fi
    echo "core imports guard self-test: WRONG: $description (wanted $wanted)" >&2
    echo "$output" >&2
    failures=$((failures + 1))
}
loop_case "a symbolic link loop beside a file importing Dispatch" "$work/loop-dispatch" "" \
    "could not list the Swift files" "Case.swift imports Dispatch"
loop_case "a symbolic link loop beside a clean file" "$work/loop-clean" "(1 files in $work/loop-clean:" \
    "could not list the Swift files"
mkdir -p "$work/newline/Area"
printf 'import Dispatch\n' > "$work/newline/Area/Odd
name.swift"
check fail "a file name with a newline, importing Dispatch" "name.swift imports Dispatch" "$guard" "$work/newline"
# A grep that cannot read the file (status 2). chmod 000 would not do: the
# container may run as root, which reads the file anyway.
mkdir -p "$work/broken-grep"
printf '#!/bin/sh\necho "grep: read error" >&2\nexit 2\n' > "$work/broken-grep/grep"
chmod +x "$work/broken-grep/grep"
check fail "grep fails to read a file (status 2)" "FAIL: could not read $work/good/Area/Case.swift" \
    env PATH="$work/broken-grep:$PATH" "$guard" "$work/good"
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
