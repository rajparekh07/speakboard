#!/usr/bin/env bash
# The core guard. Fails if the core mentions FoundationNetworking or URLSession.
#
# It matches FoundationNetworking as a whole word, and any name that starts
# with URLSession (URLSessionConfiguration, URLSessionTask and so on).
#
# The core is pure Swift with Foundation only (AGENTS.md, ADR-0005). It never
# imports FoundationNetworking and never uses URLSession. The guard matches the
# two names anywhere in the core's files, comments included, so that no form of
# import (`import`, `@preconcurrency import`, `import struct ...`,
# `canImport(...)`) slips past it.
#
# It follows symbolic links (grep -R), because SwiftPM compiles a linked file
# into the core. A link that points nowhere fails the guard. GNU grep -R
# follows every link; BSD grep (macOS) follows them only with -S, so the guard
# adds -S there.
#
# Written for bash 3.2 and BSD tools (macOS) as well as Linux.
#
# Usage: scripts/core-guard.sh [folder]   (default: Sources/SpeakboardCore)
set -euo pipefail

folder="${1:-Sources/SpeakboardCore}"

if [ ! -d "$folder" ]; then
    echo "core guard: FAIL: folder not found: $folder" >&2
    exit 1
fi

follow=-R
case "$(grep --version 2>&1 || true)" in
    *"BSD grep"*) follow=-RS ;;
esac

status=0
matches=$(grep "$follow" -nE -- '\bFoundationNetworking\b|\bURLSession' "$folder") || status=$?

if [ "$status" -eq 0 ]; then
    echo "core guard: FAIL: forbidden name in $folder" >&2
    echo "$matches" >&2
    echo "The core never imports FoundationNetworking and never uses URLSession (AGENTS.md, ADR-0005)." >&2
    exit 1
elif [ "$status" -ne 1 ]; then
    echo "core guard: FAIL: grep could not read $folder (exit $status)" >&2
    exit 1
fi

echo "core guard: OK ($folder has no FoundationNetworking and no URLSession)"
