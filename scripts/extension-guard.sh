#!/bin/bash
# The keyboard extension links no SwiftUI (ADR-0012) and contains no networking
# code (MANIFESTO.md, principle 6 and privacy contract 1). KEY-8.
#
#   scripts/extension-guard.sh sources [<folder>...]   default: Apple/Keyboard Apple/KeyboardKit
#   scripts/extension-guard.sh binary <SpeakboardKeyboard.appex>
#
# sources: fails if a Swift file in the extension's folders (the extension and
# the KeyboardKit code linked into it) imports SwiftUI, Network or
# FoundationNetworking, or names URLSession, NWConnection, NWListener,
# NWBrowser, CFStream, CFSocket or a BSD socket call. It reads the text, so a
# mention in a comment fails too, on purpose.
# binary: fails if any Mach-O file in the built extension loads SwiftUI, a
# networking framework (Network, CFNetwork) or their Swift overlays, by
# `otool -L` (OTOOL overrides it, for the self-test).
#
# Foundation itself carries URLSession, so the binary check alone cannot prove
# the extension makes no network call; the source check is what catches one.
# It is a guard for this ticket's shell, not the full privacy check the
# manifesto asks for.
set -euo pipefail

forbidden_source='(^|[^A-Za-z0-9_])(import[[:space:]]+(SwiftUI|Network|FoundationNetworking)([^A-Za-z0-9_]|$)|URLSession|NWConnection|NWListener|NWBrowser|CFStream|CFSocket|getaddrinfo|socket\()'
forbidden_link='/(SwiftUI|SwiftUICore|Network|CFNetwork)\.framework/|libswift(SwiftUI|Network)\.dylib'

sources() {
    local folders=("$@")
    if [ "${#folders[@]}" -eq 0 ]; then
        folders=(Apple/Keyboard Apple/KeyboardKit)
    fi
    local folder list file out status count=0 hits=""
    list=$(mktemp)
    for folder in "${folders[@]}"; do
        if [ ! -d "$folder" ]; then
            echo "extension guard: FAIL: no folder $folder" >&2
            rm -f "$list"
            return 1
        fi
        if ! find "$folder" -name '*.swift' -type f -print0 >> "$list"; then
            echo "extension guard: FAIL: could not list the Swift files in $folder" >&2
            rm -f "$list"
            return 1
        fi
    done
    while IFS= read -r -d '' file; do
        count=$((count + 1))
        status=0
        out=$(grep -nE "$forbidden_source" "$file") || status=$?
        case "$status" in
            0) hits="$hits$file: $out"$'\n' ;;
            1) ;;
            *)
                echo "extension guard: FAIL: grep could not read $file" >&2
                rm -f "$list"
                return 1
                ;;
        esac
    done < "$list"
    rm -f "$list"
    if [ "$count" -eq 0 ]; then
        echo "extension guard: FAIL: no Swift files in ${folders[*]}" >&2
        return 1
    fi
    if [ -n "$hits" ]; then
        echo "extension guard: FAIL: SwiftUI or networking in the keyboard extension's sources:" >&2
        printf '%s' "$hits" >&2
        echo "The extension links no SwiftUI (ADR-0012) and contains no networking code (MANIFESTO.md)." >&2
        return 1
    fi
    echo "extension guard: OK ($count files in ${folders[*]}: no SwiftUI, no networking)"
}

# Whether $1 starts with a Mach-O magic number (thin 32- or 64-bit, either byte
# order, or universal). Reads the bytes itself, so it needs no `file` command.
is_macho() {
    local magic
    magic=$(head -c 4 "$1" | od -An -tx1 | tr -d ' \n')
    case "$magic" in
        feedface | feedfacf | cefaedfe | cffaedfe | cafebabe | bebafeca) return 0 ;;
        *) return 1 ;;
    esac
}

binary() {
    local appex=$1 otool=${OTOOL:-otool}
    if [ ! -d "$appex" ]; then
        echo "extension guard: FAIL: no extension at $appex" >&2
        return 1
    fi
    local count=0 file links
    while IFS= read -r -d '' file; do
        if ! is_macho "$file"; then
            continue
        fi
        count=$((count + 1))
        if ! links=$("$otool" -L "$file"); then
            echo "extension guard: FAIL: $otool -L failed on $file" >&2
            return 1
        fi
        if echo "$links" | grep -E "$forbidden_link" > /dev/null; then
            echo "extension guard: FAIL: $file loads SwiftUI or a networking framework:" >&2
            echo "$links" | grep -E "$forbidden_link" >&2
            return 1
        fi
    done < <(find "$appex" -type f -print0)
    if [ "$count" -eq 0 ]; then
        echo "extension guard: FAIL: no Mach-O file in $appex" >&2
        return 1
    fi
    echo "extension guard: OK ($count Mach-O files in $(basename "$appex"): no SwiftUI, no networking framework)"
}

case "${1:-}" in
    sources)
        shift
        sources "$@"
        ;;
    binary)
        [ "$#" -eq 2 ] || { echo "usage: $0 binary <SpeakboardKeyboard.appex>" >&2; exit 2; }
        binary "$2"
        ;;
    *)
        echo "usage: $0 sources [<folder>...] | binary <SpeakboardKeyboard.appex>" >&2
        exit 2
        ;;
esac
