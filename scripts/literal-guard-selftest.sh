#!/bin/bash
# Self-test of scripts/literal-guard.sh: each case must pass or fail as stated,
# and each failing case must fail with its own message (for a finding, the
# file, line and column, and what was found), so a broken guard cannot pass
# silently and a case cannot pass by failing for another reason.
#
# Needs the compiler frontend (SWIFT_FRONTEND, or swift-frontend on PATH) and
# `swift`, as make check and make check-native run it. Written for bash 3.2
# and BSD tools as well as Linux.
set -euo pipefail

guard="$(cd "$(dirname "$0")" && pwd)/literal-guard.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
wrong=0

# check pass|fail <description> <message> <command...>
check() {
    local want="$1" description="$2" message="$3"
    shift 3
    local output got
    if output=$("$@" 2>&1); then got=pass; else got=fail; fi
    if [ "$got" != "$want" ]; then
        echo "literal guard self-test: WRONG: $description (wanted $want, got $got)" >&2
        echo "$output" | sed 's/^/    /' >&2
        wrong=$((wrong + 1))
    elif [ "$want" = fail ] && ! grep -qF -- "$message" <<< "$output"; then
        echo "literal guard self-test: WRONG: $description (failed, but not with \"$message\")" >&2
        echo "$output" | sed 's/^/    /' >&2
        wrong=$((wrong + 1))
    else
        echo "literal guard self-test: ok: $description ($want)"
    fi
}

# swift_case <pass|fail> <description> <source> [message]: one Swift file, Case.swift (or the name in $NAME).
swift_case() {
    local dir="$work/case$RANDOM$RANDOM"
    mkdir -p "$dir"
    printf '%s\n' "$3" > "$dir/${NAME:-Case.swift}"
    check "$1" "$2" "${4:-}" "$guard" "$dir"
}

# View code as the keyboard will have it: colours from the tokens' components, sizes from the metrics, and the
# allowed literals: 0, `+= 1`, `-= 1` and `/ 2`.
swift_case pass "view code that takes every number and colour from the tokens" 'import QuartzCore
import SpeakboardCore
import UIKit

// A comment may say 16 pt, #FFFFFF or UIColor(red: 1, green: 1, blue: 1, alpha: 1).
/* So may a block comment: 42 */
/// And a doc comment: 0.07.
final class KeysView: UIView {
    private var layers: [CALayer] = []

    func color(_ cell: ColorCell) -> UIColor {
        UIColor(
            red: CGFloat(cell.color.red), green: CGFloat(cell.color.green), blue: CGFloat(cell.color.blue),
            alpha: CGFloat(cell.color.alpha))
    }

