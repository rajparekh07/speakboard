#!/bin/bash
# Prints the keyboard's screenshots into the job log as text (KEY-68), so an
# agent can recover them from a saved job log with
# scripts/screenshots-from-log.sh and look at them. Agents cannot download a
# run's artifacts (KEY-54), but they can read its job log.
#
#   scripts/screenshots-to-log.sh print <screenshots dir>
#       macOS only (scripts/screenshot-image.swift, compiled with xcrun
#       swiftc, for the images; sips to check their size; plutil). <screenshots dir> is what
#       scripts/sim-keyboard.sh wrote. Prints, in this order:
#         keyboard-light.png, keyboard-dark.png
#             keyboard.png and keyboard-dark.png (the keyboard extension in the
#             app's field, light, then dark after switching appearance with the
#             keyboard up), cropped to the keyboard region at full resolution,
#             PNG, so glyph sharpness and label baselines can be judged
#         <state>-<appearance>.jpg, for each state shift-auto, shift-off,
#         shift-on and caps-lock, and each appearance light and dark
#             the UI tests' screenshots, cropped the same way, then scaled to
#             half size, JPEG
#         apple-keyboard-<appearance>.jpg
#             Apple's keyboard, when the UI test found it up before it switched
#             to Speakboard, as the others. When a run has not got it, one
#             `speakboard-screenshot none` line says so; that is not a failure.
#       The keyboard region is the bottom 2/5 of the screen, full width: on the
#       iPhone 18 Pro (874 pt high) from 524 pt down, which holds the keyboard
#       (from 539 pt) and the system's strip below it, for ours and Apple's.
#       It fails, after printing what it can, if a screenshot other than
#       Apple's is missing or an image tool fails.
#
#   scripts/screenshots-to-log.sh emit <name> <file> <what>
#       Prints one file as one block. Any platform: the self-test of the
#       recovery script uses it on Linux.
#
# A block, each line as the script prints it (GitHub puts a timestamp before
# each line of the job log; the recovery script removes it):
#   speakboard-screenshot begin name=<name> bytes=<n> sha256=<hex> what=<text>
#   <the file in base64, 76 characters a line, the last line maybe shorter>
#   speakboard-screenshot end name=<name>
# A name is letters, digits, dots, dashes and underscores, starting with a
# letter or digit. The what text is letters, digits, spaces and , . : ; ( ) /
# + = x - only, so the job-log tool's JSON escapes nothing in a block.
#
# Written for the bash 3.2 at /bin/bash and the tools macOS ships (sips,
# plutil, base64, shasum) with Xcode's swiftc, as well as Linux for `emit`.
set -euo pipefail

fail() {
    echo "screenshots-to-log: FAIL: $1" >&2
    exit 1
}

sha256() {
    if command -v sha256sum > /dev/null 2>&1; then
        sha256sum | cut -d ' ' -f 1
    elif command -v shasum > /dev/null 2>&1; then
        shasum -a 256 | cut -d ' ' -f 1
    else
        fail "neither sha256sum nor shasum is available"
    fi
}

# emit <name> <file> <what>: prints the block, then one line with the number of
# characters it added to the log (the block's lines and their newlines).
emit() {
    local name="$1" file="$2" what="$3" bytes sha block chars
    case "$name" in
        [A-Za-z0-9]*) ;;
        *) fail "the name \"$name\" does not start with a letter or digit" ;;
    esac
    case "$name" in
        *[!A-Za-z0-9._-]*) fail "the name \"$name\" has a character other than letters, digits, . _ -" ;;
    esac
    case "$what" in
        *[!A-Za-z0-9\ ,.:\;\(\)/+=x-]*) fail "the description of $name has a character the block does not allow: $what" ;;
    esac
    [ -f "$file" ] || fail "no file $file for $name"
    bytes=$(wc -c < "$file" | tr -d ' ')
    [ "$bytes" -gt 0 ] || fail "$file is empty"
    sha=$(sha256 < "$file")
    block=$(mktemp)
    {
        echo "speakboard-screenshot begin name=$name bytes=$bytes sha256=$sha what=$what"
        base64 < "$file" | tr -d '\r\n' | fold -w 76
        echo
        echo "speakboard-screenshot end name=$name"
    } > "$block"
    chars=$(wc -c < "$block" | tr -d ' ')
    cat "$block"
    rm -f "$block"
    echo "speakboard-screenshot printed name=$name chars=$chars"
}

# pixels <file> <pixelWidth|pixelHeight>
pixels() {
    local value
    value=$(sips -g "$2" "$1" 2> /dev/null | awk -v key="$2:" '$1 == key { print $2 }') || true
    case "$value" in
        '' | *[!0-9]*) fail "sips could not read $2 of $1 (got \"$value\")" ;;
    esac
    printf '%s\n' "$value"
}

# shape <in> <out> <png|jpeg> <divisor>: the bottom 2/5 of the screen, full
# width, its width and height divided by <divisor>, by scripts/screenshot-image.swift
# (compiled into $tool). Sets `note` to the crop's rows and the output's size,
# and checks the size again with sips.
shape() {
    local in="$1" out="$2" format="$3" divisor="$4" width height
    note=$("$tool" "$in" "$out" "$format" "$divisor") || fail "could not crop $in"
    width=$(pixels "$in" pixelWidth)
    height=$(pixels "$in" pixelHeight)
    [ "$(pixels "$out" pixelWidth)" = "$((width / divisor))" ] \
        && [ "$(pixels "$out" pixelHeight)" = "$((height * 2 / 5 / divisor))" ] \
        || fail "$out is $(pixels "$out" pixelWidth)x$(pixels "$out" pixelHeight), not $((width / divisor))x$((height * 2 / 5 / divisor))"
}

