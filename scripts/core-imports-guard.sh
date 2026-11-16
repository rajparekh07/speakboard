#!/usr/bin/env bash
# The core imports guard. Fails unless the core has no conditional compilation
# and every Swift file in it imports Foundation and nothing else (AGENTS.md,
# ADR-0005).
#
# 1. No conditional compilation. The compiler reports imports only in code it
#    compiles, and which `#if` branches it compiles depends on the platform,
#    the target and the build's defines (`swift build` adds -DSWIFT_PACKAGE
#    -DDEBUG; Package.swift can add more). So an import inside any `#if` branch
#    could be missed here, on any host. The core therefore has no `#if` at
#    all: with no branch, the compiler sees every import, and step 2 has no
#    blind spot. Apple-only code belongs under Apple/ (ADR-0005). Allowing a
#    condition in the core means changing this guard to check every branch,
#    and AGENTS.md, on purpose.
#
#    This step reads the text, conservatively: it fails on `#if`, `#elseif`,
#    `#else` or `#endif` anywhere in a file, in code, comments or strings
#    alike. An `#if` spelled inside a comment or a string also fails, on
#    purpose: a false hit is a loud failure, never a silent pass. What the
#    pinned Swift 6.4.2 frontend honours, checked with -emit-imported-modules
#    with and without -D DEBUG:
#    - `#if` is honoured at the start of a line, indented by spaces or a tab,
#      after a UTF-8 BOM, after a `;` or `{` on the same line, after a CR line
#      ending, as `#if(DEBUG)`, and as a postfix `#if` before `.member`.
#    - After any other token on the line it is a parse error, which fails step
#      2 anyway; it is still matched here.
#    - `# if`, `#/**/if`, `#` then a line break then `if`, and `#If` are not
#      directives: each is a parse error.
#    - `#elseif`, `#else` and `#endif` without an `#if` are parse errors.
#    - A UTF-16 file is rejected ("input files must be encoded as UTF-8").
#    So every directive the compiler honours contains the bytes `#if` (or
#    follows one), and a byte search for them cannot miss one.
#
# 2. Imports. It asks the compiler which modules each file imports
#    (`swift-frontend -emit-imported-modules`), so every spelling the compiler
#    accepts is seen as the compiler sees it: attributes, access levels, `;`,
#    backticks, regex literals and comments make no difference. The frontend
#    only parses for this: it neither type-checks the file nor needs the module
#    to exist.
#
#    It reads every file as Swift 6 (`-swift-version 6`), the mode the core is
#    built in. In another mode the same text can be other code (with Swift 5
#    and custom `/` operators, a regex literal here can be an import there), so
#    the core dependency guard fails if the package could build the core in any
#    other mode (KEY-56).
#
#    Allowed modules: Foundation only. The output lists only the file's own
#    import declarations: for a file with no import it is empty (checked with
#    the pinned Swift 6.4.2: no implicit module such as Swift or _Concurrency
#    is listed), so nothing else needs allowing.
#
# It fails closed: if `find` fails, or the frontend is missing, exits non-zero
# (for example on a syntax error, or a toolchain that no longer knows the flag)
# or writes no output file, the guard fails. Its self-test also proves the frontend still
# reports a real import, so a toolchain that writes an empty file always fails
# there.
#
# It follows symbolic links, as SwiftPM does, and fails if `find` fails. On a
# symbolic link loop the two finds differ, as observed: GNU find -L (Linux, the
# Swift image) reports the loop and exits 1, so the guard fails; macOS's find
# -L (macOS 27.0.1) skips the looping link silently, lists each file once and
# exits 0, so the guard reads every file and judges them. Either way no file is
# hidden. Any file name works, newlines included.
# Runs inside the Swift image (make guard-imports), or natively with
# SWIFT_FRONTEND set by make check-native. Written for bash 3.2 and BSD tools
# (macOS) as well as Linux.
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

if ! find -L "$folder" -name '*.swift' -type f -print0 > "$work/files" 2> "$work/find.txt"; then
    echo "core imports guard: FAIL: could not list the Swift files in $folder:" >&2
    head -n 20 "$work/find.txt" >&2
    exit 1
fi
sort -z "$work/files" > "$work/sorted"
# Not mapfile: macOS's bash 3.2 has none. read -d '' reads up to each NUL.
files=()
while IFS= read -r -d '' file; do
    files+=("$file")
done < "$work/sorted"
[ "${#files[@]}" -gt 0 ] || fail "no Swift files in $folder"

# 1. No conditional compilation.
directives=0
for file in "${files[@]}"; do
    status=0
    matches=$(grep -anE '#(if|elseif|else|endif)' -- "$file") || status=$?
    if [ "$status" -eq 0 ]; then
        while IFS= read -r match; do
            echo "core imports guard: FAIL: $file:${match%%:*}: conditional compilation: ${match#*:}" >&2
            directives=$((directives + 1))
        done <<< "$matches"
    elif [ "$status" -ne 1 ]; then
        fail "could not read $file"
    fi
done
if [ "$directives" -ne 0 ]; then
    echo "The core has no conditional compilation (AGENTS.md): the imports guard cannot see into a branch the" >&2
    echo "compiler skips. Move Apple-only code under Apple/. Allowing a condition in the core means changing" >&2
    echo "scripts/core-imports-guard.sh to check every branch, and AGENTS.md." >&2
    exit 1
fi

# 2. Imports.

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
echo "core imports guard: OK (${#files[@]} files in $folder: no conditional compilation; they import Foundation or nothing)"
