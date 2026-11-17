#!/bin/bash
# The keyboard extension guard (KEY-8). What it enforces, where, and what it
# does not:
#
#   scripts/extension-guard.sh sources [<folder>...]
#       default folders: Apple/Keyboard Apple/KeyboardKit. Runs in make check
#       (the Swift image) and make check-native, on every push (rungs 1 to 3).
#   scripts/extension-guard.sh project <project.yml>
#       macOS CI only: needs XcodeGen.
#   scripts/extension-guard.sh binary <SpeakboardKeyboard.appex>
#       macOS CI only: needs the built extension.
#
# sources: for the extension's own folder and KeyboardKit's (the code linked
# into the extension; the core it links is held to Foundation by the core
# guards), it fails:
#   1. on any file that is not a Swift file, except an Info.plist: the targets
#      compile every source file in their folders, so an Objective-C or C file
#      could import anything, and only Swift files are read below;
#   2. on conditional compilation (`#if`, `#elseif`, `#else`, `#endif`), read
#      as text, as the core imports guard does and for the same reason: the
#      compiler reports imports only in branches it compiles, so an import in
#      an inactive branch would go unseen. The extension has no branches;
#   3. on any import of a module outside the allowlist below, as the compiler
#      reads the imports (`swift-frontend -emit-imported-modules`, Swift 6), so
#      every spelling counts: `import struct SwiftUI.Text`, an import split
#      across lines or around a comment, attributes, access levels. The
#      frontend only parses for this, so it works in the Linux image too,
#      without UIKit or SwiftUI present. It fails closed as the core imports
#      guard does: a failing find, a missing frontend, a non-zero exit or no
#      output file fails it;
#   4. as a second net, not a proof, on networking names in the text:
#      URLSession and its relatives, Network.framework types, CFNetwork and
#      Foundation streams, `contentsOf:` (Data and String read URLs), and BSD
#      socket calls. A name can be reached in ways no text scan sees.
#
# What no part of this guard can see: networking through what the allowlist
# already lets in. Foundation (and UIKit, which re-exports it) carries
# URLSession, Data(contentsOf:) with a URL and Stream; libSystem carries BSD
# sockets. Code that uses them imports nothing new and links nothing new, so
# neither step 3 nor `otool -L` finds it; only step 4's names, as text, might.
# The manifesto's privacy contract (no networking code in the extension, and
# the build fails if that changes) needs a stronger gate: that is KEY-11
# ("Privacy gate: no networking code in the keyboard extension"), its own
# ticket.
#
# project: fails unless project.yml, as XcodeGen resolves it, gives the
# extension exactly the folder Apple/Keyboard (less its Info.plist) and
# KeyboardKit exactly Apple/KeyboardKit as sources, and their dependencies are
# exactly KeyboardKit (for the extension) and the core (for KeyboardKit). So a
# new source path or dependency for either cannot go unscanned: adding one
# means changing this guard too.
#
# binary: fails if any Mach-O file inside the built .appex loads SwiftUI or a
# networking framework (Network, CFNetwork) or their Swift overlays, by
# `otool -L` (OTOOL overrides it, for the self-test). Mach-O files are found
# by their magic number, thin or universal, 32- or 64-bit. It does not follow
# libraries loaded from outside the .appex through @rpath: today the extension
# embeds none (KeyboardKit and the core are static, inside its binary), and
# the system frameworks it loads are listed by name.
#
# Written for bash 3.2 and BSD tools (macOS) as well as Linux.
set -euo pipefail

# Step 3's allowlist: the modules the extension and KeyboardKit may import,
# each for what it is used for today.
#   Foundation      UIKit re-exports it anyway; listing it lets a file import it
#                   directly. It is also where networking APIs live: see above.
#   UIKit           the input view controller and the one view (ADR-0012)
#   QuartzCore      Core Animation layers, how the view draws (ADR-0012)
#   OSLog           the extension's one log line for the CI check: unified log
#   SpeakboardCore  the core, itself Foundation only (ADR-0005)
#   KeyboardKit     the extension's own code, linked into it
# Anything else, SwiftUI, SwiftUICore, Network and FoundationNetworking
# included, fails. A new module is a change to this list, with its reason.
allowed_modules="Foundation UIKit QuartzCore OSLog SpeakboardCore KeyboardKit"

