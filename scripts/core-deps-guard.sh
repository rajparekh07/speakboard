#!/usr/bin/env bash
# The core dependency guard. Fails if the SpeakboardCore target in Package.swift
# declares any dependency (another target, or a product of another package), or
# sets `path`, `sources`, plugins or unsafe flags. Those are ways to compile
# code into the core from outside the folder the core guard reads. It does not
# close every way: see scripts/core-deps-check.swift.
#
# It reads the package as SwiftPM evaluates it (`swift package dump-package`),
# not the text of Package.swift, so how the manifest is written does not hide
# those settings from it.
# Runs inside the Swift image (make guard-deps).
#
# Usage: scripts/core-deps-guard.sh [package folder]   (default: .)
set -euo pipefail

package="${1:-.}"
check="$(cd "$(dirname "$0")" && pwd)/core-deps-check.swift"

if ! description=$(swift package --package-path "$package" dump-package); then
    echo "core dependency guard: FAIL: could not read the package in $package" >&2
    exit 1
fi

printf '%s' "$description" | swift "$check"
