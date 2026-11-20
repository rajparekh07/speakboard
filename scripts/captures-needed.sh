#!/bin/bash
# Decides whether a macOS CI run takes the reference captures of Apple's
# keyboard (KEY-9). They cost about 10 minutes and re-photograph a keyboard
# our code does not change, so they run only when asked for or when what they
# depend on changed (review rounds 1 and 2):
#   - a workflow_dispatch: as its boolean input `captures` says;
#   - a push to main: when its own range changes a file they depend on;
#   - a push to another branch: when its own range, or the branch's whole
#     difference from main (from `git merge-base origin/main <head>`),
#     changes one. So while a pull request touches those files, every push on
#     it takes the captures, and the head that is merged has run them;
#   - fail safe: whenever that cannot be worked out (no previous commit, a
#     commit missing from the clone, no origin/main, an unknown event or
#     input), they run.
#
#   scripts/captures-needed.sh <event> <dispatch input> <before> <head> <branch>
#   scripts/captures-needed.sh --list
#
# Run in a clone with the whole history and origin/main (the workflow checks
# out with fetch-depth 0). Prints two lines for $GITHUB_OUTPUT:
# captures=true|false, and why=<one line saying why>, which holds no control
# character or newline whatever the arguments were. --list prints the files
# and folders the captures depend on, one a line.
#
# The paths come from `git diff --no-renames --name-only` with core.quotePath
# off: a rename lists both its old and its new path, and a non-ASCII name is
# printed as it is. Git still quotes a name with a double quote, a backslash
# or a control character, so a leading quote is dropped before the match; a
# control character never reaches the output, which names only the entries.
set -euo pipefail

# The files the captures depend on, and the folders (ending in /) whose every
# file they depend on: the capture test and its helpers (the whole UI test
# folder: the capture test uses say, testStart and keyboardID from
# KeyboardExtensionUITests.swift), the app it photographs through, the scripts
# and the image tool the capture path runs, this script, the workflow and the
# project. Not the core, KeyboardKit or the extension: on a simulator where
# Speakboard is never enabled they do not change Apple's keyboard (a change
# that breaks the UI test target's build fails the typing proof's run anyway).
depends="Apple/SpeakboardUITests/
Apple/App/
scripts/sim-keyboard.sh
scripts/screenshots-to-log.sh
scripts/screenshot-image.swift
scripts/captures-needed.sh
.github/workflows/macos.yml
project.yml"

if [ "${1:-}" = --list ]; then
    printf '%s\n' "$depends"
    exit 0
fi
if [ "$#" -ne 5 ]; then
    echo "usage: $0 <event> <dispatch input> <before> <head> <branch> | --list" >&2
    exit 2
fi
event=$1
input=$2
before=$3
head=$4
branch=$5

# answer <true|false> <why>: prints the two lines, the why with every control character (newlines included) removed.
answer() {
    printf 'captures=%s\nwhy=%s\n' "$1" "$(printf '%s' "$2" | LC_ALL=C tr -d '\000-\037\177')"
    exit 0
}

# hits <from> <to>: the entries of the list that the changes from <from> to <to> touch, space separated. Fails if git
# cannot list the changes.
hits() {
    local changed path entry found=""
    changed=$(git -c core.quotePath=false diff --no-renames --name-only "$1" "$2") || return 1
    while IFS= read -r entry; do
        while IFS= read -r path; do
            path=${path#\"}
            case "$entry" in
                */) [ "${path#"$entry"}" != "$path" ] || continue ;;
                *) [ "$path" = "$entry" ] || continue ;;
            esac
            found="$found $entry"
            break
        done <<< "$changed"
    done <<< "$depends"
    printf '%s' "${found# }"
}

case "$event" in
    workflow_dispatch)
        case "$input" in
            true) answer true "the run was dispatched with captures true" ;;
            false) answer false "the run was dispatched with captures false" ;;
            *) answer true "the run was dispatched with a captures input neither true nor false: fail safe" ;;
        esac
        ;;
    push) ;;
    *) answer true "the event is neither a push nor a dispatch: fail safe" ;;
esac

case "$head" in
    '' | *[!0-9a-f]*) answer true "the head commit is not a commit name: fail safe" ;;
esac
git cat-file -e "$head^{commit}" 2> /dev/null || answer true "the commit $head is not in this clone: fail safe"

# The push's own range.
case "$before" in
    '' | *[!0-9a-f]* | 0000000000000000000000000000000000000000)
        answer true "the push has no previous commit (a new branch?): fail safe"
        ;;
esac
git cat-file -e "$before^{commit}" 2> /dev/null \
    || answer true "the push's previous commit $before is not in this clone (a force push?): fail safe"
found=$(hits "$before" "$head") || answer true "git could not list what the push changes: fail safe"
if [ -n "$found" ]; then
    answer true "the push itself changes what the captures depend on: $found"
fi
if [ "$branch" = main ]; then
    answer false "the push to main changes none of the files the captures depend on"
fi

# A branch other than main: its whole difference from main.
git rev-parse --verify --quiet origin/main > /dev/null \
    || answer true "the push changes none of the files the captures depend on, and there is no origin/main to compare the branch with: fail safe"
base=$(git merge-base origin/main "$head") \
    || answer true "the push changes none of the files the captures depend on, and the branch has no merge base with origin/main: fail safe"
found=$(hits "$base" "$head") || answer true "git could not list what the branch changes from main: fail safe"
if [ -n "$found" ]; then
    answer true "the push changes none of the files the captures depend on, but the branch changes them since main (merge base $base): $found"
fi
answer false "neither the push nor the branch since main (merge base $base) changes the files the captures depend on"
