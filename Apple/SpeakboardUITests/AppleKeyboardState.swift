import Foundation

// What the reference captures of Apple's keyboard (KEY-9) check about the keyboard's state at the moment of each
// capture, from the keyboard's accessibility tree. Foundation only, so the same check can be compiled and run on Linux
// against tree lines a run logged (KEY-9 review round 1, finding 1).

/// The five states, in the order the test takes them.
enum AppleKeyboardState: String {
    case lettersUpper = "letters-upper"
    case lettersLower = "letters-lower"
    case capsLock = "caps-lock"
    case numbers = "numbers"
    case symbols = "symbols"
}

/// What the state check needs of one element of the keyboard's tree.
struct KeyFacts {
    /// "key", "button" or another type name.
    let type: String
    let identifier: String
    let label: String
    let value: String
}

/// Why `keys` do not show `state`, or nil when they do:
/// - letters: at least 26 letter keys (a key whose label is one ASCII letter), all upper case for upper case and caps
///   lock, all lower case for lower case; Shift's value "Caps lock on" for caps lock, and no value otherwise;
/// - numbers: the digit keys 0 to 9 and no letter key;
/// - symbols: no digit key, no letter key, and at least 10 keys with one-character labels.
func stateProblem(_ keys: [KeyFacts], _ state: AppleKeyboardState) -> String? {
    let ascii = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
    func isLetter(_ fact: KeyFacts) -> Bool {
        fact.type == "key" && fact.label.count == 1 && fact.label.unicodeScalars.allSatisfy { ascii.contains($0) }
    }
    let letters = keys.filter(isLetter).map(\.label)
    let digits = Set(
        keys.filter { $0.type == "key" && $0.label.count == 1 && $0.label.first?.isNumber == true }.map(\.label))
    switch state {
    case .lettersUpper, .lettersLower, .capsLock:
        guard letters.count >= 26 else { return "\(letters.count) letter keys, not the letters plane" }
        let upper = state != .lettersLower
        let wrong = letters.filter { upper ? $0 != $0.uppercased() : $0 != $0.lowercased() }
        guard wrong.isEmpty else {
            return "letter keys \(wrong.joined()) are \(upper ? "lower" : "upper") case, for \(state.rawValue)"
        }
        let shiftKey = keys.first { $0.identifier.lowercased() == "shift" || $0.label.lowercased() == "shift" }
        guard let shift = shiftKey else { return "no shift key" }
        let capsLock = shift.value.lowercased() == "caps lock on"
        if state == .capsLock && !capsLock {
            return "Shift's value is \"\(shift.value)\", not \"Caps lock on\""
        }
        if state != .capsLock && !shift.value.isEmpty {
            return "Shift's value is \"\(shift.value)\", where \(state.rawValue) has none"
        }
        return nil
    case .numbers:
        guard digits.count == 10 else { return "\(digits.count) digit keys, not 0 to 9" }
        return letters.isEmpty ? nil : "letter keys \(letters.joined()) on the numbers plane"
    case .symbols:
        guard digits.isEmpty else { return "digit keys \(digits.sorted().joined()) on the symbols plane" }
        guard letters.isEmpty else { return "letter keys \(letters.joined()) on the symbols plane" }
        let symbols = keys.filter { $0.type == "key" && $0.label.count == 1 }
        return symbols.count >= 10 ? nil : "only \(symbols.count) one-character keys on the symbols plane"
    }
}
