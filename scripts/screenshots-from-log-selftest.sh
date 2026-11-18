#!/bin/bash
# Self-test of scripts/screenshots-from-log.sh (KEY-68), which recovers the
# keyboard's screenshots from a saved job log. Each case must pass or fail as
# stated, a failing case with its own message, and a passing case must give
# back the very bytes that went in. The blocks are made by
# scripts/screenshots-to-log.sh emit, the code the workflow prints them with.
#
# Needs bash, awk, base64, fold, cmp and a SHA-256 tool, as make check (in the
# Swift image) and make check-native (on macOS) run it. Written for bash 3.2
# and BSD tools as well as Linux.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
recover="$here/screenshots-from-log.sh"
emit="$here/screenshots-to-log.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
wrong=0

# Two images, not multiples of 3 or 57 bytes, so the last base64 line is short and padded.
head -c 2000 /dev/urandom > "$work/one.bin"
head -c 911 /dev/urandom > "$work/two.bin"
"$emit" emit one.png "$work/one.bin" "a test image; crop of rows 1 to 2 of 3x4, full resolution, PNG" > "$work/one.block"
"$emit" emit two.jpg "$work/two.bin" "another, scaled to 2x2, JPEG" > "$work/two.block"
lines_one=$(wc -l < "$work/one.block" | tr -d ' ')

# check <pass|fail> <description> <message> <log file> [<expected names>...]: runs the recovery on <log file>
# into a new folder. A pass must recover exactly the expected files, each equal to its source; a fail must say
# <message>.
check() {
    local want="$1" description="$2" message="$3" log="$4" output got out name source extra
    shift 4
    out="$work/out$RANDOM$RANDOM"
    if output=$("$recover" "$log" "$out" 2>&1); then got=pass; else got=fail; fi
    if [ "$got" != "$want" ]; then
        echo "screenshots-from-log self-test: WRONG: $description (wanted $want, got $got)" >&2
        echo "$output" | sed 's/^/    /' >&2
        wrong=$((wrong + 1))
        return 0
    fi
    if [ "$want" = fail ]; then
        if ! grep -qF -- "$message" <<< "$output"; then
            echo "screenshots-from-log self-test: WRONG: $description (failed, but not with \"$message\")" >&2
            echo "$output" | sed 's/^/    /' >&2
            wrong=$((wrong + 1))
            return 0
        fi
        if [ -d "$out" ] && [ -n "$(ls -A "$out")" ]; then
            echo "screenshots-from-log self-test: WRONG: $description (failed, but left images in $out)" >&2
            wrong=$((wrong + 1))
            return 0
        fi
    else
        for name in "$@"; do
            case "$name" in
                one.png) source="$work/one.bin" ;;
                *) source="$work/two.bin" ;;
            esac
            if ! cmp -s "$source" "$out/$name"; then
                echo "screenshots-from-log self-test: WRONG: $description ($name is not the bytes that went in)" >&2
                echo "$output" | sed 's/^/    /' >&2
                wrong=$((wrong + 1))
                return 0
            fi
        done
        extra=$(ls -A "$out" | wc -l | tr -d ' ')
        if [ "$extra" != "$#" ]; then
            echo "screenshots-from-log self-test: WRONG: $description ($extra files recovered, wanted $#)" >&2
            wrong=$((wrong + 1))
            return 0
        fi
        if [ -n "$message" ] && ! grep -qF -- "$message" <<< "$output"; then
            echo "screenshots-from-log self-test: WRONG: $description (passed, but did not print \"$message\")" >&2
            echo "$output" | sed 's/^/    /' >&2
            wrong=$((wrong + 1))
            return 0
        fi
    fi
    echo "screenshots-from-log self-test: ok: $description ($want)"
}

# stamp: puts a GitHub-style timestamp before each line, and a byte order mark before the first, as the job log has.
stamp() {
    awk 'BEGIN { bom = "\357\273\277" } { printf "%s2026-11-18T00:41:%02d.%07dZ %s\n", (NR == 1 ? bom : ""), NR % 60, NR, $0 }'
}

