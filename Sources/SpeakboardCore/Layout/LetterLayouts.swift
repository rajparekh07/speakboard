// The letters layouts, as data: one per locale (ADR-0010). English is the only
// locale with data. A locale with no data of its own uses its language's: the
// part of its identifier before the first "-", "_" or "@", lowercased, so
// "en-US", "en_GB", "en@calendar=gregorian" and "EN" all get "en". A later language adds an entry here; it does not change the
// layout code, as long as its rows fit the token geometry (row 1 holds 10
// letters edge to edge, row 2 is centred, row 3 is centred between shift and
// delete).

/// The three rows of letter keys of one locale's letters layout, top to bottom, each left to right.
struct LetterRows: Sendable {
    let rows: [[Unicode.Scalar]]

    init(_ rows: [String]) {
        self.rows = rows.map { Array($0.unicodeScalars) }
    }
}

enum LetterLayouts {
    /// One letters layout per locale.
    static let byLocale: [KeyboardLocale: LetterRows] = [
        .english: LetterRows(["qwertyuiop", "asdfghjkl", "zxcvbnm"])
    ]

    /// The data for `locale`, or else for its language, with the locale the data is for. Nil if neither has any.
    static func rows(for locale: KeyboardLocale) -> (KeyboardLocale, LetterRows)? {
        locale.entry(in: byLocale)
    }
}
