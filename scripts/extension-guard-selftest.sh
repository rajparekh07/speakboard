#!/bin/bash
# Self-test of scripts/extension-guard.sh: each case must pass or fail as
# stated, and each failing case must fail with its own message, so a broken
# guard cannot pass silently and a case cannot pass by failing for another
# reason.
#
#   scripts/extension-guard-selftest.sh           the sources and binary modes:
#                                                 needs the compiler frontend
#                                                 (SWIFT_FRONTEND, or
#                                                 swift-frontend on PATH), as
#                                                 make check and check-native run it
#   scripts/extension-guard-selftest.sh project   the project mode: needs plutil
#                                                 (macOS), run in macOS CI
#
# The binary and project cases use stand-in otool and xcodegen commands, so
# they need no build. Written for bash 3.2 and BSD tools as well as Linux.
set -euo pipefail

guard="$(cd "$(dirname "$0")" && pwd)/extension-guard.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
wrong=0

# check pass|fail <description> <message> <command...>
check() {
    local want="$1" description="$2" message="$3"
    shift 3
    local output got
    if output=$("$@" 2>&1); then got=pass; else got=fail; fi
    if [ "$got" != "$want" ]; then
        echo "extension guard self-test: WRONG: $description (wanted $want, got $got)" >&2
        echo "$output" | sed 's/^/    /' >&2
        wrong=$((wrong + 1))
    elif [ "$want" = fail ] && ! grep -qF -- "$message" <<< "$output"; then
        echo "extension guard self-test: WRONG: $description (failed, but not with \"$message\")" >&2
        echo "$output" | sed 's/^/    /' >&2
        wrong=$((wrong + 1))
    else
        echo "extension guard self-test: ok: $description ($want)"
    fi
}

# swift <pass|fail> <description> <source> [message]: one Swift file, Case.swift.
swift_case() {
    local dir="$work/case$RANDOM$RANDOM"
    mkdir -p "$dir"
    printf '%s\n' "$3" > "$dir/Case.swift"
    check "$1" "$2" "${4:-}" "$guard" sources "$dir"
}

finish() {
    if [ "$wrong" -ne 0 ]; then
        echo "extension guard self-test: FAIL ($wrong wrong)"
        exit 1
    fi
    echo "extension guard self-test: OK"
}

if [ "${1:-}" = project ]; then
    command -v plutil > /dev/null 2>&1 || {
        echo "extension guard self-test: FAIL: the project cases need plutil (macOS)" >&2
        exit 1
    }
    # A stand-in xcodegen that prints the JSON dump in $DUMP.
    mkdir -p "$work/bin"
    printf '#!/bin/bash\ncat "$DUMP"\n' > "$work/bin/xcodegen"
    chmod +x "$work/bin/xcodegen"
    touch "$work/project.yml"
    # dump <extension sources> <extension dependencies> <KeyboardKit sources> <KeyboardKit dependencies>
    dump() {
        printf '{"targets":{"SpeakboardKeyboard":{"sources":%s,"dependencies":%s},' "$1" "$2"
        printf '"KeyboardKit":{"sources":%s,"dependencies":%s}}}' "$3" "$4"
    }
    ext_src='[{"path":"Apple/Keyboard","excludes":["Info.plist"]}]'
    ext_dep='[{"embed":false,"target":"KeyboardKit"}]'
    kit_src='[{"path":"Apple/KeyboardKit"}]'
    kit_dep='[{"package":"Speakboard","product":"SpeakboardCore"}]'
    project_case() {
        printf '%s\n' "$4" > "$work/dump.json"
        check "$1" "$2" "$3" env PATH="$work/bin:$PATH" DUMP="$work/dump.json" "$guard" project "$work/project.yml"
    }
    project_case pass "the extension's and KeyboardKit's sources and dependencies as the guard scans them" "" \
        "$(dump "$ext_src" "$ext_dep" "$kit_src" "$kit_dep")"
    project_case pass "the same, with each dictionary's keys in another order" "" \
        "$(dump '[{"excludes":["Info.plist"],"path":"Apple/Keyboard"}]' '[{"target":"KeyboardKit","embed":false}]' \
            "$kit_src" '[{"product":"SpeakboardCore","package":"Speakboard"}]')"
    project_case fail "a second source path for the extension" "targets.SpeakboardKeyboard.sources" \
        "$(dump '[{"path":"Apple/Keyboard","excludes":["Info.plist"]},{"path":"Apple/Other"}]' "$ext_dep" "$kit_src" "$kit_dep")"
    project_case fail "the extension without its Info.plist excluded" "targets.SpeakboardKeyboard.sources" \
        "$(dump '[{"path":"Apple/Keyboard"}]' "$ext_dep" "$kit_src" "$kit_dep")"
    project_case fail "another source path for KeyboardKit" "targets.KeyboardKit.sources" \
        "$(dump "$ext_src" "$ext_dep" '[{"path":"Apple/Elsewhere"}]' "$kit_dep")"
    project_case fail "a package dependency for the extension" "targets.SpeakboardKeyboard.dependencies" \
        "$(dump "$ext_src" '[{"embed":false,"target":"KeyboardKit"},{"package":"X","product":"Y"}]' "$kit_src" "$kit_dep")"
    project_case fail "another dependency for KeyboardKit" "targets.KeyboardKit.dependencies" \
        "$(dump "$ext_src" "$ext_dep" "$kit_src" '[{"package":"Speakboard","product":"Other"}]')"
    project_case fail "no extension target" "targets.SpeakboardKeyboard.sources is (missing)" '{"targets":{}}'
    check fail "no project spec" "no project spec" env PATH="$work/bin:$PATH" "$guard" project "$work/missing.yml"
    finish
    exit 0
