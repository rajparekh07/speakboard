#!/usr/bin/env bash
# The tools the native path needs (make check-native: the checks without
# Docker, with the active Swift toolchain, on a Mac or on any host with Swift
# installed).
#
#   scripts/native-tools.sh check      fails, naming the tool, unless every tool
#                                      the native path uses is there; then
#                                      prints the bash, Swift and frontend in use
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

check() {
    local tool developer version path
    # What the scripts make check-native runs call, besides bash's builtins.
    for tool in swift grep find sort sed mktemp cut diff head tr cat env uname; do
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
    version=$(swift --version 2>&1 | grep -m 1 'Swift version') || fail "\`swift --version\` names no Swift version"
    swift format --version > /dev/null 2>&1 || fail "\`swift format\` is not available"
    path=$(frontend) || exit 1
    echo "native tools: OK (bash $BASH_VERSION; $version; frontend $path)"
}

case "${1:-}" in
    check) check ;;
    frontend) frontend ;;
    *)
        echo "usage: scripts/native-tools.sh check|frontend" >&2
        exit 2
        ;;
esac
