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

# json_string: the log as one JSON string's contents, as the job-log tool writes it with return_content: \n between
# lines, and quotes, backslashes, tabs and & (&, as Go writes it) escaped.
json_string() {
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
}

# as_json: the log as the job-log tool returns it for one job, fetched by its job_id.
as_json() {
    printf '{"job_id":134474019408,"logs_content":"'
    json_string
    printf '","message":"Job logs content retrieved successfully","original_length":9}\n'
}

# as_failed_only <log>...: the logs as the job-log tool returns them for a failed-only fetch by run id, one entry in
# its logs array per log, with the keys in the order the tool writes them.
as_failed_only() {
    local log first=1
    printf '{"failed_jobs":%d,"logs":[' "$#"
    for log in "$@"; do
        [ "$first" = 1 ] || printf ','
        first=0
        printf '{"job_id":%d,"job_name":"screenshots (keyboard-light)","logs_content":"' "$RANDOM"
        json_string < "$log"
        printf '","message":"Job logs content retrieved successfully","original_length":9}'
    done
    printf '],"message":"Retrieved logs for %d failed jobs","return_format":{"content":true,"urls":false},' "$#"
    printf '"run_id":44215231118,"total_jobs":%d}\n' "$#"
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

sed 's/name=one.png/name=ONE.png/g' "$work/one.block" | cat "$work/one.block" - | stamp > "$work/case.log"
check fail "two names that differ only in case" "the name ONE.png is used twice" "$work/case.log"

as_json < "$work/clean.log" > "$work/first.json"
as_json < "$work/two.log" > "$work/second.json"
cat "$work/first.json" "$work/second.json" > "$work/concatenated.json"
check fail "two JSON files run together" "(two files run together?)" "$work/concatenated.json"

# KEY-69: the answer to a failed-only fetch by run id. With one job in its logs array it is recovered; with more
# than one it is refused, saying what to do instead; two such answers run together are still two files.
as_failed_only "$work/two.log" > "$work/failed-one.json"
check pass "a failed-only fetch by run id with one job" "OK: 2 images" "$work/failed-one.json" one.png two.jpg
stamp < "$work/clean.log" > "$work/stamped-one.log"
as_failed_only "$work/stamped-one.log" "$work/two.log" > "$work/failed-two.json"
check fail "a failed-only fetch by run id with two jobs" "fetch one job by its job_id" "$work/failed-two.json"
as_failed_only "$work/stamped-one.log" > "$work/failed-first.json"
cat "$work/failed-first.json" "$work/failed-one.json" > "$work/failed-concatenated.json"
check fail "two failed-only answers run together" "(two files run together?)" "$work/failed-concatenated.json"
# Braces, brackets and the key's own name in the tool's message are text in a string, not structure.
sed 's/"message":"Job logs content retrieved successfully"/"message":"a {[ \\"logs_content\\":\\" ]} b"/' \
    "$work/two.json" > "$work/message.json"
check pass "the job-log tool's JSON with braces and the key's name in its message" "OK: 2 images" \
    "$work/message.json" one.png two.jpg
# The object closed, then a block and a brace planted after it: refused, not read past.
{
    tr -d '\n' < "$work/clean.json"
    printf '\n'
    cat "$work/two.block"
    echo '}'
} > "$work/planted.json"
check fail "a block planted after the end of the job-log tool's JSON" "(two files run together?)" "$work/planted.json"

# only_printable <text>: true when every byte of <text> is a newline or printable ASCII.
only_printable() {
    [ -z "$(printf '%s' "$1" | LC_ALL=C tr -d '\n\040-\176')" ]
}

esc=$(printf '\033')
csi=$(printf '\233')
csi_utf8=$(printf '\302\233')
bel=$(printf '\007')
{
    sed "s/what=a test image/what=a ${esc}[2J test ${csi}2J image/" "$work/one.block"
    echo "speakboard-screenshot none name=x.jpg reason=${esc}[2J gone ${csi_utf8}2J"
} | stamp > "$work/escape.log"
out_escape="$work/out-escape"
if output=$("$recover" "$work/escape.log" "$out_escape" 2>&1) && only_printable "$output" \
    && grep -qF 'reason=?[2J gone ??2J' <<< "$output" && grep -qF 'matches. a ?[2J test ?2J image' <<< "$output" \
    && cmp -s "$work/one.bin" "$out_escape/one.png"; then
    echo "screenshots-from-log self-test: ok: control characters, 8-bit ones too, in a none line and a what text are shown as ? (pass)"
else
    echo "screenshots-from-log self-test: WRONG: control characters in a none line or a what text reached the output" >&2
    printf '%s\n' "$output" | od -c | head -n 20 | sed 's/^/    /' >&2
    wrong=$((wrong + 1))
fi

# KEY-69: the failure messages quote lines of the log; their control characters are shown as ? too.
# check_escaped <description> <message> <log>: the recovery must fail with <message>, printing nothing but newlines
# and printable ASCII.
check_escaped() {
    local output
    if output=$("$recover" "$3" "$work/out$RANDOM$RANDOM" 2>&1); then
        echo "screenshots-from-log self-test: WRONG: $1 (wanted fail, got pass)" >&2
        wrong=$((wrong + 1))
    elif ! grep -qF -- "$2" <<< "$output" || ! only_printable "$output"; then
        echo "screenshots-from-log self-test: WRONG: $1 (did not fail with \"$2\", or printed a control character)" >&2
        printf '%s\n' "$output" | od -c | head -n 20 | sed 's/^/    /' >&2
        wrong=$((wrong + 1))
    else
        echo "screenshots-from-log self-test: ok: $1 (fail)"
    fi
}
sed "s/^speakboard-screenshot begin name=one.png bytes=2000/& ${esc}[2J${csi}2J/" "$work/one.block" | stamp \
    > "$work/escape-begin.log"
check_escaped "a begin line with escape sequences, quoted in the failure message" \
    "a begin line the reader cannot read: speakboard-screenshot begin name=one.png bytes=2000 ?[2J?2J" \
    "$work/escape-begin.log"
awk -v at=4 -v bad="${esc}]0;pwned${bel}" 'NR == at { $0 = bad } { print }' "$work/one.block" | stamp \
    > "$work/escape-line.log"
check_escaped "a block line that sets the terminal's title, quoted in the failure message" \
    "not base64 of at most 76 characters (altered, or other output mixed in): ?]0;pwned?" "$work/escape-line.log"
sed "s/^speakboard-screenshot end name=one.png/& ${csi_utf8}31m/" "$work/one.block" | stamp > "$work/escape-end.log"
check_escaped "an end line with an 8-bit escape in UTF-8, quoted in the failure message" \
    "ends with another name: speakboard-screenshot end name=one.png ??31m" "$work/escape-end.log"

stamp < "$work/before.txt" > "$work/empty.log"
check fail "no blocks" "no screenshot blocks in the log" "$work/empty.log"

printf '{"job_id":1,"message":"no content"}\n' > "$work/other.json"
check fail "JSON that is not the job-log tool's" "has no \"logs_content\" string" "$work/other.json"

# KEY-69: a SHA-256 that differs after the copy leaves the out folder as it was. Nothing on Linux makes a copy
# differ (the case the check is for, two names on a case-insensitive file system, is refused before it), so a
# sha256sum put first on the PATH answers wrongly on its fourth call: the second image's check after the copy, when
# the first image has already been copied. What stays uncovered here is the real cause of such a difference.
fake="$work/fake-bin"
mkdir -p "$fake"
cat > "$fake/sha256sum" << 'EOF'
#!/bin/bash
set -eu
calls=$(($(cat "$FAKE_SHA_CALLS" 2> /dev/null || echo 0) + 1))
echo "$calls" > "$FAKE_SHA_CALLS"
if [ "$calls" = 4 ]; then
    cat > /dev/null
    echo "0000000000000000000000000000000000000000000000000000000000000000  -"
elif [ -n "$FAKE_SHA_REAL" ]; then
    "$FAKE_SHA_REAL"
else
    shasum -a 256
fi
EOF
chmod +x "$fake/sha256sum"
out_copy="$work/out-copy"
mkdir "$out_copy"
if output=$(FAKE_SHA_CALLS="$work/sha-calls" FAKE_SHA_REAL="$(command -v sha256sum || true)" PATH="$fake:$PATH" \
    "$recover" "$work/two.log" "$out_copy" 2>&1); then
    echo "screenshots-from-log self-test: WRONG: a SHA-256 that differs after the copy (wanted fail, got pass)" >&2
    wrong=$((wrong + 1))
elif ! grep -qF "two.jpg: SHA-256 0000000000000000000000000000000000000000000000000000000000000000 after the copy" \
    <<< "$output" || [ -n "$(ls -A "$out_copy")" ] || ls -A "$work" | grep -qF '.out-copy.partial'; then
    echo "screenshots-from-log self-test: WRONG: a SHA-256 that differs after the copy left images, or failed otherwise" >&2
    echo "$output" | sed 's/^/    /' >&2
    ls -lA "$out_copy" | sed 's/^/    /' >&2
    wrong=$((wrong + 1))
else
    echo "screenshots-from-log self-test: ok: a SHA-256 that differs after the copy leaves the out folder empty (fail)"
fi

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
