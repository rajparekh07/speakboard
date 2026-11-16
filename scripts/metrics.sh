#!/usr/bin/env bash
# The core's metrics tables and the pinned token export they come from.
#
#   scripts/metrics.sh check   fails unless every pinned file's SHA-256 matches
#                              DesignTokens/tokens.pin, and the committed
#                              tables equal what the generator makes from the
#                              pinned export (make check)
#   scripts/metrics.sh write   checks the hashes, then rewrites the tables
#                              (make metrics)
#
# The tables are Sources/SpeakboardCore/Layout/GeneratedMetrics.swift. Nobody
# edits them by hand. Runs inside the Swift image, or natively (make
# check-native), from the repo root.
set -euo pipefail

mode="${1:?usage: scripts/metrics.sh check|write}"
tokens="DesignTokens"
pin="$tokens/tokens.pin"
tables="Sources/SpeakboardCore/Layout/GeneratedMetrics.swift"
work=".build/metrics"

pinned() {  # pinned <key>: the value of "<key>: <value>" in the pin file
    local value
    value=$(sed -n "s/^$1: *//p" "$pin")
    if [ -z "$value" ]; then
        echo "metrics: FAIL: $pin has no \`$1\`" >&2
        exit 1
    fi
    printf '%s' "$value"
}

sha256() {  # sha256 <file>: its SHA-256. macOS has shasum but may have no sha256sum.
    if command -v sha256sum > /dev/null 2>&1; then
        sha256sum "$1"
    elif command -v shasum > /dev/null 2>&1; then
        shasum -a 256 "$1"
    else
        echo "metrics: FAIL: neither sha256sum nor shasum is available" >&2
        exit 1
    fi | cut -d ' ' -f 1
}

verify() {  # verify <file> <pin key>
    local want got
    want=$(pinned "$2")
    got=$(sha256 "$tokens/$1")
    if [ "$got" != "$want" ]; then
        echo "metrics: FAIL: $tokens/$1 has SHA-256 $got, but $pin pins $want (\`$2\`)." >&2
        echo "The pinned export is never edited. To move to a new export, repin it (CONTRIBUTING.md, \"Design tokens\")." >&2
        exit 1
    fi
}

verify speakboard-tokens.json sha256
verify speakboard-tokens.schema.json schema-sha256
verify validate-tokens.py validator-sha256
verify export-format.md format-note-sha256
echo "metrics: OK: the pinned export matches $pin ($(pinned publish-label), sha256 $(pinned sha256))"

mkdir -p "$work"
swift scripts/generate-metrics.swift "$tokens/speakboard-tokens.json" "$pin" > "$work/GeneratedMetrics.swift"

case "$mode" in
    check)
        if ! diff -u "$tables" "$work/GeneratedMetrics.swift" > "$work/diff.txt"; then
            echo "metrics: FAIL: $tables differs from what scripts/generate-metrics.swift makes from the pinned export:" >&2
            head -n 40 "$work/diff.txt" >&2
            echo "The tables are generated, never edited by hand. Run \`make metrics\` to regenerate them." >&2
            exit 1
        fi
        echo "metrics: OK: $tables is what the generator makes from the pinned export"
        ;;
    write)
        cp "$work/GeneratedMetrics.swift" "$tables"
        echo "metrics: wrote $tables"
        ;;
    *)
        echo "usage: scripts/metrics.sh check|write" >&2
        exit 2
        ;;
esac
