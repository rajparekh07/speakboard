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
#   1. on any file that is not a Swift file, except an Info.plist and Finder's
#      .DS_Store (by name: never compiled, and ignored by git): the targets
#      compile every source file in their folders, so an Objective-C or C file
#      could import anything, and only Swift files are read below. It follows
#      symbolic links, as Xcode does, and fails on a link that points nowhere
#      (in the Swift image, an absolute link to a file outside the repo does),
#      since the guard cannot read what Xcode elsewhere might compile;
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
# project: reads project.yml as `xcodegen dump --type json` gives it: with its
# includes merged and its variables expanded, but NOT with target templates or
# multi-platform targets expanded (XcodeGen does those later, when it
# generates). It fails unless:
#   - the extension's and KeyboardKit's target entries are exactly the
#     expected ones below, whole: sources, dependencies, settings, type and
#     platform, and no other key. A key the guard does not expect (a build
#     tool plugin, a pre-build or post-compile script, a build rule, config
#     files, ...) fails, named, as does any changed value (a new source path or
#     dependency, OTHER_SWIFT_FLAGS, OTHER_LDFLAGS, a bridging header, ...);
#   - the project-wide settings, which apply to every target, hold only
#     settings.base, with only the setting names allowed below (their values
#     are free: the bundle identifier is the owner's to choose);
#   - the core's package is this repo (`path: .`), which the core guards read;
#   - the top level holds only the keys this project uses;
#   - no target is multi-platform: a `platform` that is a list, or a
#     `platformPrefix` or `platformSuffix`, fails on any target. XcodeGen
#     renames a multi-platform target when it expands it (a target
#     `SpeakboardKeyboar` with `platform: [iOS]` and `platformSuffix: d`
#     becomes `SpeakboardKeyboard`), after the dump this guard reads, so the
#     target compared above would not be the one built;
#   - `options` sets no `preGenCommand` or `postGenCommand`, which run shell
#     commands when the project is generated;
#   - no scheme, and no target's own scheme, has `preActions` or
#     `postActions`, which run scripts inside xcodebuild. Any key of those
#     names anywhere in the dump fails.
# So any change to how the extension or KeyboardKit is built, version numbers
# included, means changing this guard too, on purpose. What it does not
# compare: the other targets' entries (the app and the tests, which are not
# linked into the extension), beyond the multi-platform and scheme checks:
# their own build scripts and build rules run in their own targets' builds.
# Target templates (`templates` on a target) are not expanded in the dump; on
# the extension and KeyboardKit the key fails the whole-entry comparison, and
# the top-level `targetTemplates` key fails the top-level check.
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

# The project mode's expected entries: the extension and KeyboardKit as
# project.yml builds them today, as XcodeGen resolves them (key order does not
# matter). A change to either target is a change here too.
expected_extension='{"type":"app-extension","platform":"iOS",
  "sources":[{"path":"Apple/Keyboard","excludes":["Info.plist"]}],
  "dependencies":[{"target":"KeyboardKit","embed":false}],
  "settings":{"base":{"PRODUCT_BUNDLE_IDENTIFIER":"$(SPEAKBOARD_BUNDLE_ID).keyboard","PRODUCT_NAME":"SpeakboardKeyboard",
    "INFOPLIST_FILE":"Apple/Keyboard/Info.plist","APPLICATION_EXTENSION_API_ONLY":true,
    "MARKETING_VERSION":"0.1","CURRENT_PROJECT_VERSION":"1"}}}'
expected_keyboardkit='{"type":"framework.static","platform":"iOS",
  "sources":[{"path":"Apple/KeyboardKit"}],
  "dependencies":[{"package":"Speakboard","product":"SpeakboardCore"}],
  "settings":{"base":{"PRODUCT_BUNDLE_IDENTIFIER":"$(SPEAKBOARD_BUNDLE_ID).KeyboardKit",
    "GENERATE_INFOPLIST_FILE":true,"APPLICATION_EXTENSION_API_ONLY":true}}}'
