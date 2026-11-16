// The letters layouts, as data: one per locale (ADR-0010). English is the only
// locale with data. A later language adds an entry here; it does not change the
// layout code, as long as its rows fit the token geometry (row 1 holds 10
// letters edge to edge, row 2 is centred, row 3 is centred between shift and
// delete).

/// A locale a keyboard layout is built for, named by its BCP 47 language identifier.
public struct LayoutLocale: Hashable, Sendable {
    /// The BCP 47 language identifier, for example "en".
    public let identifier: String

    /// The locale with this BCP 47 language identifier.
    public init(identifier: String) {
        self.identifier = identifier
    }

    /// English.
    public static let english = LayoutLocale(identifier: "en")
}

/// The three rows of letter keys of one locale's letters layout, top to bottom, each left to right.
struct LetterRows: Sendable {
    let rows: [[Unicode.Scalar]]

    init(_ rows: [String]) {
        self.rows = rows.map { Array($0.unicodeScalars) }
    }
}

enum LetterLayouts {
    /// One letters layout per locale.
    static let byLocale: [LayoutLocale: LetterRows] = [
        .english: LetterRows(["qwertyuiop", "asdfghjkl", "zxcvbnm"])
    ]
}