fi

# Allowed: what the extension and KeyboardKit use today.
swift_case pass "UIKit, QuartzCore and the core" 'import QuartzCore
import SpeakboardCore
import UIKit'
swift_case pass "KeyboardKit and OSLog" 'import KeyboardKit
import OSLog
import UIKit'
swift_case pass "Foundation" 'import Foundation'
swift_case pass "no import" 'let x = 1'
swift_case pass "names that only look like networking" 'import UIKit
func reconnect(_ x: Int) -> Int { x }
let image = UIImage(contentsOfFile: "/x")
let networkCount = 1'

# Imports outside the allowlist, in every spelling: the compiler reads them.
swift_case fail "import SwiftUI" 'import SwiftUI' "Case.swift imports SwiftUI"
swift_case fail "import struct SwiftUI.Text" 'import struct SwiftUI.Text' "Case.swift imports SwiftUI"
swift_case fail "import SwiftUICore" 'import SwiftUICore' "Case.swift imports SwiftUICore"
swift_case fail "import and SwiftUI on separate lines" 'import
    SwiftUI' "Case.swift imports SwiftUI"
swift_case fail "import/**/SwiftUI" 'import/**/SwiftUI' "Case.swift imports SwiftUI"
swift_case fail "an attributed import of SwiftUI" '@preconcurrency import SwiftUI' "Case.swift imports SwiftUI"
swift_case fail "import class Network.NWPathMonitor, then NWPathMonitor()" 'import class Network.NWPathMonitor
let monitor = NWPathMonitor()' "Case.swift imports Network"
swift_case fail "import Network" 'import Network' "Case.swift imports Network"
swift_case fail "import FoundationNetworking" 'import FoundationNetworking' "Case.swift imports FoundationNetworking"
swift_case fail "a module that does not exist" 'import NoSuchModule' "Case.swift imports NoSuchModule"

# Networking reached without a new import: only the text net sees these.
swift_case fail "socket with a space before the parenthesis" 'import Foundation
let fd = socket (AF_INET, SOCK_STREAM, 0)' "a networking name"
swift_case fail "connect(fd, ...)" 'import Foundation
let r = connect(fd, address, length)' "a networking name"
swift_case fail "Data(contentsOf:) with a URL" 'import Foundation
let d = try Data(contentsOf: URL(string: "https://example.com")!)' "a networking name"
swift_case fail "String(contentsOf:)" 'import Foundation
let s = try String(contentsOf: url, encoding: .utf8)' "a networking name"
swift_case fail "Stream.getStreamsToHost" 'import Foundation
Stream.getStreamsToHost(withName: "example.com", port: 80, inputStream: &i, outputStream: &o)' "a networking name"
swift_case fail "CFReadStreamCreateForHTTPRequest" 'import Foundation
let s = CFReadStreamCreateForHTTPRequest(nil, request)' "a networking name"
swift_case fail "URLSession" 'import Foundation
let s = URLSession.shared' "a networking name"
swift_case fail "NWConnection with no import" 'let c = NWConnection(host: "x", port: 1, using: .tcp)' \
    "a networking name"
swift_case fail "a networking name in a comment (a false hit, on purpose)" 'import UIKit
// no URLSession here' "a networking name"

# Conditional compilation: the compiler would not report an import in an inactive branch.
swift_case fail "#if around an import" 'import UIKit
#if DEBUG
import SwiftUI
#endif' "Case.swift:2: conditional compilation"
swift_case fail "an indented #if" 'import UIKit
    #if os(iOS)
    #endif' "conditional compilation"

