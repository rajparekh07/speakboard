#!/bin/bash
# Self-test of scripts/captures-needed.sh (KEY-9, review round 1, finding 3),
# which decides whether a macOS CI run takes the reference captures of Apple's
# keyboard. It makes a throwaway git repository and checks each case. Needs
# bash and git, as make check (in the Swift image) and make check-native run it.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
needed="$here/captures-needed.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
wrong=0

repo="$work/repo"
mkdir -p "$repo"
cd "$repo"
git init -q
commit() {
    git add -A
    git -c user.name=selftest -c user.email=selftest@example.invalid commit -q -m "$1"
    git rev-parse HEAD
}
mkdir -p scripts Apple/App docs
echo one > docs/notes.md
base=$(commit base)
echo two >> docs/notes.md
docs=$(commit docs)
echo change > scripts/sim-keyboard.sh
script=$(commit script)
echo change > Apple/App/SpeakboardApp.swift
app=$(commit app)

# check <description> <want true|false> <text the why line must hold> <arguments...>
check() {
    local description="$1" want="$2" because="$3" output
    shift 3
    if ! output=$("$needed" "$@" 2>&1); then
        echo "captures-needed self-test: WRONG: $description (the script failed)" >&2
        echo "$output" | sed 's/^/    /' >&2
        wrong=$((wrong + 1))
    elif ! grep -qx "captures=$want" <<< "$output" || ! grep -qF -- "$because" <<< "$output"; then
        echo "captures-needed self-test: WRONG: $description (wanted captures=$want and \"$because\")" >&2
        echo "$output" | sed 's/^/    /' >&2
        wrong=$((wrong + 1))
    else
        echo "captures-needed self-test: ok: $description (captures=$want)"
    fi
}

check "a dispatch with captures true" true "dispatched with captures true" workflow_dispatch true "" "$app"
check "a dispatch with captures false" false "dispatched with captures false" workflow_dispatch false "" "$app"
check "a dispatch with no input" true "fail safe" workflow_dispatch "" "" "$app"
check "a push that changes only docs" false "none of the files" push "" "$base" "$docs"
check "a push that changes scripts/sim-keyboard.sh" true "scripts/sim-keyboard.sh" push "" "$docs" "$script"
check "a push that changes a file under Apple/App" true "Apple/App/SpeakboardApp.swift" push "" "$script" "$app"
check "a push of several commits, one of them a script" true "scripts/sim-keyboard.sh" push "" "$base" "$app"
check "a push with no previous commit (a new branch)" true "fail safe" push "" \
    0000000000000000000000000000000000000000 "$app"
check "a push whose previous commit is empty" true "fail safe" push "" "" "$app"
check "a push whose previous commit is not in the clone (a force push)" true "not in this clone" push "" \
    1234567890123456789012345678901234567890 "$app"
check "another event" true "fail safe" schedule "" "$base" "$app"

if [ "$wrong" -ne 0 ]; then
    echo "captures-needed self-test: FAIL ($wrong wrong)"
    exit 1
fi
echo "captures-needed self-test: OK"
