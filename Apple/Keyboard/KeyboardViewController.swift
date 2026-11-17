import KeyboardKit
import OSLog
import UIKit

/// The keyboard extension's entry point: the one keyboard view (KeyboardKit), its height from the core's layout for
/// this device, and its typing adapter wired to the text document proxy. No networking (MANIFESTO.md, ADR-0012).
final class KeyboardViewController: UIInputViewController {
    private var keyboardView: KeyboardView?
    private var typing: KeyboardTyping?
    private var heightConstraint: NSLayoutConstraint?
    // One line per change of layout, read by scripts/sim-keyboard.sh to check the keyboard ran with the core's
    // height and Full Access. It carries no text the user typed.
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SpeakboardKeyboard", category: "keyboard")
    private var lastLoggedState = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        let typing = KeyboardTyping(field: DocumentProxyField(controller: self), scheduler: TimerTickScheduler())
        let keyboardView = KeyboardView(typing: typing)
        keyboardView.inputModeListHandler = { [weak self] view, event in
            self?.handleInputModeList(from: view, with: event)
        }
        keyboardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboardView)
        // A starting value only, until the view has a screen: viewWillLayoutSubviews replaces it with the core's
        // keyboard.totalHeight for this device on the first layout pass.
        let height = keyboardView.heightAnchor.constraint(equalToConstant: 0)
        // Just below required, so the system's own constraints win while it sets the keyboard up.
        height.priority = UILayoutPriority(rawValue: UILayoutPriority.required.rawValue.nextDown)
        NSLayoutConstraint.activate([
            keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboardView.topAnchor.constraint(equalTo: view.topAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            height,
        ])
        heightConstraint = height
        self.keyboardView = keyboardView
        self.typing = typing
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The keyboard appearing is a new field session: a fresh engine (TypingEngine's notes).
        typing?.beginFieldSession(at: ProcessInfo.processInfo.systemUptime)
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        typing?.textDidChange(at: ProcessInfo.processInfo.systemUptime)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        guard let keyboardView, let screen = view.window?.windowScene?.screen else { return }
        keyboardView.showsInputModeSwitchKey = needsInputModeSwitchKey
        let bounds = screen.bounds
        guard let height = keyboardView.update(screenWidth: bounds.width, screenHeight: bounds.height) else { return }
        if heightConstraint?.constant != CGFloat(height) {
            heightConstraint?.constant = CGFloat(height)
        }
        let deviceClass = keyboardView.layout?.deviceClass.rawValue ?? "none"
        let keys = keyboardView.layout?.keys.count ?? 0
        let state =
            "height=\(height) device=\(deviceClass) keys=\(keys) fullAccess=\(hasFullAccess)"
            + " switchKey=\(needsInputModeSwitchKey)"
        if state != lastLoggedState {
            lastLoggedState = state
            log.notice("speakboard-keyboard \(state, privacy: .public)")
        }
    }
}