# as_json: the log as the job-log tool returns it with return_content: one JSON string, with \n between lines, and
# quotes, backslashes and & (&, as Go writes it) escaped.
as_json() {
    printf '{"job_id":134474019408,"logs_content":"'
    # Joined with split, not gsub: awks differ on backslashes in gsub's replacement.
    awk 'function swap(text, re, with,    parts, n, i, joined) {
            n = split(text, parts, re)
            joined = parts[1]
            for (i = 2; i <= n; i++) joined = joined with parts[i]
            return joined
        }
        BEGIN { bs = "\\" }
        {
            line = swap($0, "\\\\", bs bs)
            line = swap(line, "\"", bs "\"")
            line = swap(line, "&", bs "u0026")
            line = swap(line, "\t", bs "t")
            printf "%s%s", (NR > 1 ? bs "n" : ""), line
        }'
    printf '","message":"Job logs content retrieved successfully","original_length":9}\n'
}

# The lines around the blocks, as a job log has them.
{
    echo '##[group]Run scripts/screenshots-to-log.sh print "$OUT/screenshots"'
    echo 'shell: /bin/bash --noprofile --norc -e -o pipefail {0}'
    echo 'speakboard-ui: +39.9s screenshot shift-auto taken && "quoted" \ back\slash	tab'
} > "$work/before.txt"
echo 'speakboard-screenshots: 2 images printed' > "$work/after.txt"

cat "$work/before.txt" "$work/one.block" "$work/after.txt" > "$work/clean.log"
check pass "a clean block" "one.png: 2000 bytes" "$work/clean.log" one.png

stamp < "$work/clean.log" > "$work/stamped.log"
check pass "a block with the log's timestamps and byte order mark" "" "$work/stamped.log" one.png

sed 's/$/\r/' "$work/stamped.log" > "$work/crlf.log"
check pass "CRLF line ends" "" "$work/crlf.log" one.png

cat "$work/before.txt" "$work/one.block" "$work/two.block" "$work/after.txt" | stamp > "$work/two.log"
check pass "two blocks in one log" "OK: 2 images" "$work/two.log" one.png two.jpg

as_json < "$work/two.log" > "$work/two.json"
check pass "the job-log tool's JSON, with escapes, of a log with two blocks" "OK: 2 images" "$work/two.json" one.png two.jpg

{
    cat "$work/one.block"
    echo "speakboard-screenshot none name=apple-keyboard-dark.jpg reason=the UI test did not find it"
} | stamp > "$work/none.log"
check pass "a none line is printed and is not a failure" \
    "speakboard-screenshot none name=apple-keyboard-dark.jpg reason=the UI test did not find it" "$work/none.log" one.png

# Cut and altered logs.
head -n $((lines_one / 2)) "$work/one.block" | stamp > "$work/cut-inside.log"
check fail "a truncated block: the log ends inside it" "the log ends inside the block one.png" "$work/cut-inside.log"

as_json < "$work/clean.log" > "$work/clean.json"
head -c 2000 "$work/clean.json" > "$work/cut.json"
check fail "a truncated block: the job-log tool's JSON cut short" "the logs_content string has no end" "$work/cut.json"

awk -v drop=5 'NR != drop' "$work/one.block" | stamp > "$work/lost-line.log"
check fail "a truncated block: a whole line lost" "one.png: 1943 bytes, but its begin line says 2000" "$work/lost-line.log"

awk -v at=5 'NR == at { $0 = substr($0, 1, 70) } { print }' "$work/one.block" | stamp > "$work/short-line.log"
check fail "a truncated block: characters lost from a line" "shorter than 76 characters before its last line" \
    "$work/short-line.log"

# The last line loses its padding and a character: still base64 characters, but the size is wrong.
awk -v last=$((lines_one - 2)) 'NR == last { $0 = substr($0, 1, length($0) - 4) } { print }' "$work/one.block" \
    | stamp > "$work/short-last.log"
