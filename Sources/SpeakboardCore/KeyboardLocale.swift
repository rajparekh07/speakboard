// The core's locale type, shared by every area that has data per locale
// (ADR-0010): the letters layout and the typing rules today. A locale with no
// data of its own uses its language's: the part of its identifier before the
// first "-", "_" or "@", lowercased, so "en-US", "en_GB",
// "en@calendar=gregorian" and "EN" all get "en".

/// A locale the keyboard is built for, named by its BCP 47 language identifier. Every area of the core that has
/// data per locale (the letters layout, the typing rules) takes this type and reads its data through `entry(in:)`.
public struct KeyboardLocale: Hashable, Sendable {
    /// The BCP 47 language identifier, for example "en".
    public let identifier: String

    /// The locale with this BCP 47 language identifier.
    public init(identifier: String) {
        self.identifier = identifier
    }

    /// English.
    public static let english = KeyboardLocale(identifier: "en")

    /// The locale's language: its identifier up to the first "-", "_" or "@", lowercased. "en-US" and
    /// "en@calendar=gregorian" give "en".
    public var language: KeyboardLocale {
        let subtag = identifier.prefix { $0 != "-" && $0 != "_" && $0 != "@" }
        return KeyboardLocale(identifier: subtag.lowercased())
    }
}

extension KeyboardLocale {
    /// The entry for this locale in `table`, or else for its language, with the locale the entry is for. Nil if
    /// neither has one. Every table of per-locale data (layouts, typing rules) is read through this, so they
    /// all fall back the same way.
    func entry<Value>(in table: [KeyboardLocale: Value]) -> (KeyboardLocale, Value)? {
        if let value = table[self] { return (self, value) }
        let language = self.language
        if let value = table[language] { return (language, value) }
        return nil
    }
}
