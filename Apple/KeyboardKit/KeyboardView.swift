import QuartzCore
import SpeakboardCore
import UIKit

/// The keyboard's one view (ADR-0012): it owns every touch and draws every key as Core Animation layers, with no
/// per-key views, controls or gesture recognisers.
///
/// Every frame comes from the core's `KeyboardLayout` for the screen's device class and orientation, and every
/// colour, size, weight, radius and the shadow from `KeyStyle` (the generated tokens), for the trait collection's
/// light or dark appearance; nothing here types a number or a colour (the literal guard checks it). Where the token
/// export gives nothing, this draws nothing in its place:
/// - Letter keys, the space bar and the prominent return key show no pressed face: the export has none (Apple shows
///   a popup over a letter; popups are KEY-23). Function keys use `key.function.fillPressed`.
/// - The shadow has the exported colour and offset only: no blur (radius 0) and, as opacity, the colour's own alpha.
/// - The export has no glyphs, so shift, delete, the next-keyboard key, emoji and dictation use SF Symbols (public
///   `UIImage(systemName:)`), sized by `key.function.glyphSize` and tinted with the label colour, at the symbols'
///   default weight. Shift shows "shift" when off, "shift.fill" when on and "capslock.fill" in caps lock, and the
///   letters show upper case while it is on, so its state is visible without a colour the export lacks.
/// - The backdrop is the export's opaque fallback colour, not the Liquid Glass material, which it does not describe.
///
/// Touches reach the typing adapter (`KeyboardTyping`) as plain points and times through `touchDown`, `touchMove`,
/// `touchUp` and `touchCancel`, which `touchesBegan`, `touchesMoved`, `touchesEnded` and `touchesCancelled` call, so
/// tests can drive the real view without UIKit's touch objects. The "123", emoji and dictation keys are drawn and do
/// nothing (KEY-62 does not cover them). The next-keyboard key is drawn only when `showsInputModeSwitchKey` is true
/// (the input view controller's `needsInputModeSwitchKey`), and hands its touches to `inputModeListHandler`.
public final class KeyboardView: UIView, KeyboardTypingObserver {
    /// The accessibility identifier of the keyboard, for UI tests.
    public static let accessibilityID = "SpeakboardKeyboard"

    /// The typing adapter touches go to, or nil for a view that only draws.
    public let typing: KeyboardTyping?
    /// The layout drawn, from the core. Nil until `update(screenWidth:screenHeight:)`.
    public private(set) var layout: KeyboardLayout?
    /// The appearance drawn: the trait collection's.
    public private(set) var appearance: Appearance = .light
    /// Whether to draw the next-keyboard key (`needsInputModeSwitchKey`).
    public var showsInputModeSwitchKey = false {
        didSet {
            if showsInputModeSwitchKey != oldValue { redraw() }
        }
    }
    /// Called with this view and the event for each touch on the next-keyboard key, for
    /// `UIInputViewController.handleInputModeList(from:with:)`.
    public var inputModeListHandler: ((UIView, UIEvent) -> Void)?

    /// One face layer per key, in the order of `layout.keys`.
    public private(set) var faceLayers: [CALayer] = []
    private var labelLayers: [CATextLayer] = []
    private var glyphLayers: [CALayer] = []
    private var drawnGlyphs: [String?] = []
    private var glyphCache: [String: UIImage] = [:]
    private let labels: KeyLabels?
    private var inputModeTouch: Int?

