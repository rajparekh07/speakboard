import QuartzCore
import SpeakboardCore
import UIKit

/// The keyboard's one view, for now a placeholder that proves the core is linked and running: its height is the
/// core's `KeyboardLayout` height for the device, and it prints what the core returned. It draws no keys (that is
/// KEY-23, from measured tokens, never from memory) and handles no typing.
///
/// UIKit and Core Animation only (ADR-0012): one view, its content in layers, no controls.
public final class PlaceholderKeyboardView: UIView {
    /// The layout the view shows, from the core. Nil until `update(screenWidth:screenHeight:)` is called.
    public private(set) var layout: KeyboardLayout?

    /// The text the view shows, line by line. Exposed for tests.
    public private(set) var lines: [String] = []

    private let textLayer = CATextLayer()

    /// A view with no layout yet.
    public override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = UIColor(red: 0.07, green: 0.36, blue: 0.40, alpha: 1)
        textLayer.contentsScale = traitCollection.displayScale
        textLayer.isWrapped = true
        textLayer.alignmentMode = .center
        textLayer.foregroundColor = UIColor.white.cgColor
        textLayer.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        textLayer.fontSize = 15
        layer.addSublayer(textLayer)
        accessibilityIdentifier = "SpeakboardPlaceholderKeyboard"
    }

    /// Not supported: the view is made in code.
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    /// Asks the core for the layout of a screen of `screenWidth` by `screenHeight` points and shows it, with whether
    /// the keyboard has Full Access when that is known (nil in the app's harness). Returns the keyboard's height in
    /// points, the core's `keyboard.totalHeight`, or nil if the core has no English layout.
    @discardableResult
    public func update(screenWidth: Double, screenHeight: Double, hasFullAccess: Bool? = nil) -> Double? {
        let match = DeviceClass.match(screenWidth: screenWidth, screenHeight: screenHeight)
        let orientation = Orientation(screenWidth: screenWidth, screenHeight: screenHeight)
        let layout = KeyboardLayout(locale: .english, deviceClass: match.deviceClass, orientation: orientation)
        self.layout = layout
        lines = Self.lines(
            layout: layout, isExact: match.isExact, screenWidth: screenWidth, screenHeight: screenHeight)
        if let hasFullAccess {
            lines.append("Full Access: \(hasFullAccess ? "on" : "off")")
        }
        textLayer.string = lines.joined(separator: "\n")
        setNeedsLayout()
        return layout?.size.height
    }

    /// Lays out the text in the middle of the view.
    public override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let textHeight = CGFloat(lines.count) * 20
        textLayer.frame = CGRect(
            x: 16, y: max(0, (bounds.height - textHeight) / 2), width: max(0, bounds.width - 32), height: textHeight)
        CATransaction.commit()
    }

    static func lines(layout: KeyboardLayout?, isExact: Bool, screenWidth: Double, screenHeight: Double) -> [String] {
        guard let layout else {
            return ["Speakboard placeholder", "The core has no English layout"]
        }
        let match = isExact ? "" : " (nearest to \(Int(screenWidth))x\(Int(screenHeight)))"
        return [
            "Speakboard · placeholder keyboard",
            "Core layout: \(layout.deviceClass.rawValue) \(layout.orientation.rawValue)\(match)",
            "\(Int(layout.size.width)) x \(Int(layout.size.height)) pt, \(layout.keys.count) keys",
            "Keys are drawn in KEY-23",
        ]
    }
}
