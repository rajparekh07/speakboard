#!/usr/bin/env bash
# The core dependency guard. Fails if the SpeakboardCore target in Package.swift
# is not a regular target, declares any dependency (another target, or a
# product of another package), or sets `path`, `sources`, plugins or any build
# setting, if the package could build the core in a language mode other than
# Swift 6 (it sets `swiftLanguageModes`, or its tools version is not 6.x), or
# if the SpeakboardCore product holds any target but SpeakboardCore. Those are
# ways to compile code into the core, or ship code beside it, from outside the
# folder the core guard reads, or to build the core in a mode the imports guard
# does not read it in. It does not close every way: see
# scripts/core-deps-check.swift.
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