    func draw(_ layout: KeyboardLayout, appearance: Appearance) {
        var index = 0
        while index < layout.keys.count {
            let key = layout.keys[index]
            let style = KeyStyle.of(key.kind, returnKey: .standard, appearance: appearance, metrics: layout.metrics)
            let face = CALayer()
            face.backgroundColor = color(style.fill).cgColor
            face.cornerRadius = CGFloat(style.cornerRadius.value)
            face.shadowOffset = CGSize(width: 0, height: CGFloat(style.shadow.offsetY.value))
            face.frame = CGRect(x: key.frame.x, y: key.frame.y, width: key.frame.width, height: key.frame.height)
            let label = CATextLayer()
            label.fontSize = CGFloat(style.label.size.value)
            label.frame.origin.y = (face.bounds.height - label.fontSize) / 2
            label.string = "Key \(index): 16 pt, #FFFFFF"
            layers.append(face)
            index += 1
        }
        var remaining = layers.count
        remaining -= 1
        let none: CGFloat = 0.0
        isHidden = remaining < 0 || none > 0 || layers.isEmpty == false
    }
}'
swift_case pass "a number inside a string" 'let title = "16 pt, 0.07, -2"'
swift_case pass "a number inside a multi-line string, spelled like the dump" 'let s = """
    (integer_literal_expr value="99")
    15.5
    """'
swift_case pass "a word made of hex digits in a string (not #-prefixed)" 'let word = "face"'
swift_case pass "booleans and nil" 'let a: Bool? = true
let b: Int? = nil'
swift_case pass "no literal at all" 'import UIKit'

# Rule A: numbers.
swift_case fail "an integer metric" 'import UIKit
let view = UIView()
func f() { view.layer.cornerRadius = 8 }' "Case.swift:3:38: a number typed into view code: 8"
swift_case fail "a float metric" 'let size = 15.5' "Case.swift:1:12: a number typed into view code: 15.5"
swift_case fail "a negative number" 'let offset = -2' "Case.swift:1:14: a number typed into view code: -2"
swift_case fail "a negative zero (not the allowed spelling)" 'let z = -0' "a number typed into view code: -0"
swift_case fail "a hex integer" 'let h = 0x10' "Case.swift:1:9: a number typed into view code: 0x10"
swift_case fail "a number in a string interpolation (code, not text)" 'let s = "\(16) pt"' \
    "Case.swift:1:12: a number typed into view code: 16"
swift_case fail "a number on the second line of a statement" 'let r = CGRect(
    x: 0, y: 0, width: 300, height: 0)' "Case.swift:2:24: a number typed into view code: 300"
swift_case fail "an enum raw value" 'enum E: Int { case a = 7 }' "Case.swift:1:24: a number typed into view code: 7"
swift_case fail "a default argument" 'func f(x: Double = 13) -> Double { x }' \
    "Case.swift:1:20: a number typed into view code: 13"
swift_case fail "a number in a closure" 'import UIKit
func f(_ v: UIView) { UIView.animate(withDuration: 0.25) { v.alpha = 0.5 } }' \
    "Case.swift:2:52: a number typed into view code: 0.25"
swift_case fail "the same number twice, each on its line" 'let a = 15
let b = 15' "Case.swift:2:9: a number typed into view code: 15"
swift_case fail "the same number allowed in one place and not in another: the line is the right one" 'var i = 0
let w = 1
func f() { i += 1 }' "Case.swift:2:9: a number typed into view code: 1."

# The allowances, and their edges.
swift_case pass "allowance 1: 0 and 0.0, and 0 as an index" 'let a = 0
let b: Double = 0.0
let names = ["q"]
let first = names[0]'
swift_case fail "allowance 1 edge: 0 is allowed, but the 1 in [1][0] is not" 'let c = [1][0]' \
    "Case.swift:1:10: a number typed into view code: 1"
swift_case fail "allowance 1 edge: 00 is not the spelling 0" 'let a = 00' "a number typed into view code: 00"
swift_case fail "allowance 1 edge: 0.00 is not the spelling 0.0" 'let a = 0.00' "a number typed into view code: 0.00"
swift_case pass "allowance 2: += 1 and -= 1" 'var i = 0
func f() { i += 1; i -= 1 }'
swift_case fail "allowance 2 edge: + 1 is not += 1" 'var i = 0
let j = i + 1' "Case.swift:2:13: a number typed into view code: 1"
swift_case fail "allowance 2 edge: = 1" 'var i = 0
func f() { i = 1 }' "Case.swift:2:16: a number typed into view code: 1"
swift_case fail "allowance 2 edge: += 1 * w (1 is not the whole right-hand side)" 'var i = 0
let w = 0
func f() { i += 1 * w }' "Case.swift:3:17: a number typed into view code: 1"
swift_case fail "allowance 2 edge: += 2" 'var i = 0
func f() { i += 2 }' "Case.swift:2:17: a number typed into view code: 2"
swift_case fail "allowance 2 edge: += 1.0" 'var i = 0.0
func f() { i += 1.0 }' "a number typed into view code: 1.0"
swift_case pass "allowance 3: / 2" 'let w = 0.0
let half = w / 2'
swift_case fail "allowance 3 edge: / 2.0" 'let w = 0.0
let half = w / 2.0' "Case.swift:2:16: a number typed into view code: 2.0"
swift_case fail "allowance 3 edge: * 2" 'let w = 0.0
let twice = w * 2' "Case.swift:2:17: a number typed into view code: 2"
swift_case fail "allowance 3 edge: / 3" 'let w = 0.0
let third = w / 3' "Case.swift:2:17: a number typed into view code: 3"
swift_case fail "allowance 3 edge: / (2)" 'let w = 0.0
let half = w / (2)' "Case.swift:2:17: a number typed into view code: 2"

# Rule B: colours made from literals.
swift_case fail "a colour initialiser" 'import UIKit
let c = UIColor(red: 0.07, green: 0.36, blue: 0.40, alpha: 1)' \
    "Case.swift:2:22: a colour made from literals: 0.07 in a call to UIColor"
swift_case fail "a colour initialiser with only zeros (no allowance in a colour)" 'import UIKit
let c = UIColor(white: 0, alpha: 0)' "Case.swift:2:24: a colour made from literals: 0 in a call to UIColor"
swift_case fail "UIColor.init with literals" 'import UIKit
let c = UIColor.init(white: 0, alpha: 0)' "a colour made from literals: 0 in a call to UIColor"
swift_case fail "UIKit.UIColor with literals" 'import UIKit
let c = UIKit.UIColor(white: 0, alpha: 0)' "a colour made from literals: 0 in a call to UIColor"
swift_case fail "a CGColor from components" 'import UIKit
let c = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0)' "a colour made from literals: 0 in a call to CGColor"
swift_case fail "a Core Graphics colour function" 'import UIKit
let c = CGColorCreateSRGB(0, 0, 0, 0)' "a colour made from literals: 0 in a call to CGColorCreateSRGB"
swift_case fail "withAlphaComponent(0)" 'import UIKit
let c = UIColor.label.withAlphaComponent(0)' "a colour made from literals: 0 in a call to withAlphaComponent"
swift_case fail "copy(alpha: 0)" 'import UIKit
let c = UIColor.label.cgColor.copy(alpha: 0)' "a colour made from literals: 0 in a call to copy"
swift_case fail "a named colour asset" 'import UIKit
let c = UIColor(named: "KeyFill")' "Case.swift:2:24: a colour made from literals: the string \"KeyFill\" in a call to UIColor"
swift_case fail "a named colour: UIColor.white" 'import UIKit
let c = UIColor.white' "Case.swift:2:9: a named colour: UIColor.white"
swift_case fail "a named colour on the way to a CGColor" 'import UIKit
let c = UIColor.systemBlue.cgColor' "a named colour: UIColor.systemBlue"
swift_case fail "a named CGColor" 'import UIKit
let c = CGColor.black' "a named colour: CGColor.black"
swift_case fail "a leading-dot named colour" 'import UIKit
let v = UIView()
func f() { v.backgroundColor = .clear }' "Case.swift:3:32: a named colour: .clear"
swift_case fail "#colorLiteral" 'let c = #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1)' \
    "Case.swift:1:9: a playground literal (#colorLiteral)"
swift_case fail "a hex colour string" 'let c = "#FFFFFF"' "Case.swift:1:9: a colour as a hex string: \"#FFFFFF\""
swift_case fail "a hex colour string with 0x and alpha" 'let c = "0xACB1BAFF"' "a colour as a hex string"
swift_case pass "a colour from a token's components" 'import SpeakboardCore
import UIKit
let cell = Palette.of(.light).keyLetterFill
let c = UIColor(red: CGFloat(cell.color.red), green: CGFloat(cell.color.green), blue: CGFloat(cell.color.blue),
    alpha: CGFloat(cell.color.alpha))'

# Every file in the folders counts: a test-named file is compiled into the extension too.
NAME=KeyboardKitTests.swift swift_case fail "a literal in a file named like a test" 'let x = 15' \
    "KeyboardKitTests.swift:1:9: a number typed into view code: 15"

# Failing closed.
swift_case fail "a file the frontend cannot parse" 'let x = (1 +' "the compiler could not parse"
mkdir -p "$work/ok" "$work/bad" "$work/empty" "$work/linked" "$work/elsewhere"
printf 'let a = 0\n' > "$work/ok/A.swift"
printf 'let b = 16\n' > "$work/bad/B.swift"
check fail "two folders, the second with a literal" "B.swift:1:9: a number typed into view code: 16" \
    "$guard" "$work/ok" "$work/bad"
printf 'let r = 16\n' > "$work/elsewhere/Real.swift"
ln -s ../elsewhere/Real.swift "$work/linked/Link.swift"
check fail "a symlinked Swift file with a literal" "Link.swift:1:9: a number typed into view code: 16" \
    "$guard" "$work/linked"
check fail "no Swift files" "no Swift files" "$guard" "$work/empty"
check fail "a missing folder" "folder not found" "$guard" "$work/missing"
check fail "no compiler frontend" "is not available" env SWIFT_FRONTEND="$work/no-such-frontend" "$guard" "$work/ok"
printf '#!/bin/bash\nexit 1\n' > "$work/failing-frontend"
chmod +x "$work/failing-frontend"
check fail "a frontend that fails" "the compiler could not parse" env SWIFT_FRONTEND="$work/failing-frontend" \
    "$guard" "$work/ok"
printf '#!/bin/bash\necho "(source_file \\"A.swift\\")"\n' > "$work/text-frontend"
chmod +x "$work/text-frontend"
check fail "a frontend that prints a dump the reader does not know" "is not the Swift 6 JSON AST dump" \
    env SWIFT_FRONTEND="$work/text-frontend" "$guard" "$work/ok"
printf '#!/bin/bash\nexit 0\n' > "$work/silent-frontend"
chmod +x "$work/silent-frontend"
check fail "a frontend that prints nothing" "is not the Swift 6 JSON AST dump" \
    env SWIFT_FRONTEND="$work/silent-frontend" "$guard" "$work/ok"
# The parse dump with a literal of a kind the reader does not know.
real_frontend="${SWIFT_FRONTEND:-swift-frontend}"
printf '#!/bin/bash\n"%s" "$@" | sed "s/integer_literal_expr/future_literal_expr/g"\n' "$real_frontend" \
    > "$work/future-frontend"
chmod +x "$work/future-frontend"
check fail "a literal of a kind the reader does not know" "a literal of a kind the guard does not know" \
    env SWIFT_FRONTEND="$work/future-frontend" "$guard" "$work/bad"
# No type-checked dump: the finding still fails, placed at its statement.
printf '#!/bin/bash\nfor a in "$@"; do [ "$a" = -dump-ast ] && exit 1; done\nexec "%s" "$@"\n' "$real_frontend" \
    > "$work/no-ast-frontend"
chmod +x "$work/no-ast-frontend"
check fail "no type-checked dump to place a finding" \
    "B.swift:1: (in the declaration or statement starting here; the compiler gives no closer place): a number typed into view code: 16" \
    env SWIFT_FRONTEND="$work/no-ast-frontend" "$guard" "$work/bad"

if [ "$wrong" -ne 0 ]; then
    echo "literal guard self-test: FAIL ($wrong wrong)"
    exit 1
fi
echo "literal guard self-test: OK"
