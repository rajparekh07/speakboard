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
#         apple-<state>-<appearance>.png, for each state letters-upper,
#         letters-lower, caps-lock, numbers and symbols, and each appearance
#             the reference captures of Apple's keyboard (KEY-9), from
#             AppleKeyboardCapturesUITests' attachments in apple-<appearance>/
#             and its speakboard-apple-capture lines in apple-<appearance>.log,
#             cropped the same way at full resolution, lossless PNG. Each one's
#             what text says the simulator, device, iOS version, appearance,
#             state, crop rows, scale and keyboard frame. One that would take
#             more lines than a printing job's budget is cut instead into the
#             fewest bands of rows that each fit one job,
#             apple-<state>-<appearance>-<k>-of-<n>.png, top to bottom, each
#             lossless, each printed by its own job.
#         manifest.txt, a `speakboard-capture` line per capture of Apple's
#             keyboard: name, state, appearance, iOS version, model, pixel
#             size, crop rows, screen size, scale, keyboard frame, bytes,
#             SHA-256, the group that prints it, and the simulator's device
#         groups.txt, the printing jobs' groups, a line each (see print):
#             only those whose images were all made
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
#         manifest         manifest.txt, as plain lines (KEY-9)
#         apple-<state>-<appearance>[-<k>-of-<n>]
#                          that capture of Apple's keyboard, or a band of it
#                          (KEY-9)
#       It fails, printing no block, if the blocks would take more than
#       <budget> lines, or if an image other than the UI test's
#       apple-keyboard-<appearance>.jpg is missing.
#
#   scripts/screenshots-to-log.sh groups <prepared dir>
#       Any platform. Prints groups.txt as a JSON array, for the workflow's
#       matrix of printing jobs.
#
#       The one hard limit is the job-log tool's: it returns at most the last
#       5,000 lines of a job's log. The budget, 4,600 printed lines a group by
#       default, is ours. A screenshots job's own lines (checkout, the artifact
#       fetch, setup and cleanup) were 211 on a475ff9 (4,127 lines in all, 3,916
#       of them printed), so a group at its budget gives a log of about 4,811
#       lines: a margin of about 190 lines for those lines to grow.
#
#       If a full-resolution crop outgrows one job (a busier backdrop, such
#       as a translucent one with the app blurred through it, makes a bigger
#       PNG), it is split over jobs rather than losing pixels: `prepare` does
#       so for the captures of Apple's keyboard (KEY-9), cutting the crop into
#       bands of rows, and the workflow's matrix takes its groups from
#       groups.txt. Our keyboard's keyboard-<appearance>.png is not split: it
#       fails its group's budget instead.
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

# A printing job's budget of printed lines (see print, below).
default_budget=4600

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
    local dir="$1" out="$2" missing=0 appearance state source name ours
    [ "$(uname -s)" = Darwin ] || fail "prepare needs macOS (ImageIO, sips, plutil); print and emit work anywhere"
    command -v sips > /dev/null 2>&1 || fail "sips is not available"
    command -v plutil > /dev/null 2>&1 || fail "plutil is not available"
    [ -d "$dir" ] || fail "no screenshots folder $dir"
    mkdir -p "$out"
    : > "$out/what.tsv"
    : > "$out/none.txt"
    # The printing jobs' groups, one per line (KEY-9): only groups whose images were all made, so a run that
    # fails part way gives its one real failure and the images that exist, not a red job per missing image. Empty
    # until the end, so a prepare that stops on a tool failure names none.
    budget=$default_budget
    groups=""
    : > "$out/groups.txt"
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
    apple_captures
    ours=""
    for name in keyboard-light keyboard-dark; do
        [ -f "$out/$name.png" ] && ours="$ours $name"
    done
    for appearance in light dark; do
        name=ui-$appearance
        for state in shift-auto shift-off shift-on caps-lock; do
            [ -f "$out/$state-$appearance.jpg" ] || name=""
        done
        ours="$ours $name"
    done
    [ -s "$out/manifest.txt" ] && ours="$ours manifest"
    printf '%s\n' $ours $groups > "$out/groups.txt"
    echo "speakboard-screenshots: the screenshots jobs' groups, those whose images were all made:" $ours $groups
    [ "$missing" -eq 0 ] || fail "$missing screenshots that should be there are missing (see the none lines above)"
    echo "speakboard-screenshots: prepared in $out; the screenshots jobs print them"
}

# block_lines <bytes>: the lines emit prints for a file of <bytes> bytes: begin, base64 at 76 a line, end, printed.
block_lines() {
    echo $(((4 * (($1 + 2) / 3) + 75) / 76 + 3))
}

