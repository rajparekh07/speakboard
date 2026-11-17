import KeyboardKit
import SwiftUI
import UIKit

/// The containing app. SwiftUI (ADR-0012). For now it explains how to turn the keyboard on, gives a field to try it
/// in, and hosts the harness.
@main
struct SpeakboardApp: App {
    var body: some Scene {
        WindowGroup {
            if HarnessView.isRequested {
                HarnessView()
            } else {
                SetupView()
            }
        }
    }
}

/// How to turn the keyboard on, and a field to try it in.
struct SetupView: View {
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Turn on Speakboard") {
                    Text("Settings › General › Keyboard › Keyboards › Add New Keyboard… › Speakboard")
                    Text("Then tap Speakboard and turn on Allow Full Access.")
                }
                Section("Try it") {
                    TextField("Type here", text: $text)
                        .focused($focused)
                        .accessibilityIdentifier("TryField")
                }
                Section {
                    Text(
                        "Speakboard types English letters, space, delete and return. Numbers, emoji and dictation come later."
                    )
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Speakboard")
        }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-SpeakboardFocusField") {
                focused = true
            }
        }
    }
}

/// The harness: the keyboard's view, embedded in the app at the bottom of the screen at the height the core gives
/// it, for screenshots without enabling the extension. It draws the keys and types nothing. Launch the app with
/// `-SpeakboardHarness`.
struct HarnessView: View {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-SpeakboardHarness")
    }

    // A starting value only: KeyboardViewRepresentable sets the core's height for this screen as soon as the
    // view is in a window.
    @State private var keyboardHeight: CGFloat = 260

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Text("Harness: the keyboard view, hosted in the app")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(8)
            KeyboardViewRepresentable(height: $keyboardHeight)
                .frame(height: keyboardHeight)
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }
}

/// Wraps the keyboard's UIKit view for the harness.
struct KeyboardViewRepresentable: UIViewRepresentable {
    @Binding var height: CGFloat

    func makeUIView(context: Context) -> KeyboardView {
        KeyboardView(typing: nil)
    }

    func updateUIView(_ view: KeyboardView, context: Context) {
        guard let screen = view.window?.windowScene?.screen else {
            DispatchQueue.main.async { updateHeight(view) }
            return
        }
        apply(view, screen: screen)
    }

    private func updateHeight(_ view: KeyboardView) {
        guard let screen = view.window?.windowScene?.screen else { return }
        apply(view, screen: screen)
    }

    private func apply(_ view: KeyboardView, screen: UIScreen) {
        if let coreHeight = view.update(screenWidth: screen.bounds.width, screenHeight: screen.bounds.height),
            CGFloat(coreHeight) != height
        {
            height = CGFloat(coreHeight)
        }
    }
}
