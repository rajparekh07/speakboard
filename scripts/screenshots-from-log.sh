#!/bin/bash
# Recovers the keyboard's screenshots from a saved macOS CI job log (KEY-68).
# The workflow prints them into the log with scripts/screenshots-to-log.sh,
# because agents can read a run's job log but cannot download its artifacts
# (KEY-54).
#
#   scripts/screenshots-from-log.sh <saved job log> <out dir>
#
# <saved job log> is either the plain log (each line maybe starting with the
# timestamp GitHub adds, such as `2026-11-18T00:41:58.1234567Z `, the first
# maybe with a byte order mark; CRLF line ends are taken too), or the JSON the
# GitHub job-log tool returns with return_content, {"job_id":...,
# "logs_content":"<the log>",...}, as it is saved to a file when it is too long
# to show. <out dir> must not exist or be empty: it gets one file per block,
# under the block's name.
#
# It fails, naming the line, and writes no image, when the log is not whole:
#   - a block with no end marker (the log cut inside it, or another block
#     beginning before it ends), or an end marker with no begin (the log cut
#     at its start, as a tail of the log may be);
#   - a line in a block that is not base64, a block line shorter than 76
#     characters before its last line, or a begin line it cannot read;
#   - a name used twice (names that differ only in case count as one), or a
#     name that is not a plain file name;
#   - in the job-log tool's JSON, anything after the logs_content string but
#     the end of that JSON object (two files run together, say);
#   - an image whose decoded bytes do not have the byte count and SHA-256 its
#     begin line gives (a line lost or a character changed);
#   - no blocks at all.
# It prints each `speakboard-screenshot none` line it finds: those say that a
# run had no screenshot of something (Apple's keyboard, say), and are not a
# failure. What it prints from the log has its control characters shown as
# "?". Each image's SHA-256 is checked again after it is copied to <out dir>.
#
# Written for the bash 3.2 at /bin/bash and the tools macOS ships, and for the
# Linux Swift image (mawk, GNU coreutils).
set -euo pipefail

fail() {
    echo "screenshots-from-log: FAIL: $1" >&2
    exit 1
}

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <saved job log> <out dir>" >&2
    exit 2
fi
log=$1
out=$2

[ -f "$log" ] || fail "no file $log"
if [ -e "$out" ]; then
    [ -d "$out" ] || fail "$out is not a folder"
    [ -z "$(ls -A "$out")" ] || fail "$out is not empty: give a new folder, so no image from another run is mistaken for this one's"
fi

sha256() {
    if command -v sha256sum > /dev/null 2>&1; then
        sha256sum | cut -d ' ' -f 1
    elif command -v shasum > /dev/null 2>&1; then
        shasum -a 256 | cut -d ' ' -f 1
    else
        fail "neither sha256sum nor shasum is available"
    fi
}

# Text from the log that this prints (the none lines, the what text) with control characters, an escape
# sequence's ESC among them, shown as "?", so a log cannot drive the terminal it is read in.
printable() {
    # 9 + 21 + 1 characters in the first set, 31 question marks: no tr repeat syntax, which busybox lacks.
    LC_ALL=C tr '\001-\011\013-\037\177' '???????????????????????????????'
}

