#!/bin/bash
# The literal guard (KEY-62): the keyboard's view code types no number used as
# a metric and makes no colour from literals. Every dimension and colour comes
# from the token export, through the generated constants in the core
# (`Metrics`, `Palette`, `Typography`, read through `KeyStyle`).
#
#   scripts/literal-guard.sh [<folder>...]
#       default folders: Apple/Keyboard Apple/KeyboardKit, the code linked into
#       the keyboard extension. Every Swift file in them counts, whatever its
#       name: a file called FooTests.swift there is compiled into the
#       extension too. KeyboardKit's tests (Apple/KeyboardKitTests) are not in
#       the default folders.
#
# It asks the compiler, as the import guards do; it does not read Swift text
# itself. For each Swift file (found with `find -L`, so links are followed):
#   1. `swift-frontend -dump-parse -dump-ast-format json` (Swift 6). The rules
#      are judged on this dump: it is the source as the compiler parsed it, so
#      comments are gone, a number inside a string is part of the string, and
#      every spelling of a number is one literal node. It needs no module, so
#      it works in the Linux image, without UIKit. It fails closed: a missing
#      frontend, a non-zero exit (a syntax error), or output that is not the
#      Swift 6 JSON dump the reader knows fails the guard, as does a literal
#      of a kind the reader does not know.
#   2. `swift-frontend -dump-ast -dump-ast-format json`, only to put each
#      finding on a line: the parse dump locates no expression. Without UIKit
#      this dump always exits non-zero (it cannot type-check UIKit's names),
#      so its exit status is not read. A finding it cannot place is placed at
#      the declaration or statement around it, and says so; it still fails.
#      (On macOS the dump is given the macOS SDK, so the standard library
#      loads.)
#   3. scripts/literal-guard.swift reads both dumps and judges the rules below.
#
# The rules, as the reader applies them to the parse dump:
#   A. Numbers. Every integer or floating-point literal fails, naming the file
#      and line, except where an allowance below lets it through. A negative
#      number (`-2`) is one literal and fails like any other; so does a
#      number in a string interpolation ("\(16)"), which is code, not text.
#   B. Colours made from literals:
#      - every literal (number or string, the allowances included) inside the
#        arguments of a call to UIColor, CGColor, CIColor, NSColor or Color
#        (`UIColor(red: 0.07, ...)`, `UIColor(white: 0, alpha: 0)`,
#        `UIColor.init(...)`, `UIKit.UIColor(...)`, `UIColor(named: "Key")`),
#        to a Core Graphics colour function (CGColorCreate, CGColorCreateSRGB,
#        CGColorCreateGenericRGB, ...Gray, ...GrayGamma2_2, ...CMYK,
#        CGColorCreateCopyWithAlpha, CGColorCreateWithPattern), to
#        `withAlphaComponent`, or to `copy(alpha:)`;
#      - a named colour: a member of one of those types (`UIColor.white`,
#        `UIColor.systemBlue.cgColor`, `CGColor.black`), and a leading-dot
#        member named like one of UIColor's named colours (`.white`, `.clear`,
#        `.label`, `.systemBlue`; the list is in literal-guard.swift);
#      - a playground literal (`#colorLiteral`, and `#imageLiteral` and
#        `#fileLiteral`, which have no place in view code either);
#      - a string that is a hex colour: `#` or `0x` then 3, 4, 6 or 8 hex
#        digits, the whole string (a hex integer such as 0xFFFFFF is a number,
#        rule A).
#      A colour made from the tokens' components, `UIColor(red:
#      CGFloat(cell.color.red), ...)`, passes: its arguments hold no literal.
#
# The allowances, the only literals rule A lets through, none of them inside a
# colour (rule B):
#   1. 0, spelled `0` or `0.0`, anywhere: zero is no length and no offset, the
#      first index and the start of a count.
#   2. 1, spelled `1`, as the whole right-hand side of `+=` or `-=`: stepping
#      a counter or an index. It also lets a one-point nudge written `y += 1`
#      through; that is what this allowance costs.
#   3. 2, spelled `2`, as the right-hand operand of `/`: halving, to centre one
#      thing in another. It also lets any other halving through.
# Any other spelling of these values (`00`, `0x0`, `1.0`, `2.0`, `-0`) fails.
#
# What it does not catch:
#   - A metric or colour that is not a literal in these files: a constant from
#     another module (UIKit's own, such as `UIFont.labelFontSize`, or one
#     declared in the core outside the generated files), a value read from a
#     string (`Double("16")`), or arithmetic on the allowed literals.
#   - A colour type it does not know by name: a typealias of UIColor, or a
#     leading-dot `.init(white: 0, alpha: 0)` whose type comes from context
#     (it holds only allowed literals, so neither rule sees it).
#   - A named colour reached through a name not in the list, or through a
#     variable.
#   - Literals that are not numbers or colours, such as strings used as text,
#     booleans and nil, which it lets through on purpose.
# A leading-dot member named like a colour (`.clear`, `.red`) fails even where
# the type is something else: a false hit is a loud failure, never a silent
# pass.
#
# Runs inside the Swift image (make guard-literals), or natively with
# SWIFT_FRONTEND set by make check-native. Written for bash 3.2 and BSD tools
# (macOS) as well as Linux.
set -euo pipefail