# facts_value <facts line> <key>: a value from a test's speakboard-apple-capture line, with only the characters a
# block's what text allows.
facts_value() {
    printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p" | head -n 1 | tr -cd 'A-Za-z0-9,.:;()/+=-'
}

# facts_device <facts line>: the device, the line's last value, which may hold spaces.
facts_device() {
    printf '%s' "${1##* device=}" | tr -cd 'A-Za-z0-9 ,.:;()/+=-'
}

# describe <facts line> <crop note> <capture name> <part file> <scale>: the what text of a capture of Apple's
# keyboard, or of a band of one. Any platform: the self-test runs it, and prints and recovers a block with it, so a
# character the block refuses fails make check, not a macOS run.
describe() {
    local facts="$1" note="$2" name="$3" part="$4" scale="$5" phrase behind band what
    case "$(facts_value "$facts" state)" in
        letters-upper) phrase="letters, upper case (automatic Shift in the empty field)" ;;
        letters-lower) phrase="letters, lower case (Shift off)" ;;
        caps-lock) phrase="letters, caps lock" ;;
        numbers) phrase="the numbers and punctuation plane (after 123)" ;;
        symbols) phrase="the symbols plane (after the symbols key in the numbers plane)" ;;
        *) fail "the facts line of $name names no state this script knows" ;;
    esac
    case "$(facts_value "$facts" behind)" in
        plain-system-background) behind="only the plain system background of the app" ;;
        *) behind="the screen of the app" ;;
    esac
    what="Apple keyboard reference capture from a simulator, $(facts_device "$facts") ($(facts_value "$facts" model)),"
    what="$what iOS $(facts_value "$facts" ios), $(facts_value "$facts" appearance) appearance, $phrase; crop of $note;"
    what="$what scale $scale (screen $(facts_value "$facts" window) pt); keyboard frame"
    what="$what $(facts_value "$facts" keyboard) pt (x,y,width,height); the field holds: $(facts_value "$facts" field);"
    what="$what behind the keyboard: $behind; full resolution, lossless PNG"
    case "$part" in
        *-of-*.png)
            band=${part%.png}
            what="$what; band ${band#"$name"-} of $name, the bands stacked in order are one image"
            ;;
    esac
    printf '%s\n' "$what"
}

