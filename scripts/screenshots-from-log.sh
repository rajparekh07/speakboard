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
# GitHub job-log tool returns with return_content, as it is saved to a file
# when it is too long to show: one job's, {"job_id":...,"logs_content":"<the
# log>",...}, or a failed-only fetch by run id, {...,"logs":[{"job_id":...,
# "job_name":...,"logs_content":"<the log>",...}],...}, when that holds exactly
# one job. <out dir> must not exist or be empty: it gets one file per block,
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
#   - in the job-log tool's JSON, anything after the end of the JSON object
#     (two files run together, say), or the logs of more than one job (a
#     failed-only fetch by run id when several jobs failed: fetch one job by
#     its job_id);
#   - an image whose decoded bytes do not have the byte count and SHA-256 its
#     begin line gives (a line lost or a character changed);
#   - no blocks at all.
# It prints each `speakboard-screenshot none` line it finds: those say that a
# run had no screenshot of something (Apple's keyboard, say), and are not a
# failure. Everything it prints, on standard output and in its failure
# messages, has every byte but a newline and printable ASCII shown as "?", so
# no control character from the log reaches the terminal, 8-bit ones (0x80 to
# 0x9f, alone or in UTF-8) included. The images are copied into a new folder
# beside <out dir>, each SHA-256 is checked again there, and only when every
# check has passed does that folder become <out dir>.
#
# Written for the bash 3.2 at /bin/bash and the tools macOS ships, and for the
# Linux Swift image (mawk, GNU coreutils). Its awk runs in the C locale, so it
# reads the log as bytes: macOS's awk, in a UTF-8 locale, stops on a byte that
# is not UTF-8 ("towc: multibyte conversion failure", KEY-69).
set -euo pipefail

# Text from the log that this prints (the none lines, the what text, and the log lines its failure messages quote)
# with every byte but a newline and printable ASCII shown as "?", so a log cannot drive the terminal it is read in:
# an escape sequence's ESC, and 8-bit controls such as 0x9b (CSI), alone or as the second byte of their UTF-8 form.
printable() {
    LC_ALL=C tr -c '\n\040-\176' '?'
}

fail() {
    printf '%s\n' "screenshots-from-log: FAIL: $1" | printable >&2
    exit 1
}

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <saved job log> <out dir>" >&2
    exit 2