decode_base64() {
    # GNU and macOS (13 and later) base64 both take -d.
    base64 -d
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# 1. The log as lines. The job-log tool's JSON holds the whole log in one JSON
# string: decode it (\n, \t, \r, \", \\, \/, \b, \f, and \uXXXX; a \u escape
# above ASCII becomes "?", which no block line has). Split at backslashes, so
# each piece after the first starts with an escape, and the work is linear in
# the log's length.
first=$(head -c 1 "$log")
if [ "$first" = "{" ]; then
    awk '
        { doc = doc (NR > 1 ? "\n" : "") $0 }
        function hexvalue(hex,    i, value) {
            value = 0
            for (i = 1; i <= length(hex); i++) {
                value = value * 16 + index("0123456789abcdef", tolower(substr(hex, i, 1))) - 1
            }
            return value
        }
        # Prints text up to an unescaped quote, which ends the string. Returns 1 at the end, with what follows the
        # quote in `after`.
        function literal(text,    quote) {
            quote = index(text, "\"")
            if (quote) {
                printf "%s", substr(text, 1, quote - 1)
                after = substr(text, quote + 1)
                return 1
            }
            printf "%s", text
            return 0
        }
        # The string ended in piece `last`. What follows it must be only the rest of the tool JSON object (the
        # message and the line count: no object, and no second logs_content), so two JSON files run together, or
        # anything else after the first, fail rather than drop what follows.
        function ended(last,    j, tail) {
            tail = after
            for (j = last + 1; j <= n; j++) tail = tail "\\" parts[j]
            sub(/[ \t\r\n]+$/, "", tail)
            if (index(tail, "logs_content") || index(tail, "{") || substr(tail, length(tail)) != "}") {
                print "screenshots-from-log: FAIL: something other than the end of the JSON follows its logs_content string (two files run together?)" > "/dev/stderr"
                exit 3
            }
            printf "\n"
            exit 0
        }
        END {
            key = "\"logs_content\":\""
            start = index(doc, key)
            if (!start) {
                print "screenshots-from-log: FAIL: the file starts with { but has no \"logs_content\" string: not the job-log tool JSON" > "/dev/stderr"
                exit 3
            }
            n = split(substr(doc, start + length(key)), parts, /\\/)
            if (literal(parts[1])) ended(1)
            plain = 0
            for (i = 2; i <= n; i++) {
                piece = parts[i]
                if (plain) { plain = 0; if (literal(piece)) ended(i); continue }
                if (piece == "") { printf "\\"; plain = 1; continue }
                c = substr(piece, 1, 1)
                rest = substr(piece, 2)
                if (c == "n") printf "\n"
                else if (c == "t") printf "\t"
                else if (c == "r") printf "\r"
                else if (c == "\"" || c == "/") printf "%s", c
                else if (c == "b" || c == "f") { }
                else if (c == "u") {
                    code = hexvalue(substr(piece, 2, 4))
                    rest = substr(piece, 6)
                    if (code >= 32 && code < 127) printf "%c", code
                    else if (code == 9) printf "\t"
                    else if (code == 10) printf "\n"
                    else printf "?"
                } else {
                    print "screenshots-from-log: FAIL: an escape \\" c " the JSON reader does not know" > "/dev/stderr"
                    exit 3
                }
                if (literal(rest)) ended(i)
            }
            print "screenshots-from-log: FAIL: the logs_content string has no end: the JSON is cut" > "/dev/stderr"
            exit 3
        }
    ' "$log" > "$work/log.txt" || fail "could not read $log as the job-log tool JSON"
else
    cp "$log" "$work/log.txt"
fi

# 2. The blocks. Each block's base64 goes to <k>.b64, and a line per block to
# manifest.tsv: k, name, bytes, sha256, what.
status=0
awk -v work="$work" '
    function stop(message) {
        print "screenshots-from-log: FAIL: line " NR ": " message > "/dev/stderr"
        failed = 1
        exit 1
    }
    {
        line = $0
        sub(/\r$/, "", line)
        if (NR == 1 && substr(line, 1, 3) == "\357\273\277") line = substr(line, 4)
        if (match(line, /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9][.0-9]*Z /)) {
            line = substr(line, RLENGTH + 1)
        }
        if (substr(line, 1, 22) == "speakboard-screenshot ") {
            rest = substr(line, 23)
            if (substr(rest, 1, 6) == "begin ") {
                if (name != "") stop("a block begins inside the block " name ", which has no end marker (the log is cut, or not whole)")
                count = split(rest, field, " ")
                if (count < 5 || field[2] !~ /^name=[A-Za-z0-9][A-Za-z0-9._-]*$/ || field[3] !~ /^bytes=[1-9][0-9]*$/ \
                    || field[4] !~ /^sha256=[0-9a-f]+$/ || length(field[4]) != 7 + 64 || field[5] !~ /^what=/) {
                    stop("a begin line the reader cannot read: " line)
                }
                name = substr(field[2], 6)
                # Case-insensitively: on the default macOS file system A.png and a.png are one file.
                if (tolower(name) in seen) stop("the name " name " is used twice (names that differ only in case count as one)")
                seen[tolower(name)] = 1
                what = substr(rest, index(rest, " what=") + 6)
                blocks++
                file = work "/" blocks ".b64"
                printf "" > file
                print blocks "\t" name "\t" substr(field[3], 7) "\t" substr(field[4], 8) "\t" what > (work "/manifest.tsv")
                lines = 0
                short = 0
                next
            }
            if (substr(rest, 1, 4) == "end ") {
                if (name == "") stop("an end marker with no begin: " line " (the log is cut at its start?)")
                if (rest != "end name=" name) stop("the block " name " ends with another name: " line)
                if (lines == 0) stop("the block " name " is empty")
                close(file)
                name = ""
                next
            }
            if (substr(rest, 1, 5) == "none ") {
                if (name != "") stop("a none line inside the block " name ", which has no end marker")
                print line
                next
            }
            if (substr(rest, 1, 8) == "printed ") {
                if (name != "") stop("a printed line inside the block " name ", which has no end marker")
                next
            }
            if (name != "") stop("a marker the reader does not know, inside the block " name ": " line)
            next
        }
        if (name == "") next
        if (line !~ /^[A-Za-z0-9+\/]+=*$/ || length(line) > 76) {
            stop("a line in the block " name " that is not base64 of at most 76 characters (altered, or other output mixed in): " substr(line, 1, 100))
        }
        if (short) stop("a line in the block " name " shorter than 76 characters before its last line (characters lost)")
        if (length(line) < 76) short = 1
        print line > file
        lines++
    }
    END {
        if (failed) exit 1
        if (name != "") {
            print "screenshots-from-log: FAIL: the log ends inside the block " name ", with no end marker (the log is cut)" > "/dev/stderr"
            exit 1
        }
        if (blocks == 0) {
            print "screenshots-from-log: FAIL: no screenshot blocks in the log (was the screenshot step reached, and is this the macOS job?)" > "/dev/stderr"
            exit 1
        }
    }
