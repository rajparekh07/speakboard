import KeyboardKit
import OSLog
import UIKit

/// The keyboard extension's entry point. A shell for now: one placeholder view whose height comes from the core's
/// layout for this device. No key drawing, no typing behaviour, no networking (MANIFESTO.md, ADR-0012).
final class KeyboardViewController: UIInputViewController {
    private let keyboardView = PlaceholderKeyboardView(frame: .zero)
    private var heightConstraint: NSLayoutConstraint?
    // One line per change of layout, read by scripts/sim-keyboard.sh to check the keyboard ran with the core's
    // height and Full Access. It carries no text the user typed.
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SpeakboardKeyboard", category: "shell")

    override func viewDidLoad() {
        super.viewDidLoad()
        keyboardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboardView)
        // A starting value only, until the view has a screen: viewWillLayoutSubviews replaces it with the core's
        // keyboard.totalHeight for this device on the first layout pass, so any value would do here.
        let height = keyboardView.heightAnchor.constraint(equalToConstant: 260)
        // Below required, so the system's own constraints win while it sets the keyboard up.
        height.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboardView.topAnchor.constraint(equalTo: view.topAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            height,
        ])
        heightConstraint = height
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        guard let screen = view.window?.windowScene?.screen else { return }
        let bounds = screen.bounds
        guard
            let height = keyboardView.update(
                screenWidth: bounds.width, screenHeight: bounds.height, hasFullAccess: hasFullAccess)
        else { return }
        if heightConstraint?.constant != CGFloat(height) {
            heightConstraint?.constant = CGFloat(height)
        }
        let deviceClass = keyboardView.layout?.deviceClass.rawValue ?? "none"
        let state = "height=\(height) device=\(deviceClass) fullAccess=\(hasFullAccess)"
        if state != lastLoggedState {
            lastLoggedState = state
            log.notice("speakboard-shell \(state, privacy: .public)")
        }
    }

    private var lastLoggedState = ""
}