net_names='URLSession|NSURLSession|URLSessionTask|NSURLConnection|NWConnection|NWListener|NWBrowser|NWPathMonitor|NWEndpoint|CFNetwork|CFStream|CF(Read|Write)Stream|CFSocket|CFHost|getStreamsToHost|NSStream|contentsOf:|getaddrinfo|gethostbyname|(^|[^A-Za-z0-9_.])(socket|connect|sendto|recvfrom)[[:space:]]*\('
forbidden_link='/(SwiftUI|SwiftUICore|Network|CFNetwork)\.framework/|libswift(SwiftUI|SwiftUICore|Network)\.dylib'

# Each mode's scratch folder, removed on exit. Global, so the EXIT trap still
# sees it after the function that made it returns.
work=""
cleanup() {
    [ -z "$work" ] || rm -rf "$work"
}
trap cleanup EXIT

fail() {
    echo "extension guard: FAIL: $1" >&2
    exit 1
}

is_allowed() {
    local module
    for module in $allowed_modules; do
        [ "$1" = "$module" ] && return 0
    done
    return 1
}

sources() {
    local folders=("$@")
    if [ "${#folders[@]}" -eq 0 ]; then
        folders=(Apple/Keyboard Apple/KeyboardKit)
    fi
    local frontend="${SWIFT_FRONTEND:-swift-frontend}"
    command -v "$frontend" > /dev/null 2>&1 || fail "the compiler frontend \`$frontend\` is not available"

    local folder file name status matches match module out
    work=$(mktemp -d)
    : > "$work/all"
    for folder in "${folders[@]}"; do
        [ -d "$folder" ] || fail "folder not found: $folder"
        if ! find -L "$folder" -type f -print0 >> "$work/all" 2> "$work/find.txt"; then
            echo "extension guard: FAIL: could not list the files in $folder:" >&2
            head -n 20 "$work/find.txt" >&2
            exit 1
        fi
    done
    local files=() problems=0
    while IFS= read -r -d '' file; do
        name=$(basename "$file")
        case "$name" in
            *.swift) files+=("$file") ;;
            Info.plist) ;;
            *)
                echo "extension guard: FAIL: $file is not a Swift file. The extension's folders hold Swift files" >&2
                echo "  only (and an Info.plist), so that every source they compile is read by this guard." >&2
                problems=$((problems + 1))
                ;;
        esac
    done < <(sort -z "$work/all")
    [ "$problems" -eq 0 ] || exit 1
    [ "${#files[@]}" -gt 0 ] || fail "no Swift files in ${folders[*]}"

    # 2. No conditional compilation.
    for file in "${files[@]}"; do
        status=0
        matches=$(grep -anE '#(if|elseif|else|endif)' -- "$file") || status=$?
        if [ "$status" -eq 0 ]; then
            while IFS= read -r match; do
                echo "extension guard: FAIL: $file:${match%%:*}: conditional compilation: ${match#*:}" >&2
                problems=$((problems + 1))
            done <<< "$matches"
        elif [ "$status" -ne 1 ]; then
            fail "could not read $file"
        fi
    done
    if [ "$problems" -ne 0 ]; then
        echo "The keyboard extension has no conditional compilation: this guard reads imports with the compiler," >&2
        echo "which sees only the branches it compiles." >&2
        exit 1
    fi

    # 3. Imports, as the compiler reads them.
    for file in "${files[@]}"; do
        out="$work/modules.txt"
        rm -f "$out"
        if ! "$frontend" -emit-imported-modules "$file" -o "$out" -module-name ExtensionGuard -swift-version 6 \
            > "$work/log.txt" 2>&1; then
            echo "extension guard: FAIL: the compiler could not read the imports of $file:" >&2
            head -n 20 "$work/log.txt" >&2
            exit 1
        fi
        [ -f "$out" ] || fail "the compiler wrote no list of imported modules for $file"
        while IFS= read -r module; do
            [ -n "$module" ] || continue
            if ! is_allowed "$module"; then
                echo "extension guard: FAIL: $file imports $module" >&2
                problems=$((problems + 1))
            fi
        done < "$out"
    done
    if [ "$problems" -ne 0 ]; then
        echo "The keyboard extension and KeyboardKit import only: $allowed_modules (scripts/extension-guard.sh" >&2
        echo "says why each). No SwiftUI (ADR-0012), no networking (MANIFESTO.md)." >&2
        exit 1
    fi

    # 4. Networking names, as text: a second net.
    for file in "${files[@]}"; do
        status=0
        matches=$(grep -anE "$net_names" -- "$file") || status=$?
        if [ "$status" -eq 0 ]; then
            while IFS= read -r match; do
                echo "extension guard: FAIL: $file:${match%%:*}: a networking name: ${match#*:}" >&2
                problems=$((problems + 1))
            done <<< "$matches"
        elif [ "$status" -ne 1 ]; then
            fail "could not read $file"
        fi
    done
    if [ "$problems" -ne 0 ]; then
        echo "The keyboard extension contains no networking code (MANIFESTO.md). A mention in a comment fails too." >&2
        exit 1
    fi
    echo "extension guard: OK (${#files[@]} Swift files in ${folders[*]}: no other source files, no conditional" \
        "compilation, imports only from the allowlist, no networking names)"
}

