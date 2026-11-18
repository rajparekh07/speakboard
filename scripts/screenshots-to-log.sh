#!/bin/bash
# Prints the keyboard's screenshots into the job log as text (KEY-68), so an
# agent can recover them from a saved job log with
# scripts/screenshots-from-log.sh and look at them. Agents cannot download a
# run's artifacts (KEY-54), but they can read its job log.
#
# GitHub's job-log tool returns at most the last 5,000 lines of a job's log,
# so the images are not printed in the macOS job, whose own lines (the test
# totals, the speakboard-ui lines) must stay readable. That job prepares them,
# and small Linux jobs of the same workflow print them, a group each, every
# group's whole log within the tool's reach:
#
#   scripts/screenshots-to-log.sh prepare <screenshots dir> <out dir>
#       macOS only (scripts/screenshot-image.swift, compiled with xcrun
#       swiftc, for the images; sips to check their size; plutil). Makes,
#       from what scripts/sim-keyboard.sh wrote, in <out dir>:
#         keyboard-light.png, keyboard-dark.png
#             keyboard.png and keyboard-dark.png (the keyboard extension in the
#             app's field, light, then dark after switching appearance with the
#             keyboard up), cropped to the keyboard region at full resolution,
#             PNG (lossless), so glyph sharpness and label baselines can be
#             judged
#         <state>-<appearance>.jpg, for each state shift-auto, shift-off,
#         shift-on and caps-lock, and each appearance light and dark
#             the UI tests' screenshots, cropped the same way, then scaled to
#             half size, JPEG
#         apple-keyboard-<appearance>.jpg
#             Apple's keyboard, when the UI test found it up before it switched
#             to Speakboard, as the others. When a run has not got it, a line
#             in none.txt says so; that is not a failure.
#         what.tsv, a line per image: its name, a tab, and what it is
#         none.txt, a `speakboard-screenshot none` line per image not made
#       The keyboard region is the bottom 2/5 of the screen, full width: on the
#       iPhone 18 Pro (874 pt high) from 524 pt down, which holds the keyboard
#       (from 539 pt) and the system's strip below it, for ours and Apple's.
#       If a screenshot other than Apple's is missing, it makes the rest, then
#       fails. If an image tool fails, it fails at once, with what it made so
#       far left in <out dir>.
#
#   scripts/screenshots-to-log.sh print <prepared dir> <group> [<budget>]
#       Any platform. Prints the group's images from <prepared dir> as blocks,
#       or the none line of an image not made, then one line with the group's
#       image count, lines and characters. The groups:
#         keyboard-light   keyboard-light.png
#         keyboard-dark    keyboard-dark.png
#         ui-light         shift-auto, shift-off, shift-on, caps-lock and
#                          apple-keyboard, -light.jpg
#         ui-dark          the same, -dark.jpg
#       It fails, printing no block, if the blocks would take more than
#       <budget> lines, or if an image other than Apple's is missing.
#
#       The one hard limit is the job-log tool's: it returns at most the last
#       5,000 lines of a job's log. The budget, 4,600 printed lines a group by
#       default, is ours. A screenshots job's own lines (checkout, the artifact
#       fetch, setup and cleanup) were 211 on a475ff9 (4,127 lines in all, 3,916
#       of them printed), so a group at its budget gives a log of about 4,811
#       lines: a margin of about 190 lines for those lines to grow.
#
#       If the full-resolution crop outgrows one job (a busier backdrop, such
#       as a translucent one with the app blurred through it, makes a bigger
#       PNG), split it over two jobs rather than lose pixels: have `prepare`
#       cut the crop into its top and bottom halves at a row between key rows,
#       as keyboard-<appearance>-top.png and -bottom.png, each lossless; give
#       each half its own group and matrix entry (keyboard-light-top and so
#       on); and say in the docs that the halves are one image. Not built.
#
#   scripts/screenshots-to-log.sh emit <name> <file> <what>
#       Prints one file as one block. Any platform.
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
# plutil, base64, shasum) with Xcode's swiftc, and for Linux (print, emit).
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

