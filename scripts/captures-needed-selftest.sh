#!/bin/bash
# Self-test of scripts/captures-needed.sh (KEY-9, review rounds 1 and 2),
# which decides whether a macOS CI run takes the reference captures of Apple's
# keyboard. It makes a throwaway git repository with a main branch, an
# origin/main and a working branch, and checks each case. Needs bash and git,
# as make check (in the Swift image) and make check-native run it.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
needed="$here/captures-needed.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
wrong=0

# The list the captures depend on, as this test expects it. The script's own list (--list) must equal it, so a change
# to either is a change to both; and every entry of the script's list is tested below.
expected="Apple/SpeakboardUITests/
Apple/App/
scripts/sim-keyboard.sh
scripts/screenshots-to-log.sh
scripts/screenshot-image.swift
scripts/captures-needed.sh
.github/workflows/macos.yml
project.yml"
listed=$("$needed" --list)
if [ "$listed" = "$expected" ]; then
    echo "captures-needed self-test: ok: the script's list is the expected list (pass)"
else
    echo "captures-needed self-test: WRONG: the script's list is not the expected list:" >&2
    diff <(printf '%s\n' "$expected") <(printf '%s\n' "$listed") | sed 's/^/    /' >&2 || true
    wrong=$((wrong + 1))
fi

repo="$work/repo"
mkdir -p "$repo"
cd "$repo"
git init -q
git checkout -q -b main
commit() {
    git add -A
    git -c user.name=selftest -c user.email=selftest@example.invalid commit -q -m "$1"
    git rev-parse HEAD
}
mkdir -p scripts Apple/App Apple/SpeakboardUITests docs .github/workflows
echo one > docs/notes.md
echo state > Apple/SpeakboardUITests/AppleKeyboardState.swift
echo sim > scripts/sim-keyboard.sh
base=$(commit base)
git update-ref refs/remotes/origin/main "$base"

# check <description> <want true|false> <text the why line must hold> <arguments...>: the script must answer
# captures=<want>, give exactly two lines, and say <text>.
check() {
    local description="$1" want="$2" because="$3" output
    shift 3
    if ! output=$("$needed" "$@" 2>&1); then
        echo "captures-needed self-test: WRONG: $description (the script failed)" >&2
        echo "$output" | sed 's/^/    /' >&2
        wrong=$((wrong + 1))
    elif [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" != 2 ] || ! grep -qx "captures=$want" <<< "$output" \
        || ! grep -qF -- "$because" <<< "$output"; then
        echo "captures-needed self-test: WRONG: $description (wanted two lines, captures=$want and \"$because\")" >&2
        echo "$output" | sed 's/^/    /' >&2
        wrong=$((wrong + 1))
    else
        echo "captures-needed self-test: ok: $description (captures=$want)"
    fi
}

# Dispatches and other events.
check "a dispatch with captures true" true "dispatched with captures true" workflow_dispatch true "" "$base" work
check "a dispatch with captures false" false "dispatched with captures false" workflow_dispatch false "" "$base" work
check "a dispatch with no input" true "fail safe" workflow_dispatch "" "" "$base" work
check "a dispatch input with a newline and a second captures= line" true "neither true nor false: fail safe" \
    workflow_dispatch "$(printf 'x\ncaptures=false')" "" "$base" work
check "another event" true "fail safe" schedule "" "$base" "$base" work

# Every entry of the script's list: a change under it, on a branch from main, takes the captures.
while IFS= read -r entry; do
    git checkout -q -b "entry$RANDOM" "$base"
    case "$entry" in
        */) path="${entry}selftest-change.swift" ;;
        *) path=$entry ;;
    esac
    mkdir -p "$(dirname "$path")"
    echo "change" >> "$path"
    changed=$(commit "change $entry")
    check "a push that changes $path" true "$entry" push "" "$base" "$changed" work
done <<< "$listed"