' "$work/log.txt" | printable || status=$?
[ "$status" -eq 0 ] || exit 1

# 3. Each image: decoded, then checked against its byte count and SHA-256.
# Every block is checked before any image is kept.
mkdir -p "$work/images"
while IFS="$(printf '\t')" read -r k name bytes sha what; do
    tr -d '\n' < "$work/$k.b64" | decode_base64 > "$work/images/$name" 2> "$work/decode.err" \
        || fail "$name: not valid base64 ($(head -n 1 "$work/decode.err")): the block is cut or altered"
    got_bytes=$(wc -c < "$work/images/$name" | tr -d ' ')
    [ "$got_bytes" = "$bytes" ] || fail "$name: $got_bytes bytes, but its begin line says $bytes: the block is cut or altered"
    got_sha=$(sha256 < "$work/images/$name")
    [ "$got_sha" = "$sha" ] || fail "$name: SHA-256 $got_sha, but its begin line says $sha: the block is altered"
done < "$work/manifest.tsv"

mkdir -p "$out"
count=0
while IFS="$(printf '\t')" read -r k name bytes sha what; do
    cp "$work/images/$name" "$out/$name"
    # Checked again where it lands, so nothing in between (another image of the same name on a case-insensitive
    # file system, say) can put other bytes under this name.
    got_sha=$(sha256 < "$out/$name")
    [ "$got_sha" = "$sha" ] || fail "$out/$name: SHA-256 $got_sha after the copy, not $sha"
    echo "screenshots-from-log: $out/$name: $bytes bytes, SHA-256 $sha, matches. $what" | printable
    count=$((count + 1))
done < "$work/manifest.tsv"
echo "screenshots-from-log: OK: $count images, each matching the byte count and SHA-256 printed with it"