# apple_captures: the reference captures of Apple's keyboard (KEY-9), from $dir/apple-<appearance>/ (the UI test's
# exported attachments) and the facts in $dir/apple-<appearance>.log, into $out, each with its own group, and a line
# each in $out/manifest.txt. Uses prepare's dir, out, tool, missing and groups.
apple_captures() {
    local appearance state name source log facts window width height scale
    local points_wide points_high bytes sha top count pieces fits band parts part first rows what
    : > "$out/manifest.txt"
    for appearance in light dark; do
        log="$dir/apple-$appearance.log"
        for state in letters-upper letters-lower caps-lock numbers symbols; do
            name="apple-$state-$appearance"
            source=$(attachment "$dir/apple-$appearance" "$name")
            facts=$(grep -o "speakboard-apple-capture name=$name\\.png .*" "$log" 2> /dev/null | tail -n 1 || true)
            if [ -z "$source" ] || [ ! -f "$source" ] || [ -z "$facts" ]; then
                none "$name.png" "no capture $name: no attachment in $dir/apple-$appearance, or no facts line in $log"
                missing=$((missing + 1))
                continue
            fi
            window=$(facts_value "$facts" window)
            width=$(pixels "$source" pixelWidth)
            height=$(pixels "$source" pixelHeight)
            points_wide=${window%x*}
            points_high=${window#*x}
            case "$points_wide$points_high" in
                '' | *[!0-9]*) fail "$name: the window size \"$window\" in its facts line is not <width>x<height>" ;;
            esac
            scale=$((width / points_wide))
            [ "$((scale * points_wide))" = "$width" ] && [ "$((scale * points_high))" = "$height" ] \
                || fail "$name: $width x $height pixels is not a whole multiple of the window, $window pt"
            shape "$source" "$out/$name.png" png 1
            bytes=$(wc -c < "$out/$name.png" | tr -d ' ')
            if [ "$(block_lines "$bytes")" -le "$budget" ]; then
                parts="$name.png"
                printf '%s\n' "$note" > "$work/$name.png.note"
            else
                # Too big for one printing job: cut into the fewest bands of rows, 2 or more, that each fit one
                # job, each lossless, each its own group. Bands differ in size (the blurred app above the keys
                # makes a busier PNG), so each cut is measured and the count raised until every band fits.
                echo "speakboard-screenshots: $name.png ($bytes bytes) is over one job's $budget lines: cutting it"
                rm -f "$out/$name.png"
                count=$((height * 2 / 5))
                top=$((height - count))
                pieces=2
                while :; do
                    [ "$pieces" -le 12 ] || fail "$name: even 12 bands are each over one job's $budget lines"
                    parts=""
                    fits=1
                    part=1
                    while [ "$part" -le "$pieces" ]; do
                        first=$((top + count * (part - 1) / pieces))
                        rows=$((top + count * part / pieces - first))
                        band="$name-$part-of-$pieces.png"
                        "$tool" rows "$source" "$out/$band" "$first" "$rows" > "$work/$band.note" \
                            || fail "could not cut rows $first to $((first + rows - 1)) of $source"
                        parts="$parts $band"
                        [ "$(block_lines "$(wc -c < "$out/$band" | tr -d ' ')")" -le "$budget" ] || fits=0
                        part=$((part + 1))
                    done
                    [ "$fits" = 1 ] && break
                    for band in $parts; do rm -f "$out/$band" "$work/$band.note"; done
                    pieces=$((pieces + 1))
                done
                echo "speakboard-screenshots: $name.png cut into $pieces bands of rows, top to bottom:$parts"
            fi
            for part in $parts; do
                note=$(cat "$work/$part.note")
                what=$(describe "$facts" "$note" "$name" "$part" "$scale")
                made "$part" "$what"
                rows=$(printf '%s\n' "$note" | sed -n 's/^rows \([0-9]*\) to \([0-9]*\) of.*/\1-\2/p')
                bytes=$(wc -c < "$out/$part" | tr -d ' ')
                sha=$(sha256 < "$out/$part")
                first=${part%.png}
                groups="$groups $first"
                printf '%s\n' "speakboard-capture name=$part state=$state appearance=$appearance ios=$(facts_value "$facts" ios) model=$(facts_value "$facts" model) pixels=$(pixels "$out/$part" pixelWidth)x$(pixels "$out/$part" pixelHeight) rows=$rows screen=${width}x$height scale=$scale keyboard=$(facts_value "$facts" keyboard) field=$(facts_value "$facts" field) behind=$(facts_value "$facts" behind) bytes=$bytes sha256=$sha group=$first simulator device=$(facts_device "$facts")" \
                    >> "$out/manifest.txt"
            done
        done
    done
    echo "speakboard-screenshots: the manifest of the captures of Apple's keyboard ($(wc -l < "$out/manifest.txt" | tr -d ' ') images):"
    cat "$out/manifest.txt"
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
        manifest)
            [ -f "$dir/manifest.txt" ] || fail "no manifest.txt in $dir: is it a folder the prepare step made?"
            lines=$(wc -l < "$dir/manifest.txt" | tr -d ' ')
            [ "$lines" -le "$budget" ] || fail "the manifest has $lines lines, over the budget of $budget"
            echo "speakboard-screenshots: the manifest of the captures of Apple's keyboard (KEY-9), a line per image:"
            cat "$dir/manifest.txt"
            echo "speakboard-screenshots: group manifest: $lines lines"
            [ "$lines" -gt 0 ] || fail "the manifest is empty: no capture of Apple's keyboard was made"
            return 0
            ;;
        apple-*)
            # KEY-9: a capture of Apple's keyboard, or a band of one, alone in its group.
            case "$group" in
                *[!a-z0-9-]*) fail "no group $group" ;;
            esac
            names="$group.png"
            ;;
        *) fail "no group $group (keyboard-light, keyboard-dark, ui-light, ui-dark, manifest, apple-...)" ;;
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

# groups_json <prepared dir>: the printing jobs' groups from groups.txt, as a JSON array for the workflow's matrix.
groups_json() {
    local dir="$1" group json=""
    [ -s "$dir/groups.txt" ] || fail "no groups.txt in $dir: is it a folder the prepare step made?"
    while read -r group; do
        case "$group" in
            '' | *[!A-Za-z0-9-]*) fail "a group name groups.txt should not have: \"$group\"" ;;
        esac
        json="$json${json:+,}\"$group\""
    done < "$dir/groups.txt"
    printf '[%s]\n' "$json"
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
        print_group "$2" "$3" "${4:-$default_budget}"
        ;;
    describe)
        [ "$#" -eq 6 ] || fail "usage: $0 describe <facts line> <crop note> <capture name> <part file> <scale>"
        describe "$2" "$3" "$4" "$5" "$6"
        ;;
    groups)
        [ "$#" -eq 2 ] || fail "usage: $0 groups <prepared dir>"
        groups_json "$2"
        ;;
    *)
        echo "usage: $0 prepare <screenshots dir> <out dir> | print <prepared dir> <group> [<budget>] | groups <prepared dir> | emit <name> <file> <what>" >&2
        exit 2
        ;;
esac