frontend="${SWIFT_FRONTEND:-swift-frontend}"
reader="$(cd "$(dirname "$0")" && pwd)/literal-guard.swift"

fail() {
    echo "literal guard: FAIL: $1" >&2
    exit 1
}

folders=("$@")
if [ "${#folders[@]}" -eq 0 ]; then
    folders=(Apple/Keyboard Apple/KeyboardKit)
fi
command -v "$frontend" > /dev/null 2>&1 || fail "the compiler frontend \`$frontend\` is not available"
command -v swift > /dev/null 2>&1 || fail "\`swift\` is not available to run $reader"
[ -f "$reader" ] || fail "the reader $reader is missing"

# The macOS SDK, so the type-checked dump can load the standard library on a
# Mac. UIKit is not in it, just as it is not in the Linux image.
sdk_args=()
if [ "$(uname -s)" = Darwin ]; then
    sdk=$(xcrun --show-sdk-path 2> /dev/null) || fail "\`xcrun --show-sdk-path\` found no SDK"
    sdk_args=(-sdk "$sdk")
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

: > "$work/files"
for folder in "${folders[@]}"; do
    [ -d "$folder" ] || fail "folder not found: $folder"
    if ! find -L "$folder" -name '*.swift' -type f -print0 >> "$work/files" 2> "$work/find.txt"; then
        echo "literal guard: FAIL: could not list the Swift files in $folder:" >&2
        head -n 20 "$work/find.txt" >&2
        exit 1
    fi
done
files=()
while IFS= read -r -d '' file; do
    files+=("$file")
done < <(sort -z "$work/files")
[ "${#files[@]}" -gt 0 ] || fail "no Swift files in ${folders[*]}"

args=()
n=0
for file in "${files[@]}"; do
    n=$((n + 1))
    if ! "$frontend" -dump-parse -dump-ast-format json "$file" -module-name LiteralGuard -swift-version 6 \
        > "$work/$n.parse.json" 2> "$work/$n.parse.txt"; then
        echo "literal guard: FAIL: the compiler could not parse $file:" >&2
        head -n 20 "$work/$n.parse.txt" >&2
        exit 1
    fi
    # Only for lines: its exit status is not read (see the header).
    "$frontend" -dump-ast -dump-ast-format json "$file" -module-name LiteralGuard -swift-version 6 \
        ${sdk_args[@]+"${sdk_args[@]}"} > "$work/$n.ast.json" 2> /dev/null || true
    args+=("$file" "$work/$n.parse.json" "$work/$n.ast.json")
done

if ! summary=$(swift "$reader" "${args[@]}"); then
    echo "The keyboard's view code types no number used as a metric and makes no colour from literals: every" >&2
    echo "dimension and colour comes from the generated tokens (KeyStyle, Palette, Typography, Metrics). The" >&2
    echo "allowances, and what the guard does not catch, are in scripts/literal-guard.sh." >&2
    exit 1
fi
echo "literal guard: OK (${folders[*]}: $summary; no number but the allowed 0, += 1, -= 1 and / 2, and no colour" \
    "made from literals)"
