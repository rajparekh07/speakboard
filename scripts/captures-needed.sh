#!/bin/bash
# Decides whether a macOS CI run takes the reference captures of Apple's
# keyboard (KEY-9). They cost about 10 minutes and re-photograph a keyboard
# our code does not change, so they run only when asked for or when a push
# changes what they depend on (review round 1, finding 3):
#   - a workflow_dispatch: as its boolean input `captures` says;
#   - a push: when it changes one of the files below;
#   - fail safe: whenever that cannot be worked out (no previous commit, a
#     commit missing from the clone, an unknown event or input), they run.
#
#   scripts/captures-needed.sh <event name> <dispatch input> <before> <head>
#
# Run in a clone with the push's history (the workflow checks out with
# fetch-depth 0). Prints two lines for $GITHUB_OUTPUT: captures=true|false
# and why=<one line saying why>.
set -euo pipefail

if [ "$#" -ne 4 ]; then
    echo "usage: $0 <event name> <dispatch input> <before> <head>" >&2
    exit 2
fi
event=$1
input=$2
before=$3
head=$4

# The files the captures depend on, as git prints their paths.
depends='^(Apple/SpeakboardUITests/AppleKeyboardCapturesUITests\.swift|Apple/SpeakboardUITests/AppleKeyboardState\.swift'
depends="$depends|scripts/sim-keyboard\\.sh|scripts/screenshots-to-log\\.sh|scripts/screenshot-image\\.swift"
depends="$depends|scripts/captures-needed\\.sh|\\.github/workflows/macos\\.yml|project\\.yml|Apple/App/)"

answer() {
    printf 'captures=%s\nwhy=%s\n' "$1" "$2"
    exit 0
}

case "$event" in
    workflow_dispatch)
        case "$input" in
            true) answer true "the run was dispatched with captures true" ;;
            false) answer false "the run was dispatched with captures false" ;;
            *) answer true "the run was dispatched with captures \"$input\", neither true nor false: fail safe" ;;
        esac
        ;;
    push) ;;
    *) answer true "the event $event is neither a push nor a dispatch: fail safe" ;;
esac

case "$before" in
    '' | *[!0-9a-f]* | 0000000000000000000000000000000000000000)
        answer true "the push has no previous commit (\"$before\", a new branch?): fail safe"
        ;;
esac
git cat-file -e "$before^{commit}" 2> /dev/null \
    || answer true "the push's previous commit $before is not in this clone (a force push?): fail safe"
git cat-file -e "$head^{commit}" 2> /dev/null || answer true "the commit $head is not in this clone: fail safe"
changed=$(git diff --name-only "$before" "$head") || answer true "git could not list what the push changes: fail safe"
hits=$(printf '%s\n' "$changed" | grep -E "$depends" | tr '\n' ' ' | sed 's/ *$//' || true)
if [ -n "$hits" ]; then
    answer true "the push changes files the captures depend on: $hits"
fi
answer false "the push changes none of the files the captures depend on"
