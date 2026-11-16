// The letters layouts, as data: one per locale (ADR-0010). English is the only
// locale with data. A locale with no data of its own uses its language's: the
// part of its identifier before the first "-", "_" or "@", lowercased, so
// "en-US", "en_GB", "en@calendar=gregorian" and "EN" all get "en". A later language adds an entry here; it does not change the
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

    /// The locale's language: its identifier up to the first "-", "_" or "@", lowercased. "en-US" and
    /// "en@calendar=gregorian" give "en".
    public var language: LayoutLocale {
        let subtag = identifier.prefix { $0 != "-" && $0 != "_" && $0 != "@" }
        return LayoutLocale(identifier: subtag.lowercased())
    }
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

    /// The data for `locale`, or else for its language, with the locale the data is for. Nil if neither has any.
    static func rows(for locale: LayoutLocale) -> (LayoutLocale, LetterRows)? {
        locale.entry(in: byLocale)
    }
}

extension LayoutLocale {
    /// The entry for this locale in `table`, or else for its language, with the locale the entry is for. Nil if
    /// neither has one. Every table of per-locale data (layouts, typing rules) is read through this, so they
    /// all fall back the same way.
    func entry<Value>(in table: [LayoutLocale: Value]) -> (LayoutLocale, Value)? {
        if let value = table[self] { return (self, value) }
        let language = self.language
        if let value = table[language] { return (language, value) }
        return nil
    }
}
