import Foundation
import SpeakboardCore
import UIKit

/// What the keyboard reads from and writes to the field it types into: the small part of `UITextDocumentProxy` the
/// typing engine needs (TypingContext.swift says why each). `DocumentProxyField` is the real one; tests use a fake.
@MainActor
public protocol KeyboardTextField: AnyObject {
    /// The text before the insertion point, as far as the field shares it (`documentContextBeforeInput`).
    var documentContextBeforeInput: String? { get }
    /// Whether the field has any text (`hasText`).
    var hasText: Bool { get }
    /// The field's `autocapitalizationType`, as the core's type.
    var fieldAutocapitalization: Autocapitalization { get }
    /// The field's `returnKeyType`, as the core's type.
    var fieldReturnKeyType: ReturnKeyType { get }
    /// The field's `enablesReturnKeyAutomatically`.
    var fieldEnablesReturnKeyAutomatically: Bool { get }
    /// Which document the field is: a new value means another field or another app (`documentIdentifier`), or nil
    /// when the field gives none.
    var documentIdentifier: UUID? { get }
    /// Inserts text at the insertion point.
    func insertText(_ text: String)
    /// Deletes one character backward.
    func deleteBackward()
}

@MainActor
extension KeyboardTextField {
    /// The context the typing engine reads, now.
    var typingContext: TypingContext {
        TypingContext(
            textBeforeCursor: documentContextBeforeInput ?? "", documentHasText: hasText,
            autocapitalization: fieldAutocapitalization, returnKeyType: fieldReturnKeyType,
            enablesReturnKeyAutomatically: fieldEnablesReturnKeyAutomatically)
    }
}

/// The real field: the input view controller's `textDocumentProxy`, read afresh on every call.
@MainActor
public final class DocumentProxyField: KeyboardTextField {
    private weak var controller: UIInputViewController?

    /// The field of `controller`'s text document proxy. It holds the controller weakly.
    public init(controller: UIInputViewController) {
        self.controller = controller
    }

    private var proxy: UITextDocumentProxy? { controller?.textDocumentProxy }

    /// See `KeyboardTextField`.
    public var documentContextBeforeInput: String? { proxy?.documentContextBeforeInput }

    /// See `KeyboardTextField`.
    public var hasText: Bool { proxy?.hasText ?? false }

    /// See `KeyboardTextField`. A field that does not say gets UIKit's documented default, sentences.
    public var fieldAutocapitalization: Autocapitalization {
        switch proxy?.autocapitalizationType ?? .sentences {
        case .none: return .none
        case .words: return .words
        case .sentences: return .sentences
        case .allCharacters: return .allCharacters
        @unknown default: return .sentences
        }
    }

    /// See `KeyboardTextField`. A field that does not say gets UIKit's documented default.
    public var fieldReturnKeyType: ReturnKeyType {
        switch proxy?.returnKeyType ?? .default {
        case .default: return .default
        case .go: return .go
        case .google: return .google
        case .join: return .join
        case .next: return .next
        case .route: return .route
        case .search: return .search
        case .send: return .send
        case .yahoo: return .yahoo
        case .done: return .done
        case .emergencyCall: return .emergencyCall
        case .continue: return .continue
        @unknown default: return .default
        }
    }

    /// See `KeyboardTextField`.
    public var fieldEnablesReturnKeyAutomatically: Bool {
        proxy?.enablesReturnKeyAutomatically ?? false
    }

    /// See `KeyboardTextField`. Read by key-value coding, as an optional: Swift imports the proxy's
    /// `documentIdentifier` as a non-optional `UUID`, and reading it that way traps if the proxy has none, which
    /// crashed the extension in the simulator (KEY-62): it had none when the keyboard appeared. It checks the proxy
    /// answers the property first, so a proxy class without it gives nil rather than an exception. Both have been
    /// observed: the extension logs whether there was one when it appeared and at the first text change, and macOS CI
    /// has logged `appeared document=none`, `appeared document=present` and `first-text-change document=present`.
    public var documentIdentifier: UUID? {
        guard let object = proxy as? NSObject,
            object.responds(to: #selector(getter: UITextDocumentProxy.documentIdentifier))
        else { return nil }
        return object.value(forKey: "documentIdentifier") as? UUID
    }

    /// See `KeyboardTextField`.
    public func insertText(_ text: String) {
        proxy?.insertText(text)
    }

    /// See `KeyboardTextField`.
    public func deleteBackward() {
        proxy?.deleteBackward()
    }
}