    /// A view that sends its touches to `typing`, or only draws if it is nil.
    public init(typing: KeyboardTyping?, locale: KeyboardLocale = .english) {
        self.typing = typing
        self.labels = KeyLabels(locale: locale)
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        isAccessibilityElement = true
        accessibilityIdentifier = Self.accessibilityID
        accessibilityLabel = "Speakboard keyboard"
        accessibilityTraits = .allowsDirectInteraction
        typing?.observer = self
        registerForTraitChanges([UITraitUserInterfaceStyle.self], action: #selector(userInterfaceStyleChanged))
        syncAppearance()
    }

    /// Not supported: the view is made in code.
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    // MARK: Layout

    /// Builds the layout for a screen of `screenWidth` by `screenHeight` points, if it is not the one drawn, and
    /// returns the keyboard's height in points (the core's `keyboard.totalHeight`), or nil if the core has no layout
    /// for the locale.
    @discardableResult
    public func update(screenWidth: Double, screenHeight: Double) -> Double? {
        let match = DeviceClass.match(screenWidth: screenWidth, screenHeight: screenHeight)
        let orientation = Orientation(screenWidth: screenWidth, screenHeight: screenHeight)
        if layout?.deviceClass != match.deviceClass || layout?.orientation != orientation {
            layout = KeyboardLayout(locale: .english, deviceClass: match.deviceClass, orientation: orientation)
            typing?.layout = layout
            buildLayers()
        }
        return layout?.size.height
    }

    /// Redraws in the trait collection's appearance if it changed.
    public override func layoutSubviews() {
        super.layoutSubviews()
        syncAppearance()
    }

    @objc private func userInterfaceStyleChanged() {
        syncAppearance()
    }

    private func syncAppearance() {
        applyUserInterfaceStyle(traitCollection.userInterfaceStyle)
    }

    /// Draws in the appearance of `style`: dark for `.dark`, light otherwise. The view calls it with its trait
    /// collection's style on every layout pass and whenever the style changes; tests call it directly, because a view
    /// with no window does not take a trait override into its trait collection.
    public func applyUserInterfaceStyle(_ style: UIUserInterfaceStyle) {
        let current: Appearance = style == .dark ? .dark : .light
        if current != appearance || faceLayers.isEmpty {
            appearance = current
            glyphCache.removeAll()
            redraw()
        }
    }

    private func buildLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for face in faceLayers { face.removeFromSuperlayer() }
        faceLayers.removeAll()
        labelLayers.removeAll()
        glyphLayers.removeAll()
        drawnGlyphs.removeAll()
        glyphCache.removeAll()
        if let layout {
            var index = 0
            while index < layout.keys.count {
                let face = CALayer()
                let label = CATextLayer()
                label.alignmentMode = .center
                let glyph = CALayer()
                face.addSublayer(label)
                face.addSublayer(glyph)
                layer.addSublayer(face)
                faceLayers.append(face)
                labelLayers.append(label)
                glyphLayers.append(glyph)
                drawnGlyphs.append(nil)
                index += 1
            }
        }
        CATransaction.commit()
        redraw()
    }

    // MARK: Drawing

    /// The return key's face: the field's return key type's, or the standard face where the export does not say.
    private var returnFace: ReturnKeyFace {
        ReturnKeyFace(typing?.returnKey.kind ?? .default) ?? .standard
    }

    /// Sets every layer from the layout, the tokens and the typing state, with implicit animations off.
    func redraw() {
        let palette = Palette.of(appearance)
        layer.backgroundColor = Self.cgColor(palette.keyboardBackdropFallback)
        guard let layout, faceLayers.count == layout.keys.count else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let shift = typing?.shiftState ?? .off
        let face = returnFace
        let scale = traitCollection.displayScale
        var index = 0
        while index < layout.keys.count {
            let key = layout.keys[index]
            let style = KeyStyle.of(key.kind, returnKey: face, appearance: appearance, metrics: layout.metrics)
            draw(key, style, index: index, shift: shift, scale: scale)
            index += 1
        }
        CATransaction.commit()
    }

    private func draw(_ key: Key, _ style: KeyStyle, index: Int, shift: ShiftState, scale: CGFloat) {
        let faceLayer = faceLayers[index]
        let frame = CGRect(x: key.frame.x, y: key.frame.y, width: key.frame.width, height: key.frame.height)
        let bounds = CGRect(origin: .zero, size: frame.size)
        faceLayer.frame = frame
        faceLayer.isHidden = key.kind == .globe && !showsInputModeSwitchKey
        let held = typing?.heldKeyIndex == index
        let fill = held ? (style.fill(pressed: true) ?? style.fill) : style.fill
        faceLayer.backgroundColor = Self.cgColor(fill)
        faceLayer.cornerRadius = CGFloat(style.cornerRadius.value)
        faceLayer.shadowColor = Self.cgColor(style.shadow.color.color.opaque)
        faceLayer.shadowOpacity = Float(style.shadow.color.color.alpha)
        faceLayer.shadowOffset = CGSize(width: 0, height: CGFloat(style.shadow.offsetY.value))
        faceLayer.shadowRadius = 0
        faceLayer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: faceLayer.cornerRadius).cgPath