project() {
    local spec="$1"
    [ -f "$spec" ] || fail "no project spec at $spec"
    command -v xcodegen > /dev/null 2>&1 || fail "xcodegen is not available"
    command -v plutil > /dev/null 2>&1 || fail "plutil is not available"
    work=$(mktemp -d)
    xcodegen dump --type json --spec "$spec" > "$work/dump.json" || fail "xcodegen could not read $spec"
    # check_key <key path> <expected JSON>. Both sides are compared as XML
    # property lists, whose dictionary keys plutil writes sorted: XcodeGen's
    # JSON lists a dictionary's keys in a different order from run to run.
    check_key() {
        local got want shown
        printf '%s' "$2" > "$work/want.json"
        want=$(plutil -convert xml1 -o - "$work/want.json") || fail "the guard's own expected value for $1 is not JSON"
        if got=$(plutil -extract "$1" xml1 -o - "$work/dump.json" 2> /dev/null); then
            shown=$(plutil -extract "$1" json -o - "$work/dump.json")
        else
            got="(missing)"
            shown="(missing)"
        fi
        if [ "$got" != "$want" ]; then
            echo "extension guard: FAIL: project.yml $1 is $shown, not $2." >&2
            echo "  The extension guard scans exactly these sources (scripts/extension-guard.sh sources); a new" >&2
            echo "  source path or dependency for the extension or KeyboardKit means changing the guard too." >&2
            exit 1
        fi
    }
    check_key targets.SpeakboardKeyboard.sources '[{"path":"Apple\/Keyboard","excludes":["Info.plist"]}]'
    check_key targets.KeyboardKit.sources '[{"path":"Apple\/KeyboardKit"}]'
    check_key targets.SpeakboardKeyboard.dependencies '[{"embed":false,"target":"KeyboardKit"}]'
    check_key targets.KeyboardKit.dependencies '[{"package":"Speakboard","product":"SpeakboardCore"}]'
    echo "extension guard: OK (project.yml: the extension's sources are Apple/Keyboard, KeyboardKit's" \
        "Apple/KeyboardKit, and their only dependencies are KeyboardKit and the core)"
}

# Whether $1 starts with a Mach-O magic number: thin 32- or 64-bit, or
# universal (FAT_MAGIC or FAT_MAGIC_64), in either byte order. Reads the bytes
# itself, so it needs no `file` command.
is_macho() {
    local magic
    magic=$(head -c 4 "$1" | od -An -tx1 | tr -d ' \n')
    case "$magic" in
        feedface | feedfacf | cefaedfe | cffaedfe | cafebabe | bebafeca | cafebabf | bfbafeca) return 0 ;;
        *) return 1 ;;
    esac
}

binary() {
    local appex=$1 otool=${OTOOL:-otool}
    [ -d "$appex" ] || fail "no extension at $appex"
    local count=0 file links
    while IFS= read -r -d '' file; do
        if ! is_macho "$file"; then
            continue
        fi
        count=$((count + 1))
        links=$("$otool" -L "$file") || fail "$otool -L failed on $file"
        if echo "$links" | grep -E "$forbidden_link" > /dev/null; then
            echo "extension guard: FAIL: $file loads SwiftUI or a networking framework:" >&2
            echo "$links" | grep -E "$forbidden_link" >&2
            exit 1
        fi
    done < <(find "$appex" -type f -print0)
    [ "$count" -gt 0 ] || fail "no Mach-O file in $appex"
    echo "extension guard: OK ($count Mach-O files in $(basename "$appex"): no SwiftUI, no networking framework)"
}

case "${1:-}" in
    sources)
        shift
        sources "$@"
        ;;
    project)
        [ "$#" -eq 2 ] || { echo "usage: $0 project <project.yml>" >&2; exit 2; }
        project "$2"
        ;;
    binary)
        [ "$#" -eq 2 ] || { echo "usage: $0 binary <SpeakboardKeyboard.appex>" >&2; exit 2; }
        binary "$2"
        ;;
    *)
        echo "usage: $0 sources [<folder>...] | project <project.yml> | binary <SpeakboardKeyboard.appex>" >&2
        exit 2
        ;;
esac