fi
log=$1
out=$2
# Without trailing slashes, so the folder beside it and the last move name it plainly.
while [ "${#out}" -gt 1 ] && [ "${out%/}" != "$out" ]; do out=${out%/}; done

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
# the log's length. What is around that string is read as JSON structure
# (brackets outside strings): it must be one of the tool's two shapes, with
# one logs_content string, and nothing after the object's end.
first=$(head -c 1 "$log")
if [ "$first" = "{" ]; then
    LC_ALL=C awk '
        { doc = doc (NR > 1 ? "\n" : "") $0 }
        function hexvalue(hex,    i, value) {
            value = 0
            for (i = 1; i <= length(hex); i++) {
                value = value * 16 + index("0123456789abcdef", tolower(substr(hex, i, 1))) - 1
            }
            return value
        }
        function stop(message) {
            print "screenshots-from-log: FAIL: " message > "/dev/stderr"
            exit 3
        }
        # Walks the JSON text `text` (no unfinished string at its start) from the open brackets `stack`, skipping
        # strings, and returns the brackets still open after it. Sets `closedat` to the position where the last one
        # closed, if one did (and stops there), and stops on a bracket that closes another kind.
        function skeleton(stack, text,    i, n, c, instring, escaped, want) {
            closedat = 0
            n = length(text)
            for (i = 1; i <= n; i++) {
                c = substr(text, i, 1)
                if (instring) {
                    if (escaped) escaped = 0
                    else if (c == "\\") escaped = 1
                    else if (c == "\"") instring = 0
                    continue
                }
                if (c == "\"") instring = 1
                else if (c == "{" || c == "[") stack = stack c
                else if (c == "}" || c == "]") {
                    want = (c == "}") ? "{" : "["
                    if (substr(stack, length(stack)) != want) stop("a " c " that closes nothing open in the JSON: not the job-log tool JSON")
                    stack = substr(stack, 1, length(stack) - 1)
                    if (stack == "") { closedat = i; return stack }
                }
            }
            return stack
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
        # The string ended in piece `last`. What follows it is read as JSON structure up to the next logs_content
        # key, if any (a key: inside a string its quotes would be escaped). The object must close there, with
        # nothing after it but white space.
        function ended(last,    j, tail, cut, segment, rest) {
            tail = after
            for (j = last + 1; j <= n; j++) tail = tail "\\" parts[j]
            cut = index(tail, key)
            segment = cut ? substr(tail, 1, cut - 1) : tail
            skeleton(opens, segment)
            if (closedat) {
                rest = substr(tail, closedat + 1)
                sub(/^[ \t\r\n]+/, "", rest)
                if (rest != "") stop("something follows the end of the JSON object that holds the logs_content string (two files run together?)")
                printf "\n"
                exit 0
            }
            if (cut && shape == "jobs") stop("the job-log tool JSON holds the logs of more than one job (a failed-only fetch by run id, with several failed jobs): fetch one job by its job_id, with return_content true")
            if (cut) stop("a second logs_content string in the same JSON object: not the job-log tool JSON")
            stop("the JSON object that holds the logs_content string has no end: the JSON is cut")
        }
        END {
            key = "\"logs_content\":\""
            start = index(doc, key)
            if (!start) stop("the file starts with { but has no \"logs_content\" string: not the job-log tool JSON")
            # One job: {"job_id":...,"logs_content":"..."...}. A failed-only fetch by run id:
            # {"failed_jobs":...,"logs":[{"job_id":...,"job_name":...,"logs_content":"..."...}],...}.
            opens = skeleton("", substr(doc, 1, start - 1))
            if (opens == "{") shape = "job"
            else if (opens == "{[{" && index(doc, "\"logs\":[") && index(doc, "\"logs\":[") < start) shape = "jobs"
            else stop("the logs_content string is not where the job-log tool JSON puts it")
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
                    stop("an escape \\" c " the JSON reader does not know")
                }
                if (literal(rest)) ended(i)
            }
            stop("the logs_content string has no end: the JSON is cut")
        }
    ' "$log" > "$work/log.txt" 2> "$work/json.err" || {
        printable < "$work/json.err" >&2
        fail "could not read $log as the job-log tool JSON"
    }
else
    cp "$log" "$work/log.txt"
fi

# 2. The blocks. Each block's base64 goes to <k>.b64, and a line per block to
# manifest.tsv: k, name, bytes, sha256, what.
status=0
LC_ALL=C awk -v work="$work" '
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
' "$work/log.txt" 2> "$work/blocks.err" | printable || status=$?
printable < "$work/blocks.err" >&2
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

# 4. The images, copied into a new folder beside <out dir> (on the same file system, so the last move is a rename)
# and checked again there, so nothing in between (another image of the same name on a case-insensitive file system,
# say) can put other bytes under a name. Only when every image has passed does that folder become <out dir>: a
# failure leaves <out dir> as it was.
parent=$(dirname "$out")
mkdir -p "$parent"
stage="$parent/.$(basename "$out").partial-$$"
mkdir "$stage" || fail "could not make the folder $stage to copy the images into"
trap 'rm -rf "$work" "$stage"' EXIT
count=0
while IFS="$(printf '\t')" read -r k name bytes sha what; do
    cp "$work/images/$name" "$stage/$name"
    got_sha=$(sha256 < "$stage/$name")
    [ "$got_sha" = "$sha" ] || fail "$name: SHA-256 $got_sha after the copy, not $sha; $out is left as it was"
    count=$((count + 1))
done < "$work/manifest.tsv"
if [ -d "$out" ]; then
    rmdir "$out" || fail "could not replace the empty folder $out"
fi
mv "$stage" "$out" || fail "could not move $stage to $out"
while IFS="$(printf '\t')" read -r k name bytes sha what; do
    echo "screenshots-from-log: $out/$name: $bytes bytes, SHA-256 $sha, matches. $what" | printable
done < "$work/manifest.tsv"
echo "screenshots-from-log: OK: $count images, each matching the byte count and SHA-256 printed with it"