# The project-wide setting names allowed in settings.base, and the top-level
# keys project.yml may have.
project_setting_names="SPEAKBOARD_BUNDLE_ID SWIFT_VERSION CODE_SIGN_STYLE TARGETED_DEVICE_FAMILY ENABLE_USER_SCRIPT_SANDBOXING"
top_level_keys="name options packages schemes settings targets"

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
    : > "$work/dangling"
    for folder in "${folders[@]}"; do
        [ -d "$folder" ] || fail "folder not found: $folder"
        if ! find -L "$folder" -type f -print0 >> "$work/all" 2> "$work/find.txt"; then
            echo "extension guard: FAIL: could not list the files in $folder:" >&2
            head -n 20 "$work/find.txt" >&2
            exit 1
        fi
        # With -L, a link that is still a link points nowhere (here): -type f
        # skips it, but Xcode on another machine might compile what it names.
        if ! find -L "$folder" -type l -print0 >> "$work/dangling" 2> "$work/find.txt"; then
            echo "extension guard: FAIL: could not list the links in $folder:" >&2
            head -n 20 "$work/find.txt" >&2
            exit 1
        fi
    done
    local files=() problems=0
    while IFS= read -r -d '' file; do
        echo "extension guard: FAIL: $file is a symbolic link that points nowhere here, so the guard cannot read" \
            "what it names" >&2
        problems=$((problems + 1))
    done < "$work/dangling"
    while IFS= read -r -d '' file; do
        name=$(basename "$file")
        case "$name" in
            *.swift) files+=("$file") ;;
            Info.plist) ;;
            # Finder's folder metadata: never compiled, ignored by git, and
            # written by macOS into any folder opened in Finder.
            .DS_Store) ;;
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
    plutil -convert xml1 -o "$work/dump.plist" "$work/dump.json" || fail "xcodegen's dump of $spec is not JSON"
    local problems=0

    # The keys of the dictionary at key path $2 in property list $1 (the whole
    # list if $2 is empty), one per line; nothing if there is none. plutil
    # writes a dictionary's own keys one tab in.
    keys_of() {
        local xml
        if [ -z "$2" ]; then
            xml=$(cat "$1")
        else
            xml=$(plutil -extract "$2" xml1 -o - "$1" 2> /dev/null) || return 0
        fi
        printf '%s\n' "$xml" | sed -n 's/^	<key>\(.*\)<\/key>$/\1/p'
    }
    # The value at key path $2 in property list $1, as XML (compared) or JSON
    # (shown), or "(missing)". XML, because plutil writes a dictionary's keys
    # sorted there, while XcodeGen's JSON lists them in a different order from
    # run to run.
    value_xml() { plutil -extract "$2" xml1 -o - "$1" 2> /dev/null || echo "(missing)"; }
    value_json() { plutil -extract "$2" json -o - "$1" 2> /dev/null || echo "(missing)"; }

    # compare_entry <key path> <expected JSON object>: every key of the entry
    # at the key path, and every expected key, must hold exactly the expected
    # value. A key the guard does not expect fails, named.
    compare_entry() {
        local path="$1" key got want
        printf '%s' "$2" > "$work/want.json"
        plutil -convert xml1 -o "$work/want.plist" "$work/want.json" \
            || fail "the guard's own expected value for $path is not JSON"
        if [ "$(value_xml "$work/dump.plist" "$path")" = "(missing)" ]; then
            echo "extension guard: FAIL: project.yml has no $path" >&2
            problems=$((problems + 1))
            return
        fi
        for key in $( (keys_of "$work/dump.plist" "$path"; keys_of "$work/want.plist" "") | sort -u); do
            got=$(value_xml "$work/dump.plist" "$path.$key")
            want=$(value_xml "$work/want.plist" "$key")
            if [ "$got" != "$want" ]; then
                if [ "$want" = "(missing)" ]; then
                    echo "extension guard: FAIL: project.yml $path.$key is set ($(value_json "$work/dump.plist" "$path.$key")):" \
                        "a key the guard does not expect there" >&2
                else
                    echo "extension guard: FAIL: project.yml $path.$key is $(value_json "$work/dump.plist" "$path.$key")," \
                        "not $(value_json "$work/want.plist" "$key")" >&2
                fi
                problems=$((problems + 1))
            fi
        done
    }

    # 1. The top level holds only the keys this project uses. Another key
    #    (configFiles, fileGroups, projectReferences, targetTemplates left
    #    unresolved, ...) is not read below, so it fails, named.
    local key
    for key in $(keys_of "$work/dump.plist" ""); do
        case " $top_level_keys " in
            *" $key "*) ;;
            *)
                echo "extension guard: FAIL: project.yml has the top-level key $key, which the guard does not know" >&2
                problems=$((problems + 1))
                ;;
        esac
    done
    # 2. Project-wide settings apply to every target, the extension included.
    #    Only `base` is allowed, holding only the setting names below; their
    #    values are free (the bundle identifier is the owner's to choose).
    for key in $(keys_of "$work/dump.plist" settings); do
        if [ "$key" != base ]; then
            echo "extension guard: FAIL: project.yml settings.$key is set: only settings.base is allowed" >&2
            problems=$((problems + 1))
        fi
    done
    for key in $(keys_of "$work/dump.plist" settings.base); do
        case " $project_setting_names " in
            *" $key "*) ;;
            *)
                echo "extension guard: FAIL: project.yml settings.base.$key is set: a project-wide setting the guard" \
                    "does not allow (it would apply to the extension too)" >&2
                problems=$((problems + 1))
                ;;
        esac
    done
    # 3. The core comes from this repo's own package, which the core guards read.
    compare_entry packages.Speakboard '{"path":"."}'
    # 4. No multi-platform target: XcodeGen renames one when it expands it,
    #    after this dump, so a target that reads `SpeakboardKeyboar` here can
    #    be built as `SpeakboardKeyboard`. Target names are plain words here,
    #    so each is a usable key path.
    local target platform
    for target in $(keys_of "$work/dump.plist" targets); do
        case "$target" in
            *[!A-Za-z0-9_-]*)
                echo "extension guard: FAIL: project.yml has a target named \"$target\": only letters, digits, _ and -" \
                    "are allowed, so the guard can read it" >&2
                problems=$((problems + 1))
                continue
                ;;
        esac
        platform=$(value_xml "$work/dump.plist" "targets.$target.platform")
        case "$platform" in
            *"<array>"* | *"<array/>"*)
                echo "extension guard: FAIL: project.yml targets.$target.platform is a list: a multi-platform target," \
                    "which XcodeGen renames after the dump this guard reads" >&2
                problems=$((problems + 1))
                ;;
        esac
        for key in platformPrefix platformSuffix; do
            if [ "$(value_xml "$work/dump.plist" "targets.$target.$key")" != "(missing)" ]; then
                echo "extension guard: FAIL: project.yml targets.$target.$key is set: it renames a multi-platform" \
                    "target after the dump this guard reads" >&2
                problems=$((problems + 1))
            fi
        done
    done
    # 5. No commands at generation, and no scheme scripts in xcodebuild.
    for key in preGenCommand postGenCommand; do
        if [ "$(value_xml "$work/dump.plist" "options.$key")" != "(missing)" ]; then
            echo "extension guard: FAIL: project.yml options.$key is set: it runs a shell command when the project" \
                "is generated" >&2
            problems=$((problems + 1))
        fi
    done
    if grep -E '<key>(preActions|postActions)</key>' "$work/dump.plist" > /dev/null; then
        echo "extension guard: FAIL: project.yml has scheme preActions or postActions: they run scripts inside" \
            "xcodebuild" >&2
        problems=$((problems + 1))
    fi
    # 6. The extension and KeyboardKit, whole: sources, dependencies, settings,
    #    type and platform, and no other key (build tool plugins, script phases,
    #    build rules, config files, ...).
    compare_entry targets.SpeakboardKeyboard "$expected_extension"
    compare_entry targets.KeyboardKit "$expected_keyboardkit"

    if [ "$problems" -ne 0 ]; then
        echo "The extension guard scans exactly the extension's and KeyboardKit's own folders and the core. A change" >&2
        echo "to how project.yml builds them is a change to the guard too: scripts/extension-guard.sh project." >&2
        exit 1
    fi
    echo "extension guard: OK (project.yml: the extension and KeyboardKit are exactly as the guard expects, the" \
        "project-wide settings and top-level keys are ones it knows, the core is this repo's package, no target is" \
        "multi-platform, and no generation command or scheme action runs a script)"
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