check fail "a truncated block: the last line cut" "one.png:" "$work/short-last.log"

# One character changed: "A" to "B" or anything else to "A", in the middle of the block.
awk -v at=10 'NR == at { c = substr($0, 30, 1); $0 = substr($0, 1, 29) (c == "A" ? "B" : "A") substr($0, 31) } { print }' \
    "$work/one.block" | stamp > "$work/altered.log"
check fail "an altered block: one character changed" "one.png: SHA-256" "$work/altered.log"

sed 's/bytes=2000/bytes=1999/' "$work/one.block" | stamp > "$work/altered-count.log"
check fail "an altered begin line: the byte count" "one.png: 2000 bytes, but its begin line says 1999" \
    "$work/altered-count.log"

awk 'NR == 3 { print "speakboard-ui: +40.1s a line from elsewhere" } { print }' "$work/one.block" | stamp > "$work/mixed.log"
check fail "other output inside a block" "not base64 of at most 76 characters" "$work/mixed.log"

grep -v -e '^speakboard-screenshot end ' -e '^speakboard-screenshot printed ' "$work/one.block" \
    | cat - "$work/two.block" | stamp > "$work/no-end.log"
check fail "a missing end marker, then another block" "a block begins inside the block one.png, which has no end marker" \
    "$work/no-end.log"

grep -v -e '^speakboard-screenshot end ' -e '^speakboard-screenshot printed ' "$work/two.block" \
    | stamp > "$work/no-end-last.log"
check fail "a missing end marker at the end of the log" "the log ends inside the block two.jpg" "$work/no-end-last.log"

tail -n $((lines_one - 3)) "$work/one.block" | stamp > "$work/tail.log"
check fail "a log cut at its start (a tail), inside a block" "an end marker with no begin" "$work/tail.log"

sed 's/^speakboard-screenshot end name=one.png/speakboard-screenshot end name=two.jpg/' "$work/one.block" \
    | stamp > "$work/wrong-end.log"
check fail "an end marker with another name" "the block one.png ends with another name" "$work/wrong-end.log"

cat "$work/one.block" "$work/one.block" | stamp > "$work/duplicate.log"
check fail "a duplicate name" "the name one.png is used twice" "$work/duplicate.log"

sed 's#name=one.png#name=../one.png#g' "$work/one.block" | stamp > "$work/path.log"
check fail "a name that is a path" "a begin line the reader cannot read" "$work/path.log"

sed 's/sha256=[0-9a-f]*/sha256=abc/' "$work/one.block" | stamp > "$work/short-sha.log"
check fail "a begin line with a short SHA-256" "a begin line the reader cannot read" "$work/short-sha.log"

stamp < "$work/before.txt" > "$work/empty.log"
check fail "no blocks" "no screenshot blocks in the log" "$work/empty.log"

printf '{"job_id":1,"message":"no content"}\n' > "$work/other.json"
check fail "JSON that is not the job-log tool's" "has no \"logs_content\" string" "$work/other.json"

# The out folder must be new or empty.
mkdir -p "$work/full"
: > "$work/full/old.png"
if output=$("$recover" "$work/clean.log" "$work/full" 2>&1); then
    echo "screenshots-from-log self-test: WRONG: a folder that is not empty (wanted fail, got pass)" >&2
    wrong=$((wrong + 1))
elif ! grep -qF "is not empty" <<< "$output"; then
    echo "screenshots-from-log self-test: WRONG: a folder that is not empty (failed, but not with \"is not empty\")" >&2
    echo "$output" | sed 's/^/    /' >&2
    wrong=$((wrong + 1))
else
    echo "screenshots-from-log self-test: ok: a folder that is not empty (fail)"
fi

