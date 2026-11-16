// What the caller passes with each key event: the little the keyboard can see
// of the text field, and the user's keyboard settings.
//
// The engine does not own the document. On iOS a keyboard extension sees only
// the text just before the insertion point (UITextDocumentProxy's
// documentContextBeforeInput), whether the field has any text (UIKeyInput's
// hasText) and the field's text input traits, and it changes the text only by
// deleting backward and inserting at the insertion point (deleteBackward and
// insertText). The context below is those inputs, as plain values, and the
// engine's output (TypingOutput) is those two operations.
//
// Sources. Apple's reference pages need JavaScript, so each was read on
// 16 Nov 2026 through the JSON behind it
// (developer.apple.com/tutorials/data/documentation/uikit/<page>.json).
// - UITextInputTraits.autocapitalizationType: "This property determines at what
//   times the Shift key is automatically pressed, thereby making the typed
//   character a capital letter. The default value for this property is
//   sentences."
//   https://developer.apple.com/documentation/uikit/uitextinputtraits/autocapitalizationtype
// - UITextAutocapitalizationType and its four cases.
//   https://developer.apple.com/documentation/uikit/uitextautocapitalizationtype
// - UITextInputTraits.returnKeyType: "Setting this property to a different key
//   type changes the visible title of the Return key and typically results in
//   the system dismissing the keyboard when it is pressed. The default value
//   for this property is default."
//   https://developer.apple.com/documentation/uikit/uitextinputtraits/returnkeytype
// - UIReturnKeyType and its twelve cases.
//   https://developer.apple.com/documentation/uikit/uireturnkeytype
// - UITextInputTraits.enablesReturnKeyAutomatically: "The default value for
//   this property is false. If you set it to true, the keyboard disables the
//   Return key when the text entry area contains no text. As soon as the user
//   enters some text, the Return key is automatically enabled."
//   https://developer.apple.com/documentation/uikit/uitextinputtraits/enablesreturnkeyautomatically
// - UIKeyInput.hasText: "true if the backing store has textual content, false
//   otherwise." https://developer.apple.com/documentation/uikit/uikeyinput/hastext
// - App Extension Programming Guide, Custom Keyboard: a custom keyboard "does
//   not have access to most of the general keyboard settings in the Settings
//   app (Settings > General > Keyboard), such as Auto-Capitalization and Enable
//   Caps Lock"; it lists automatic capitalization, "automatic period upon
//   double space" and "caps lock support" among the features with no dedicated
//   API; and its example inserts "\n" through the document proxy for a new
//   line, and deletes with deleteBackward.
//   https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html

/// When the Shift key is pressed automatically: UIKit's `UITextAutocapitalizationType`, case for case.
public enum Autocapitalization: Equatable, Sendable, CaseIterable {
    /// "No automatic text capitalization" (Apple's documentation).
    case none
    /// "Automatic capitalization of the first letter of each word" (Apple's documentation).
    case words
    /// "Automatic capitalization of the first letter of each sentence" (Apple's documentation). UIKit's default.
    case sentences
    /// "Automatic capitalization of all characters" (Apple's documentation).
    case allCharacters
}

/// The kind of Return key the field asks for: UIKit's `UIReturnKeyType`, case for case. Each case's
/// documentation quotes what Apple says the key "displays an indication to" do.
///
/// Apple documents what each kind indicates, not its title or its colour. Key rendering (KEY-15) draws those from
/// measurement (ADR-0003), not from this type. To the engine every kind behaves the same: Return inserts a line
/// break, and the field decides what that does.
public enum ReturnKeyType: Equatable, Sendable, CaseIterable {
    /// "Accept the user's input." UIKit's default.
    case `default`
    /// "Proceed."
    case go
    /// "Search using Google."
    case google
    /// "Join something, such as a meeting."
    case join
    /// "Proceed forward."
    case next
    /// "Plan a route to a location."
    case route
    /// "Perform a search."
    case search
    /// "Send something, such as an email."
    case send
    /// "Search using Yahoo."
    case yahoo
    /// "Accept the user's input."
    case done
    /// "Place an emergency phone call."
    case emergencyCall
    /// "Continue what the user is doing."
    case `continue`
}

/// What the keyboard can see of the text field when a key event happens. The caller passes the context as it is
/// when the event happens, after applying every earlier output.
public struct TypingContext: Equatable, Sendable {
    /// The text before the insertion point, as far as the field shares it: iOS's `documentContextBeforeInput`, or
    /// "" when that is nil. iOS may give only part of the text, so the engine reads only its end, and reads ""
    /// as the start of the text.
    public var textBeforeCursor: String
    /// Whether the field has any text, before or after the insertion point: iOS's `hasText`.
    public var documentHasText: Bool
    /// The field's `autocapitalizationType`.
    public var autocapitalization: Autocapitalization
    /// The field's `returnKeyType`.
    public var returnKeyType: ReturnKeyType
    /// The field's `enablesReturnKeyAutomatically`.
    public var enablesReturnKeyAutomatically: Bool

    /// A context. The trait defaults are UIKit's documented defaults: `sentences`, `default` and false.
    /// `documentHasText` defaults to whether `textBeforeCursor` has any text.
    public init(
        textBeforeCursor: String = "", documentHasText: Bool? = nil,
        autocapitalization: Autocapitalization = .sentences, returnKeyType: ReturnKeyType = .default,
        enablesReturnKeyAutomatically: Bool = false
    ) {
        self.textBeforeCursor = textBeforeCursor
        self.documentHasText = documentHasText ?? !textBeforeCursor.isEmpty
        self.autocapitalization = autocapitalization
        self.returnKeyType = returnKeyType
        self.enablesReturnKeyAutomatically = enablesReturnKeyAutomatically
    }
}

/// The user's keyboard settings that the engine follows: the switches of the same names in iOS's Settings >
/// General > Keyboard. Apple's Custom Keyboard guide says a custom keyboard cannot read Auto-Capitalization or
/// Enable Caps Lock, so all three are inputs. How the keyboard learns them is not decided here.
public struct TypingSettings: Equatable, Sendable {
    /// Auto-Capitalization. When off, Shift is never pressed automatically, whatever the field's
    /// `autocapitalization`. Assumption, not measured: the switch turns off `allCharacters` too.
    public var autoCapitalization: Bool
    /// Enable Caps Lock. When off, a double tap on Shift does not lock it.
    public var capsLock: Bool
    /// "." Shortcut. When off, a double space is two spaces.
    public var periodShortcut: Bool

    /// The settings. Every default is on, as recalled from iOS, not measured.
    public init(autoCapitalization: Bool = true, capsLock: Bool = true, periodShortcut: Bool = true) {
        self.autoCapitalization = autoCapitalization
        self.capsLock = capsLock
        self.periodShortcut = periodShortcut
    }
}