# Paths git prints differently.
git checkout -q -b names "$base"
git mv Apple/SpeakboardUITests/AppleKeyboardState.swift Apple/SpeakboardUITests/AppleKeyboardStateCheck.swift
echo edit >> Apple/SpeakboardUITests/AppleKeyboardStateCheck.swift
renamed=$(commit "rename with an edit")
check "a dependency renamed with an edit" true "Apple/SpeakboardUITests/" push "" "$base" "$renamed" main
git checkout -q -b away "$base"
git mv scripts/sim-keyboard.sh docs/sim-keyboard.sh
away=$(commit "rename away")
check "a dependency renamed away from the list" true "scripts/sim-keyboard.sh" push "" "$base" "$away" main
git checkout -q -b accent "$base"
mkdir -p Apple/App
echo x > "Apple/App/R$(printf '\303\251')glages.swift"
accent=$(commit "a non-ASCII name")
check "a file with a non-ASCII name under Apple/App" true "Apple/App/" push "" "$base" "$accent" main
git checkout -q -b quote "$base"
mkdir -p Apple/App
echo x > 'Apple/App/a"b.swift'
quote=$(commit "a double quote in a name")
check "a file with a double quote in its name under Apple/App" true "Apple/App/" push "" "$base" "$quote" main
# KEY-70: a path that differs from an entry only in letter case lands inside it on the Mac's file system.
git checkout -q -b case "$base"
mkdir -p apple/app
echo x > apple/app/Lower.swift
lettercase=$(commit "a path in another letter case")
check "a file under apple/app (Apple/App/ in another letter case)" true "Apple/App/" push "" "$base" "$lettercase" main
git checkout -q -b case2 "$base"
echo x > Project.yml
lettercase2=$(commit "a file named like an entry in another letter case")
check "a file Project.yml (project.yml in another letter case)" true "project.yml" push "" "$base" "$lettercase2" main

# The branch's whole difference from main.
git checkout -q -b work "$base"
echo change >> scripts/sim-keyboard.sh
early=$(commit "an earlier push changes a capture file")
echo two >> docs/notes.md
docs=$(commit "the latest push changes only docs")
check "a branch whose earlier push changed a capture file, the latest only docs" true \
    "the branch changes them since main" push "" "$early" "$docs" work
git checkout -q -b plain "$base"
echo three >> docs/notes.md
plain1=$(commit "docs")
echo four >> docs/notes.md
plain2=$(commit "more docs")
check "a branch with no capture file changed since main" false "neither the push nor the branch since main" \
    push "" "$plain1" "$plain2" plain
check "a branch equal to main" false "neither the push nor the branch since main" push "" "$base" "$base" plain
git update-ref -d refs/remotes/origin/main
check "a docs-only push with no origin/main" true "no origin/main" push "" "$plain1" "$plain2" plain
# KEY-70: an origin/main unrelated to the branch (an orphan commit): no merge base.
git checkout -q --orphan unrelated
git rm -rq --cached . > /dev/null
echo other > unrelated.txt
git add unrelated.txt
orphan=$(git -c user.name=selftest -c user.email=selftest@example.invalid commit -q -m "orphan" && git rev-parse HEAD)
git update-ref refs/remotes/origin/main "$orphan"
check "a docs-only push with an unrelated origin/main (no merge base)" true "no merge base with origin/main: fail safe" \
    push "" "$plain1" "$plain2" plain
git update-ref refs/remotes/origin/main "$base"
git checkout -q -f plain
git clean -qfd

# KEY-70: git diff failing, from a git stub first on PATH that fails `diff` (when STUB_FAIL_FROM is set, only when
# its arguments hold that commit) and runs the real git for everything else.
real_git=$(command -v git)
mkdir -p "$work/stub"
cat > "$work/stub/git" << EOF
#!/bin/bash
for argument in "\$@"; do
    if [ "\$argument" = diff ]; then
        if [ -z "\${STUB_FAIL_FROM:-}" ] || [ "\${*/\$STUB_FAIL_FROM/}" != "\$*" ]; then
            exit 128
        fi
    fi
done
exec "$real_git" "\$@"
EOF
chmod +x "$work/stub/git"
PATH="$work/stub:$PATH" STUB_FAIL_FROM="" check "a push whose git diff fails" true \
    "git could not list what the push changes: fail safe" push "" "$plain1" "$plain2" plain
PATH="$work/stub:$PATH" STUB_FAIL_FROM="$base" check "a push whose git diff of the branch since main fails" true \
    "git could not list what the branch changes from main: fail safe" push "" "$plain1" "$plain2" plain

# A push to main uses its own range only.
check "a push to main whose range changes a capture file" true "the push itself changes" push "" "$base" "$early" main
check "a push to main whose range changes none" false "the push to main changes none" push "" "$early" "$docs" main

# Fail safe.
check "a push with no previous commit (a new branch)" true "fail safe" push "" \
    0000000000000000000000000000000000000000 "$docs" work
check "a push whose previous commit is empty" true "fail safe" push "" "" "$docs" work
check "a push whose previous commit is not in the clone (a force push)" true "not in this clone" push "" \
    1234567890123456789012345678901234567890 "$docs" work

if [ "$wrong" -ne 0 ]; then
    echo "captures-needed self-test: FAIL ($wrong wrong)"
    exit 1
fi
echo "captures-needed self-test: OK"