        let labelLayer = labelLayers[index]
        let glyphLayer = glyphLayers[index]
        let size = CGFloat(style.label.size.value)
        if let font = style.label.font, let text = text(for: key.kind, shift: shift) {
            let uiFont = Self.font(font, size: size)
            labelLayer.isHidden = false
            labelLayer.font = uiFont
            labelLayer.fontSize = size
            labelLayer.foregroundColor = Self.cgColor(style.label.color)
            labelLayer.contentsScale = scale
            if labelLayer.string as? String != text { labelLayer.string = text }
            labelLayer.frame = CGRect(
                x: 0, y: (bounds.height - uiFont.lineHeight) / 2, width: bounds.width, height: uiFont.lineHeight)
            glyphLayer.isHidden = true
            drawnGlyphs[index] = nil
        } else if let name = Self.glyphName(for: key.kind, shift: shift),
            let image = glyph(name, size: size, color: style.label.color)
        {
            glyphLayer.isHidden = false
            if drawnGlyphs[index] != name {
                glyphLayer.contents = image.cgImage
                drawnGlyphs[index] = name
            }
            glyphLayer.contentsScale = image.scale
            glyphLayer.frame = CGRect(
                x: (bounds.width - image.size.width) / 2, y: (bounds.height - image.size.height) / 2,
                width: image.size.width, height: image.size.height)
            labelLayer.isHidden = true
        } else {
            labelLayer.isHidden = true
            glyphLayer.isHidden = true
        }
    }

    private func text(for kind: KeyKind, shift: ShiftState) -> String? {
        switch kind {
        case .letter(let scalar):
            let letter = String(Character(scalar))
            return shift.isOn ? letter.uppercased() : letter
        case .space: return labels?.space
        case .modeSwitch: return labels?.modeSwitch
        case .returnKey: return labels?.returnTitle(typing?.returnKey.kind ?? .default)
        case .shift, .delete, .emoji, .globe, .dictation: return nil
        }
    }

    /// The SF Symbol drawn on a glyph key, or nil for a key with a text label. Not from the token export, which has
    /// no glyphs: a stand-in until the design system has an icon set.
    public static func glyphName(for kind: KeyKind, shift: ShiftState) -> String? {
        switch kind {
        case .shift:
            switch shift {
            case .off: return "shift"
            case .automatic, .manual: return "shift.fill"
            case .locked: return "capslock.fill"
            }
        case .delete: return "delete.left"
        case .globe: return "globe"
        case .emoji: return "face.smiling"
        case .dictation: return "mic"
        case .letter, .space, .modeSwitch, .returnKey: return nil
        }
    }

    private func glyph(_ name: String, size: CGFloat, color: ColorCell) -> UIImage? {
        if let cached = glyphCache[name] { return cached }
        let configuration = UIImage.SymbolConfiguration(pointSize: size)
        guard
            let symbol = UIImage(systemName: name, withConfiguration: configuration)?
                .withTintColor(Self.uiColor(color), renderingMode: .alwaysOriginal)
        else { return nil }
        let format = UIGraphicsImageRendererFormat(for: traitCollection)
        let image = UIGraphicsImageRenderer(size: symbol.size, format: format).image { _ in
            symbol.draw(at: .zero)
        }
        glyphCache[name] = image
        return image
    }

    /// The text on key `index`, or nil if it shows a glyph or nothing. For tests.
    public func labelText(at index: Int) -> String? {
        guard index < labelLayers.count, !labelLayers[index].isHidden else { return nil }
        return labelLayers[index].string as? String
    }

    /// The SF Symbol drawn on key `index`, or nil. For tests.
    public func glyphName(at index: Int) -> String? {
        guard index < glyphLayers.count, !glyphLayers[index].isHidden else { return nil }
        return drawnGlyphs[index]
    }

    static func uiColor(_ cell: ColorCell) -> UIColor {
        uiColor(cell.color)
    }

    static func uiColor(_ color: RGBAColor) -> UIColor {
        UIColor(
            red: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue),
            alpha: CGFloat(color.alpha))
    }

    static func cgColor(_ cell: ColorCell) -> CGColor {
        uiColor(cell.color).cgColor
    }

    static func cgColor(_ color: RGBAColor) -> CGColor {
        uiColor(color).cgColor
    }

    static func font(_ font: KeyFont, size: CGFloat) -> UIFont {
        switch font.typeface.typeface {
        case .system: return UIFont.systemFont(ofSize: size, weight: weight(font.weight.weight))
        }
    }

    static func weight(_ weight: FontWeight) -> UIFont.Weight {
        switch weight {
        case FontWeight.ultraLight: return UIFont.Weight.ultraLight
        case FontWeight.thin: return UIFont.Weight.thin
        case FontWeight.light: return UIFont.Weight.light
        case FontWeight.regular: return UIFont.Weight.regular
        case FontWeight.medium: return UIFont.Weight.medium
        case FontWeight.semibold: return UIFont.Weight.semibold
        case FontWeight.bold: return UIFont.Weight.bold
        case FontWeight.heavy: return UIFont.Weight.heavy
        case FontWeight.black: return UIFont.Weight.black
        }
    }

    // MARK: Typing state

    /// See `KeyboardTypingObserver`: redraws the held key, Shift, the letters' case and the return key.
    public func typingStateDidChange(_ typing: KeyboardTyping) {
        redraw()
    }

    // MARK: Touches

    /// A finger landed at `point` (this view's coordinates) at `time` (the touch's timestamp).
    public func touchDown(_ touch: Int, at point: CGPoint, time: TimeInterval) {
        typing?.touchBegan(touch, at: Self.layoutPoint(point), time: time)
    }

    /// The finger `touch` moved to `point`.
    public func touchMove(_ touch: Int, to point: CGPoint, time: TimeInterval) {
        typing?.touchMoved(touch, to: Self.layoutPoint(point), time: time)
    }

    /// The finger `touch` lifted at `point`.
    public func touchUp(_ touch: Int, at point: CGPoint, time: TimeInterval) {
        typing?.touchEnded(touch, at: Self.layoutPoint(point), time: time)
    }

    /// The finger `touch` was cancelled.
    public func touchCancel(_ touch: Int, time: TimeInterval) {
        typing?.touchCancelled(touch, time: time)
    }

    static func layoutPoint(_ point: CGPoint) -> LayoutPoint {
        LayoutPoint(x: Double(point.x), y: Double(point.y))
    }

    private static func id(_ touch: UITouch) -> Int {
        ObjectIdentifier(touch).hashValue
    }

    private func isInputModeKey(at point: CGPoint) -> Bool {
        guard showsInputModeSwitchKey, let key = layout?.key(at: Self.layoutPoint(point)) else { return false }
        return key.kind == .globe
    }

    /// Sends this touch to the next-keyboard handler if it began on that key.
    private func forwardInputModeTouch(_ touch: UITouch, _ event: UIEvent?, began: Bool) {
        let id = Self.id(touch)
        if began, isInputModeKey(at: touch.location(in: self)) { inputModeTouch = id }
        if inputModeTouch == id, let event { inputModeListHandler?(self, event) }
    }

    /// See `touchDown`.
    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            forwardInputModeTouch(touch, event, began: true)
            touchDown(Self.id(touch), at: touch.location(in: self), time: touch.timestamp)
        }
    }

    /// See `touchMove`.
    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            forwardInputModeTouch(touch, event, began: false)
            touchMove(Self.id(touch), to: touch.location(in: self), time: touch.timestamp)
        }
    }

    /// See `touchUp`.
    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            forwardInputModeTouch(touch, event, began: false)
            if inputModeTouch == Self.id(touch) { inputModeTouch = nil }
            touchUp(Self.id(touch), at: touch.location(in: self), time: touch.timestamp)
        }
    }

    /// See `touchCancel`.
    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if inputModeTouch == Self.id(touch) { inputModeTouch = nil }
            touchCancel(Self.id(touch), time: touch.timestamp)
        }
    }
}
