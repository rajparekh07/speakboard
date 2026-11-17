#!/bin/bash
# Self-test of scripts/extension-guard.sh: each case must pass or fail as
# stated, so a broken guard cannot pass silently. The binary cases use a
# stand-in otool, so they run on any host.
set -euo pipefail

guard="$(cd "$(dirname "$0")" && pwd)/extension-guard.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
wrong=0

# check <pass|fail> <name> <command...>
check() {
    local want=$1 name=$2
    shift 2
    local got=pass
    "$@" > "$work/out.txt" 2>&1 || got=fail
    if [ "$got" = "$want" ]; then
        echo "extension guard self-test: ok: $name ($want)"
    else
        echo "extension guard self-test: WRONG: $name (wanted $want, got $got)"
        sed 's/^/    /' "$work/out.txt"
        wrong=$((wrong + 1))
    fi
}

# source <case> <content>: a folder with one Swift file.
source_case() {
    mkdir -p "$work/$1"
    printf '%s\n' "$2" > "$work/$1/X.swift"
}

source_case clean 'import UIKit
import QuartzCore
let networkingIsElsewhere = true'
check pass "UIKit and Core Animation only" "$guard" sources "$work/clean"
source_case swiftui 'import SwiftUI'
check fail "import SwiftUI" "$guard" sources "$work/swiftui"
source_case swiftui-attr '@preconcurrency import SwiftUI'
check fail "an attributed import of SwiftUI" "$guard" sources "$work/swiftui-attr"
source_case network 'import Network'
check fail "import Network" "$guard" sources "$work/network"
source_case networking 'import FoundationNetworking'
check fail "import FoundationNetworking" "$guard" sources "$work/networking"
source_case session 'let s = URLSession.shared'
check fail "URLSession" "$guard" sources "$work/session"
source_case nw 'let c = NWConnection(host: "x", port: 1, using: .tcp)'
check fail "NWConnection" "$guard" sources "$work/nw"
source_case socket 'let fd = socket(AF_INET, SOCK_STREAM, 0)'
check fail "a BSD socket" "$guard" sources "$work/socket"
source_case networkish 'import NetworkExtensionLike
let networkCount = 1'
check pass "a longer name is not a match" "$guard" sources "$work/networkish"
mkdir -p "$work/empty"
check fail "no Swift files" "$guard" sources "$work/empty"
check fail "a missing folder" "$guard" sources "$work/missing"
source_case second-ok 'import UIKit'
check fail "two folders, the second with SwiftUI" "$guard" sources "$work/second-ok" "$work/swiftui"

# Binary cases: a stand-in otool prints the load commands of each "Mach-O".
cat > "$work/otool" << 'EOF'
#!/bin/bash
cat "$2.links"
EOF
chmod +x "$work/otool"
# A stand-in Mach-O: the 64-bit little-endian magic number, then padding.
appex_case() {
    mkdir -p "$work/$1.appex"
    printf '\317\372\355\376padding' > "$work/$1.appex/SpeakboardKeyboard"
    printf '%s\n' "$2" > "$work/$1.appex/SpeakboardKeyboard.links"
}
appex_case good '/System/Library/Frameworks/UIKit.framework/UIKit
/System/Library/Frameworks/Foundation.framework/Foundation'
check pass "a binary that loads UIKit and Foundation" env OTOOL="$work/otool" "$guard" binary "$work/good.appex"
appex_case ui '/System/Library/Frameworks/SwiftUI.framework/SwiftUI'
check fail "a binary that loads SwiftUI" env OTOOL="$work/otool" "$guard" binary "$work/ui.appex"
appex_case net '/System/Library/Frameworks/Network.framework/Network'
check fail "a binary that loads Network" env OTOOL="$work/otool" "$guard" binary "$work/net.appex"
appex_case cfnet '/System/Library/Frameworks/CFNetwork.framework/CFNetwork'
check fail "a binary that loads CFNetwork" env OTOOL="$work/otool" "$guard" binary "$work/cfnet.appex"
mkdir -p "$work/nomacho.appex"
echo text > "$work/nomacho.appex/Info.plist"
check fail "no Mach-O file" env OTOOL="$work/otool" "$guard" binary "$work/nomacho.appex"
check fail "a missing extension" env OTOOL="$work/otool" "$guard" binary "$work/missing.appex"
cat > "$work/broken-otool" << 'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$work/broken-otool"
check fail "otool fails" env OTOOL="$work/broken-otool" "$guard" binary "$work/good.appex"

if [ "$wrong" -ne 0 ]; then
    echo "extension guard self-test: FAIL ($wrong wrong)"
    exit 1
fi
echo "extension guard self-test: OK"