# The print step of the screenshots jobs: a group from a prepared folder, as the workflow runs it, then recovered.
prepared="$work/prepared"
mkdir -p "$prepared"
for state in shift-auto shift-off shift-on caps-lock; do
    head -c $((700 + ${#state})) /dev/urandom > "$prepared/$state-light.jpg"
    printf '%s\t%s\n' "$state-light.jpg" "UI test screenshot $state, light; half size, JPEG" >> "$prepared/what.tsv"
done
echo "speakboard-screenshot none name=apple-keyboard-light.jpg reason=the UI test did not find Apple's keyboard up" \
    > "$prepared/none.txt"
if "$emit" print "$prepared" ui-light > "$work/group.out" 2>&1; then
    stamp < "$work/group.out" > "$work/group.log"
    if output=$("$recover" "$work/group.log" "$work/group-images" 2>&1) \
        && cmp -s "$prepared/caps-lock-light.jpg" "$work/group-images/caps-lock-light.jpg" \
        && [ "$(ls -A "$work/group-images" | wc -l | tr -d ' ')" = 4 ] \
        && grep -qF "speakboard-screenshot none name=apple-keyboard-light.jpg" <<< "$output" \
        && grep -qF "speakboard-screenshots: group ui-light: 4 images" "$work/group.out"; then
        echo "screenshots-from-log self-test: ok: a group printed by the screenshots job is recovered whole (pass)"
    else
        echo "screenshots-from-log self-test: WRONG: a group printed by the screenshots job was not recovered whole" >&2
        echo "$output" | sed 's/^/    /' >&2
        wrong=$((wrong + 1))
    fi
else
    echo "screenshots-from-log self-test: WRONG: printing a group failed" >&2
    sed 's/^/    /' "$work/group.out" >&2
    wrong=$((wrong + 1))
fi
if "$emit" print "$prepared" ui-light 20 > "$work/over.out" 2>&1; then
    echo "screenshots-from-log self-test: WRONG: a group over its line budget printed" >&2
    wrong=$((wrong + 1))
elif ! grep -qF "over its budget of 20" "$work/over.out" || grep -qF "speakboard-screenshot begin" "$work/over.out"; then
    echo "screenshots-from-log self-test: WRONG: a group over its line budget did not fail as it should" >&2
    sed 's/^/    /' "$work/over.out" >&2
    wrong=$((wrong + 1))
else
    echo "screenshots-from-log self-test: ok: a group over its line budget fails and prints no block (fail)"
fi
rm "$prepared/shift-on-light.jpg"
if "$emit" print "$prepared" ui-light > "$work/missing.out" 2>&1; then
    echo "screenshots-from-log self-test: WRONG: a group with a screenshot missing passed" >&2
    wrong=$((wrong + 1))
elif ! grep -qF "speakboard-screenshot none name=shift-on-light.jpg reason=not in" "$work/missing.out"; then
    echo "screenshots-from-log self-test: WRONG: a group with a screenshot missing did not say which" >&2
    sed 's/^/    /' "$work/missing.out" >&2
    wrong=$((wrong + 1))
else
    echo "screenshots-from-log self-test: ok: a group with a screenshot other than Apple's missing fails (fail)"
fi

# The printer refuses what the block format does not allow.
if "$emit" emit "../x.png" "$work/one.bin" "x" > /dev/null 2>&1; then
    echo "screenshots-from-log self-test: WRONG: the printer took a name that is a path" >&2
    wrong=$((wrong + 1))
else
    echo "screenshots-from-log self-test: ok: the printer refuses a name that is a path (fail)"
fi
if "$emit" emit "x.png" "$work/one.bin" 'Apple\x27s "keyboard" & more' > /dev/null 2>&1; then
    echo "screenshots-from-log self-test: WRONG: the printer took a description the JSON would escape" >&2
    wrong=$((wrong + 1))
else
    echo "screenshots-from-log self-test: ok: the printer refuses a description the JSON would escape (fail)"
fi

if [ "$wrong" -ne 0 ]; then
    echo "screenshots-from-log self-test: FAIL ($wrong wrong)"
    exit 1
fi
echo "screenshots-from-log self-test: OK"