# attachment <export dir> <attachment name>: the exported file of the UI test's
# attachment named <attachment name>, from the export's manifest.json, or nothing.
attachment() {
    local dir="$1" name="$2" manifest="$1/manifest.json" test=0 index suggested exported
    [ -f "$manifest" ] || return 0
    while plutil -extract "$test" json -o - "$manifest" > /dev/null 2>&1; do
        index=0
        while exported=$(plutil -extract "$test.attachments.$index.exportedFileName" raw -o - "$manifest" 2> /dev/null); do
            suggested=$(plutil -extract "$test.attachments.$index.suggestedHumanReadableName" raw -o - "$manifest" \
                2> /dev/null || true)
            case "$suggested" in
                "$name"_* | "$name".*)
                    printf '%s\n' "$dir/$exported"
                    return 0
                    ;;
            esac
            index=$((index + 1))
        done
        test=$((test + 1))
    done
}

print_all() {
    local dir="$1" missing=0 appearance state source name what total=0 count=0 line
    [ "$(uname -s)" = Darwin ] || fail "print needs macOS (sips, plutil); emit works anywhere"
    command -v sips > /dev/null 2>&1 || fail "sips is not available"
    command -v plutil > /dev/null 2>&1 || fail "plutil is not available"
    [ -d "$dir" ] || fail "no screenshots folder $dir"
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    tool="$work/screenshot-image"
    xcrun swiftc -O "$(cd "$(dirname "$0")" && pwd)/screenshot-image.swift" -o "$tool" \
        || fail "could not compile scripts/screenshot-image.swift"

    # emit_counted <name> <file> <what>: emit, and add up what the blocks added to the log, from each block's
    # `printed` line. Not in a pipeline, so the totals stay in this shell.
    emit_counted() {
        emit "$1" "$2" "$3" > "$work/block.txt"
        cat "$work/block.txt"
        line=$(tail -n 1 "$work/block.txt")
        total=$((total + ${line##*chars=}))
        count=$((count + 1))
    }

    echo "speakboard-screenshots: the screenshots follow as text; recover them with scripts/screenshots-from-log.sh"
    for appearance in light dark; do
        if [ "$appearance" = light ]; then source="$dir/keyboard.png"; else source="$dir/keyboard-dark.png"; fi
        name="keyboard-$appearance.png"
        if [ -f "$source" ]; then
            shape "$source" "$work/$name" png 1
            emit_counted "$name" "$work/$name" \
                "the keyboard extension in the app field, $appearance; crop of $note, full resolution, PNG"
        else
            echo "speakboard-screenshot none name=$name reason=no $source"
            missing=$((missing + 1))
        fi
    done
    for appearance in light dark; do
        if [ ! -f "$dir/ui-$appearance/manifest.json" ]; then
            echo "speakboard-screenshots: no manifest.json in $dir/ui-$appearance; its files:"
            ls -l "$dir/ui-$appearance" 2>&1 | head -n 40 || true
        fi
        for state in shift-auto shift-off shift-on caps-lock apple-keyboard; do
            name="$state-$appearance.jpg"
            source=$(attachment "$dir/ui-$appearance" "$state-$appearance")
            if [ -n "$source" ] && [ -f "$source" ]; then
                shape "$source" "$work/$name" jpeg 2
                if [ "$state" = apple-keyboard ]; then
                    what="Apple keyboard before the UI test switched to Speakboard, $appearance"
                else
                    what="UI test screenshot $state, $appearance"
                fi
                emit_counted "$name" "$work/$name" "$what; crop of $note, half size, JPEG"
            elif [ "$state" = apple-keyboard ]; then
                echo "speakboard-screenshot none name=$name reason=the UI test did not find Apple's keyboard up in $appearance appearance, so this run has no screenshot of it"
            else
                echo "speakboard-screenshot none name=$name reason=no attachment $state-$appearance in $dir/ui-$appearance"
                if [ "$missing" -eq 0 ] && [ -f "$dir/ui-$appearance/manifest.json" ]; then
                    echo "speakboard-screenshots: the start of $dir/ui-$appearance/manifest.json, to see why:"
                    head -n 60 "$dir/ui-$appearance/manifest.json" || true
                fi
                missing=$((missing + 1))
            fi
        done
    done
    echo "speakboard-screenshots: $count images printed, $total characters of log text"
    [ "$missing" -eq 0 ] || fail "$missing screenshots that should be there are missing (see the none lines above)"
}

case "${1:-}" in
    emit)
        [ "$#" -eq 4 ] || fail "usage: $0 emit <name> <file> <what>"
        emit "$2" "$3" "$4"
        ;;
    print)
        [ "$#" -eq 2 ] || fail "usage: $0 print <screenshots dir>"
        print_all "$2"
        ;;
    *)
        echo "usage: $0 print <screenshots dir> | emit <name> <file> <what>" >&2
        exit 2
        ;;
esac