prepare() {
    local dir="$1" out="$2" missing=0 appearance state source name
    [ "$(uname -s)" = Darwin ] || fail "prepare needs macOS (ImageIO, sips, plutil); print and emit work anywhere"
    command -v sips > /dev/null 2>&1 || fail "sips is not available"
    command -v plutil > /dev/null 2>&1 || fail "plutil is not available"
    [ -d "$dir" ] || fail "no screenshots folder $dir"
    mkdir -p "$out"
    : > "$out/what.tsv"
    : > "$out/none.txt"
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    tool="$work/screenshot-image"
    xcrun swiftc -O "$(cd "$(dirname "$0")" && pwd)/screenshot-image.swift" -o "$tool" \
        || fail "could not compile scripts/screenshot-image.swift"

    # made <name> <what>: records the image and says so in the job log.
    made() {
        printf '%s\t%s\n' "$1" "$2" >> "$out/what.tsv"
        echo "speakboard-screenshots: made $1 ($(wc -c < "$out/$1" | tr -d ' ') bytes): $2"
    }
    # none <name> <reason>
    none() {
        echo "speakboard-screenshot none name=$1 reason=$2" | tee -a "$out/none.txt"
    }

    for appearance in light dark; do
        if [ "$appearance" = light ]; then source="$dir/keyboard.png"; else source="$dir/keyboard-dark.png"; fi
        name="keyboard-$appearance.png"
        if [ -f "$source" ]; then
            shape "$source" "$out/$name" png 1
            made "$name" "the keyboard extension in the app field, $appearance; crop of $note, full resolution, PNG"
        else
            none "$name" "no $source"
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
                shape "$source" "$out/$name" jpeg 2
                if [ "$state" = apple-keyboard ]; then
                    made "$name" "Apple keyboard before the UI test switched to Speakboard, $appearance; crop of $note, half size, JPEG"
                else
                    made "$name" "UI test screenshot $state, $appearance; crop of $note, half size, JPEG"
                fi
            elif [ "$state" = apple-keyboard ]; then
                none "$name" "the UI test did not find Apple's keyboard up in $appearance appearance, so this run has no screenshot of it"
            else
                none "$name" "no attachment $state-$appearance in $dir/ui-$appearance"
                if [ "$missing" -eq 0 ] && [ -f "$dir/ui-$appearance/manifest.json" ]; then
                    echo "speakboard-screenshots: the start of $dir/ui-$appearance/manifest.json, to see why:"
                    head -n 60 "$dir/ui-$appearance/manifest.json" || true
                fi
                missing=$((missing + 1))
            fi
        done
    done
    [ "$missing" -eq 0 ] || fail "$missing screenshots that should be there are missing (see the none lines above)"
    echo "speakboard-screenshots: prepared in $out; the screenshots jobs print them"
}

# print_group <prepared dir> <group> <budget>
print_group() {
    local dir="$1" group="$2" budget="$3" names name what line rest missing=0 count=0 lines chars
    case "$group" in
        keyboard-light) names="keyboard-light.png" ;;
        keyboard-dark) names="keyboard-dark.png" ;;
        ui-light | ui-dark)
            names=""
            for name in shift-auto shift-off shift-on caps-lock apple-keyboard; do
                names="$names $name-${group#ui-}.jpg"
            done
            ;;
        *) fail "no group $group (keyboard-light, keyboard-dark, ui-light, ui-dark)" ;;
    esac
    case "$budget" in
        '' | *[!0-9]*) fail "the budget must be a number of lines, not \"$budget\"" ;;
    esac
    [ -f "$dir/what.tsv" ] || fail "no what.tsv in $dir: is it a folder the prepare step made?"
    blocks=$(mktemp)
    trap 'rm -f "$blocks"' EXIT
    for name in $names; do
        if [ -f "$dir/$name" ]; then
            what=""
            while IFS="$(printf '\t')" read -r line rest; do
                if [ "$line" = "$name" ]; then what=$rest; fi
            done < "$dir/what.tsv"
            [ -n "$what" ] || fail "no line for $name in $dir/what.tsv"
            emit "$name" "$dir/$name" "$what" >> "$blocks"
            count=$((count + 1))
        elif line=$(grep -F "speakboard-screenshot none name=$name " "$dir/none.txt" 2> /dev/null); then
            printf '%s\n' "$line" >> "$blocks"
            case "$name" in
                apple-keyboard-*) ;;
                *) missing=$((missing + 1)) ;;
            esac
        else
            echo "speakboard-screenshot none name=$name reason=not in $dir" >> "$blocks"
            missing=$((missing + 1))
        fi
    done
    lines=$(wc -l < "$blocks" | tr -d ' ')
    chars=$(wc -c < "$blocks" | tr -d ' ')
    if [ "$lines" -gt "$budget" ]; then
        fail "group $group would print $lines lines ($chars characters), over its budget of $budget: the job's log would not fit in the job-log tool's last 5,000 lines. Nothing printed"
    fi
    cat "$blocks"
    echo "speakboard-screenshots: group $group: $count images, $lines lines, $chars characters (budget $budget lines)"
    [ "$missing" -eq 0 ] || fail "$missing screenshots that should be there are missing (see the none lines above)"
}

case "${1:-}" in
    emit)
        [ "$#" -eq 4 ] || fail "usage: $0 emit <name> <file> <what>"
        emit "$2" "$3" "$4"
        ;;
    prepare)
        [ "$#" -eq 3 ] || fail "usage: $0 prepare <screenshots dir> <out dir>"
        prepare "$2" "$3"
        ;;
    print)
        [ "$#" -eq 3 ] || [ "$#" -eq 4 ] || fail "usage: $0 print <prepared dir> <group> [<budget lines>]"
        print_group "$2" "$3" "${4:-4600}"
        ;;
    *)
        echo "usage: $0 prepare <screenshots dir> <out dir> | print <prepared dir> <group> [<budget>] | emit <name> <file> <what>" >&2
        exit 2
        ;;
esac