# Files the targets would compile but the import check cannot read.
mkdir -p "$work/objc"
printf 'import UIKit\n' > "$work/objc/View.swift"
printf '@import Network;\nNSURLSession *s;\n' > "$work/objc/Net.m"
check fail "an Objective-C file beside the Swift" "Net.m is not a Swift file" "$guard" sources "$work/objc"
mkdir -p "$work/cfile"
printf 'import UIKit\n' > "$work/cfile/View.swift"
printf 'int x;\n' > "$work/cfile/x.c"
check fail "a C file" "x.c is not a Swift file" "$guard" sources "$work/cfile"
mkdir -p "$work/plist"
printf 'import UIKit\n' > "$work/plist/View.swift"
printf '<plist/>\n' > "$work/plist/Info.plist"
check pass "an Info.plist beside the Swift" "" "$guard" sources "$work/plist"

# Several folders, and failing closed.
mkdir -p "$work/ok" "$work/bad" "$work/empty"
printf 'import UIKit\n' > "$work/ok/A.swift"
printf 'import SwiftUI\n' > "$work/bad/B.swift"
check fail "two folders, the second importing SwiftUI" "B.swift imports SwiftUI" "$guard" sources "$work/ok" "$work/bad"
check fail "no Swift files" "no Swift files" "$guard" sources "$work/empty"
check fail "a missing folder" "folder not found" "$guard" sources "$work/missing"
check fail "no compiler frontend" "is not available" env SWIFT_FRONTEND="$work/no-such-frontend" \
    "$guard" sources "$work/ok"
printf '#!/bin/bash\nexit 1\n' > "$work/failing-frontend"
chmod +x "$work/failing-frontend"
check fail "a frontend that fails" "could not read the imports" env SWIFT_FRONTEND="$work/failing-frontend" \
    "$guard" sources "$work/ok"
printf '#!/bin/bash\nexit 0\n' > "$work/silent-frontend"
chmod +x "$work/silent-frontend"
check fail "a frontend that writes nothing" "wrote no list" env SWIFT_FRONTEND="$work/silent-frontend" \
    "$guard" sources "$work/ok"

# Binary cases: a stand-in otool prints the load commands of each stand-in Mach-O.
printf '#!/bin/bash\ncat "$2.links"\n' > "$work/otool"
chmod +x "$work/otool"
# appex_case <name> <magic bytes, as printf octal> <load commands>
appex_case() {
    mkdir -p "$work/$1.appex"
    printf "$2"'padding' > "$work/$1.appex/SpeakboardKeyboard"
    printf '%s\n' "$3" > "$work/$1.appex/SpeakboardKeyboard.links"
}
thin64='\317\372\355\376'
appex_case good "$thin64" '/System/Library/Frameworks/UIKit.framework/UIKit
/System/Library/Frameworks/Foundation.framework/Foundation'
check pass "a binary that loads UIKit and Foundation" "" env OTOOL="$work/otool" "$guard" binary "$work/good.appex"
appex_case ui "$thin64" '/System/Library/Frameworks/SwiftUI.framework/SwiftUI'
check fail "a binary that loads SwiftUI" "loads SwiftUI or a networking framework" \
    env OTOOL="$work/otool" "$guard" binary "$work/ui.appex"
appex_case uicore "$thin64" '/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore'
check fail "a binary that loads SwiftUICore" "loads SwiftUI or a networking framework" \
    env OTOOL="$work/otool" "$guard" binary "$work/uicore.appex"
appex_case net "$thin64" '/System/Library/Frameworks/Network.framework/Network'
check fail "a binary that loads Network" "loads SwiftUI or a networking framework" \
    env OTOOL="$work/otool" "$guard" binary "$work/net.appex"
appex_case cfnet "$thin64" '/System/Library/Frameworks/CFNetwork.framework/CFNetwork'
check fail "a binary that loads CFNetwork" "loads SwiftUI or a networking framework" \
    env OTOOL="$work/otool" "$guard" binary "$work/cfnet.appex"
appex_case fat64 '\312\376\272\277' '/System/Library/Frameworks/SwiftUI.framework/SwiftUI'
check fail "a universal (FAT_MAGIC_64) binary that loads SwiftUI" "loads SwiftUI or a networking framework" \
    env OTOOL="$work/otool" "$guard" binary "$work/fat64.appex"
appex_case fat '\312\376\272\276' '/System/Library/Frameworks/Network.framework/Network'
check fail "a universal (FAT_MAGIC) binary that loads Network" "loads SwiftUI or a networking framework" \
    env OTOOL="$work/otool" "$guard" binary "$work/fat.appex"
mkdir -p "$work/nomacho.appex"
echo text > "$work/nomacho.appex/Info.plist"
check fail "no Mach-O file" "no Mach-O file" env OTOOL="$work/otool" "$guard" binary "$work/nomacho.appex"
check fail "a missing extension" "no extension at" env OTOOL="$work/otool" "$guard" binary "$work/missing.appex"
printf '#!/bin/bash\nexit 1\n' > "$work/broken-otool"
chmod +x "$work/broken-otool"
check fail "otool fails" "-L failed" env OTOOL="$work/broken-otool" "$guard" binary "$work/good.appex"

finish
