#!/usr/bin/env bash
# The tools the native path needs (make check-native: the checks without
# Docker, with the active Swift toolchain, on a Mac or on any host with Swift
# installed).
#
#   scripts/native-tools.sh check <pinned Swift version>
#                                      fails, naming the tool, unless every tool
#                                      the native path uses is there, and fails
#                                      unless the active Swift is the pinned
#                                      version (the Makefile passes it, from
#                                      SWIFT_TAG); then prints the bash, Swift
#                                      and frontend in use
#   scripts/native-tools.sh frontend   prints the path of the compiler frontend
#                                      the core imports guard runs
#
# On macOS the frontend is not on PATH: it is in the active developer directory,
# where `xcrun -f swift-frontend` finds it. Elsewhere it is `swift-frontend` on
# PATH. It fails closed: a missing tool is a failure with a message, never a
# skip.
#
# On macOS the active developer directory must be Xcode's. With only the
# Command Line Tools (Swift 6.3.3 on 16 Nov 2026), the tests fail to compile
# with "no such module 'Testing'".
#
# Written for bash 3.2 and BSD tools (macOS) as well as Linux.
set -euo pipefail

fail() {
    echo "native tools: FAIL: $1" >&2
    exit 1
}

frontend() {
    local path
    if [ "$(uname -s)" = Darwin ]; then
        command -v xcrun > /dev/null 2>&1 || fail "xcrun is not available. Install Xcode and select it with xcode-select"
        path=$(xcrun -f swift-frontend 2> /dev/null) \
            || fail "\`xcrun -f swift-frontend\` found no compiler frontend in the active developer directory"
    else
        path=$(command -v swift-frontend 2> /dev/null) || fail "the compiler frontend \`swift-frontend\` is not on PATH"
    fi
    [ -n "$path" ] && [ -x "$path" ] || fail "the compiler frontend \`$path\` is not an executable file"
    printf '%s\n' "$path"
}

# Prints the Swift version a `--version` output names, or nothing if it names
# none or is ambiguous. "Swift version 6.4.2 (swift-6.4.2-RELEASE)" on Linux and
# "Apple Swift version 6.4.2 (swiftlang-...)" on macOS give 6.4.2. The number
# must be followed by a space or the end of the line, so 6.4.2-dev, 6.4.2+asserts
# and 6.4.2abc give nothing, and a line naming "Swift version" twice gives
# nothing rather than the last one.
swift_version() {
    local line
    line=$(printf '%s\n' "$1" | grep -m 1 'Swift version') || return 0
    if [ "$(printf '%s\n' "$line" | grep -o 'Swift version' | wc -l | tr -d ' ')" != 1 ]; then
        return 0
    fi
    printf '%s\n' "$line" | sed -n 's/.*Swift version \([0-9][0-9.]*\)\( .*\)\{0,1\}$/\1/p'
}

# Fails unless the version in the --version output $2 of $1 (a name, for the
# message) is the pinned $3.
require_pinned() {
    local what="$1" output="$2" pinned="$3" active line
    active=$(swift_version "$output")
    line=$(printf '%s\n' "$output" | grep -m 1 'Swift version' || true)
    if [ "$active" != "$pinned" ]; then
        local found
        if [ -n "$active" ]; then
            found="Swift $active"
        else
            found="not a plain Swift version"
        fi
        echo "native tools: FAIL: $what is $found (${line:-no version line}), but the Makefile pins $pinned." >&2
        echo "Several of the guards' facts were checked with the pinned version. Select a toolchain with Swift $pinned," >&2
        echo "or change the pin, which is in one place: SWIFT_TAG in the Makefile, in its own commit." >&2
        exit 1
    fi
}

check() {
    local pinned="$1" tool developer path
    # What the scripts make check-native runs call, besides bash's builtins.
    for tool in swift grep find sort sed mktemp cut diff head tr cat env uname od wc; do
        command -v "$tool" > /dev/null 2>&1 || fail "\`$tool\` is not available"
    done
    if ! command -v sha256sum > /dev/null 2>&1 && ! command -v shasum > /dev/null 2>&1; then
        fail "neither \`sha256sum\` nor \`shasum\` is available (scripts/metrics.sh needs one)"
    fi
    if [ "$(uname -s)" = Darwin ]; then
        if [ -n "${DEVELOPER_DIR:-}" ]; then
            developer="$DEVELOPER_DIR"
        else
            developer=$(xcode-select -p 2> /dev/null) || fail "\`xcode-select -p\` names no active developer directory"
        fi
        case "$developer" in
            *CommandLineTools*)
                echo "native tools: FAIL: the active developer directory is the Command Line Tools ($developer)." >&2
                echo "The tests need Xcode's toolchain (without it: no such module 'Testing'). Select Xcode:" >&2
                echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
                exit 1
                ;;
        esac
    fi
    require_pinned "the active Swift" "$(swift --version 2>&1 || true)" "$pinned"
    swift format --version > /dev/null 2>&1 || fail "\`swift format\` is not available"
    path=$(frontend) || exit 1
    # The core imports guard runs this frontend, which xcrun can find in another toolchain than `swift`'s.
    require_pinned "the compiler frontend ($path)" "$("$path" --version 2>&1 || true)" "$pinned"
    echo "native tools: OK (bash $BASH_VERSION; Swift $pinned, as pinned, for swift and the frontend; frontend $path)"
}

case "${1:-}" in
    check)
        [ -n "${2:-}" ] || fail "usage: scripts/native-tools.sh check <pinned Swift version>"
        check "$2"
        ;;
    frontend) frontend ;;
    *)
        echo "usage: scripts/native-tools.sh check <pinned Swift version> | frontend" >&2
        exit 2
        ;;
esac
