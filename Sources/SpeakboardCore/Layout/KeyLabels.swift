// The words on the keys whose label is text: the space bar, the "123" key and
// the return key's titles, as data per locale (ADR-0010), read through
// `KeyboardLocale.entry(in:)` like the letters layout and the typing rules.
//
// Not from the token export, which has no text, and not from Apple's
// documentation, which names what each return key type "displays an
// indication to" do but not its title (TypingContext.swift). The English
// titles are recalled from Apple's keyboard, not measured: the device
// observation for KEY-62 must confirm them.

/// The text on the keyboard's word keys, for one locale.
public struct KeyLabels: Sendable {
    /// The locale whose labels these are: the one the data holds, which can be the language of the locale asked for.
    public let locale: KeyboardLocale
    /// The space bar's label.
    public let space: String
    /// The label of the key that switches to numbers and symbols.
    public let modeSwitch: String
    private let returnTitles: ReturnTitles

    /// The labels for `locale`, or else for its language, or nil if neither has any. English is the only locale with
    /// labels.
    public init?(locale: KeyboardLocale) {
        guard let (dataLocale, labels) = locale.entry(in: Self.byLocale) else { return nil }
        self = KeyLabels(
            locale: dataLocale, space: labels.space, modeSwitch: labels.modeSwitch, returnTitles: labels.returnTitles)
    }

    private init(locale: KeyboardLocale, space: String, modeSwitch: String, returnTitles: ReturnTitles) {
        self.locale = locale
        self.space = space
        self.modeSwitch = modeSwitch
        self.returnTitles = returnTitles
    }

    /// The return key's title for the return key type a field asks for.
    public func returnTitle(_ type: ReturnKeyType) -> String {
        returnTitles.title(type)
    }

    /// The return key's title for each `ReturnKeyType`.
    struct ReturnTitles: Sendable {
        let `default`, go, google, join, next, route, search, send, yahoo, done, emergencyCall, `continue`: String

        func title(_ type: ReturnKeyType) -> String {
            switch type {
            case .default: return `default`
            case .go: return go
            case .google: return google
            case .join: return join
            case .next: return next
            case .route: return route
            case .search: return search
            case .send: return send
            case .yahoo: return yahoo
            case .done: return done
            case .emergencyCall: return emergencyCall
            case .continue: return `continue`
            }
        }
    }

    static let byLocale: [KeyboardLocale: KeyLabels] = [
        // Recalled from Apple's English keyboard, not measured.
        .english: KeyLabels(
            locale: .english, space: "space", modeSwitch: "123",
            returnTitles: ReturnTitles(
                default: "return", go: "go", google: "Google", join: "join", next: "next", route: "route",
                search: "search", send: "send", yahoo: "Yahoo", done: "done", emergencyCall: "Emergency Call",
                continue: "continue"))
    ]
}
