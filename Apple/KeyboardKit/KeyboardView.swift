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
/// tests can drive the real view without UIKit's touch objects. Each touch is named by its `UITouch` object's
/// identity, so each finger is followed by its own identity, and every key a finger is on is drawn held (KEY-24).
/// The "123", emoji and dictation keys are drawn and do nothing (KEY-62 does not cover them). The next-keyboard key
/// is drawn only when `showsInputModeSwitchKey` is true (the input view controller's `needsInputModeSwitchKey`), and
/// hands its touches to `inputModeListHandler`.
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
            typing?.showsInputModeSwitchKey = showsInputModeSwitchKey
            if showsInputModeSwitchKey != oldValue { redrawAll() }
        }
    }
    /// Called with this view and the event for each touch on the next-keyboard key, for
    /// `UIInputViewController.handleInputModeList(from:with:)`.
    public var inputModeListHandler: ((UIView, UIEvent) -> Void)?

    /// One face layer per key, in the order of `layout.keys`.
    public private(set) var faceLayers: [CALayer] = []
    private var labelLayers: [CATextLayer] = []
    private var glyphLayers: [CALayer] = []
    /// The symbol name on each glyph key, for `glyphName(at:)`.
    private var drawnGlyphs: [String?] = []
    /// The image each glyph layer holds. A layer's contents are replaced whenever the image to draw is another object,
    /// so a new appearance, colour or scale always reaches the layer: the name alone does not change with them
    /// (KEY-62 review round 2).
    private var drawnImages: [UIImage?] = []
    /// Rendered glyphs, by symbol name and colour, at `glyphScale`. Cleared on an appearance or display scale change.
    private var glyphCache: [String: UIImage] = [:]
    private var glyphScale: CGFloat?
    private let labels: KeyLabels?
    private var inputModeTouch: Int?

    // What the last drawing used, so a typing state change redraws only what changed (KEY-65). The faces' frames,
    // radii and shadows, the fonts, and the colours change only with the layout, the appearance (or the display
    // scale) and, for the return key, the field's return key type: a press touches only the held keys' fills, a Shift
    // change only the letters' text and Shift's glyph, and a return key change only the return key.
    /// Each key's fill at rest and while held, made on a full redraw. Nil until the key is drawn.
    private var restFills: [CGColor?] = []
    private var heldFills: [CGColor?] = []
    /// Whether each key was last drawn held.
    private var drawnHeld: [Bool] = []
    /// Each letter key's text in lower and upper case, made when the layers are built. Nil for other keys.
    private var letterTexts: [(lower: String, upper: String)?] = []
    /// The Shift state and the return key type the letters, Shift and the return key were last drawn for.
    private var drawnShift: ShiftState = .off
    private var drawnReturnKind: ReturnKeyType = .default
    /// How many times each key's layers have been written since they were built: for tests, which check that a key
    /// press writes only the layers that should change (KEY-65).
    public private(set) var layerWrites: [KeyLayerWrites] = []

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
        typing?.showsInputModeSwitchKey = showsInputModeSwitchKey
        registerForTraitChanges(
            [UITraitUserInterfaceStyle.self, UITraitDisplayScale.self], action: #selector(appearanceTraitsChanged))
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
            buildLayers()
            // After the layers, so the adapter's notice of the new layout (it drops the fingers down) is drawn on them.
            typing?.layout = layout
        }
        return layout?.size.height
    }

    /// Redraws in the trait collection's appearance if it, or the display scale, changed.
    public override func layoutSubviews() {
        super.layoutSubviews()
        syncAppearance()
    }

    @objc private func appearanceTraitsChanged() {
        syncAppearance()
    }

    private func syncAppearance() {
        applyUserInterfaceStyle(traitCollection.userInterfaceStyle)
    }

    /// Draws in the appearance of `style`: dark for `.dark`, light otherwise. The view calls it with its trait
    /// collection's style on every layout pass and whenever the style changes; tests call it directly, because a view
    /// with no window does not take a trait override into its trait collection.
    /// It also redraws everything when the display scale is not the one the glyphs were drawn at.
    public func applyUserInterfaceStyle(_ style: UIUserInterfaceStyle) {
        let current: Appearance = style == .dark ? .dark : .light
        if current != appearance || faceLayers.isEmpty || traitCollection.displayScale != glyphScale {
            appearance = current
            glyphCache.removeAll()
            redrawAll()
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
        drawnImages.removeAll()
        glyphCache.removeAll()
        restFills.removeAll()
        heldFills.removeAll()
        drawnHeld.removeAll()
        letterTexts.removeAll()
        layerWrites.removeAll()
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
                drawnImages.append(nil)
                restFills.append(nil)
                heldFills.append(nil)
                drawnHeld.append(false)
                layerWrites.append(KeyLayerWrites())
                if case .letter(let scalar) = layout.keys[index].kind {
                    let lower = String(Character(scalar))
                    letterTexts.append((lower: lower, upper: lower.uppercased()))
                } else {
                    letterTexts.append(nil)
                }
                index += 1
            }
        }
        CATransaction.commit()
        redrawAll()
    }

    // MARK: Drawing

    /// Sets every layer from the layout, the tokens and the typing state, with implicit animations off: for a new
    /// layout, appearance or display scale, and when the next-keyboard key is shown or hidden.
    func redrawAll() {
        let palette = Palette.of(appearance)
        layer.backgroundColor = Self.cgColor(palette.keyboardBackdropFallback)
        guard let layout, faceLayers.count == layout.keys.count else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let scale = traitCollection.displayScale
        if scale != glyphScale {
            glyphCache.removeAll()
            glyphScale = scale
        }
        let shift = typing?.shiftState ?? .off
        let returnKind = typing?.returnKeyKind ?? .default
        var index = 0
        while index < layout.keys.count {
            drawKey(index, in: layout, shift: shift, returnKind: returnKind)
            index += 1
        }
        drawnShift = shift
        drawnReturnKind = returnKind
        CATransaction.commit()
    }

    /// Draws key `index` whole: its face, its fill and its label or glyph.
    private func drawKey(_ index: Int, in layout: KeyboardLayout, shift: ShiftState, returnKind: ReturnKeyType) {
        let key = layout.keys[index]
        let style = Self.style(of: key.kind, returnKind: returnKind, appearance: appearance, layout: layout)
        drawFace(index, key, style)
        drawFill(index, held: typing?.holds(index) ?? false)
        drawContent(index, key, style, shift: shift, returnKind: returnKind)
    }

    private static func style(
        of kind: KeyKind, returnKind: ReturnKeyType, appearance: Appearance, layout: KeyboardLayout
    ) -> KeyStyle {
        KeyStyle.of(
            kind, returnKey: ReturnKeyFace(returnKind) ?? .standard, appearance: appearance, metrics: layout.metrics)
    }

    /// The face's frame, visibility, radius and shadow, and the fills it takes at rest and held.
    private func drawFace(_ index: Int, _ key: Key, _ style: KeyStyle) {
        let faceLayer = faceLayers[index]
        let frame = CGRect(x: key.frame.x, y: key.frame.y, width: key.frame.width, height: key.frame.height)
        let bounds = CGRect(origin: .zero, size: frame.size)
        faceLayer.frame = frame
        faceLayer.isHidden = key.kind == .globe && !showsInputModeSwitchKey
        faceLayer.cornerRadius = CGFloat(style.cornerRadius.value)
        faceLayer.shadowColor = Self.cgColor(style.shadow.color.color.opaque)
        faceLayer.shadowOpacity = Float(style.shadow.color.color.alpha)
        faceLayer.shadowOffset = CGSize(width: 0, height: CGFloat(style.shadow.offsetY.value))
        faceLayer.shadowRadius = 0
        faceLayer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: faceLayer.cornerRadius).cgPath
        let rest = Self.cgColor(style.fill)
        restFills[index] = rest
        heldFills[index] = style.fill(pressed: true).map { Self.cgColor($0) } ?? rest
        layerWrites[index].face += 1
    }

    /// The face's fill, held or at rest, from the colours `drawFace` made.
    private func drawFill(_ index: Int, held: Bool) {
        faceLayers[index].backgroundColor = held ? heldFills[index] : restFills[index]
        drawnHeld[index] = held
        layerWrites[index].fill += 1
    }

    /// The key's label or glyph, whole: font, size, colour, scale, text or image, and frame.
    private func drawContent(_ index: Int, _ key: Key, _ style: KeyStyle, shift: ShiftState, returnKind: ReturnKeyType)
    {
        let labelLayer = labelLayers[index]
        let glyphLayer = glyphLayers[index]
        let bounds = CGRect(x: 0, y: 0, width: key.frame.width, height: key.frame.height)
        let size = CGFloat(style.label.size.value)
        if let font = style.label.font, let text = text(at: index, kind: key.kind, shift: shift, returnKind: returnKind)
        {
            let uiFont = Self.font(font, size: size)
            labelLayer.isHidden = false
            labelLayer.font = uiFont
            labelLayer.fontSize = size
            labelLayer.foregroundColor = Self.cgColor(style.label.color)
            labelLayer.contentsScale = glyphScale ?? traitCollection.displayScale
            if labelLayer.string as? String != text { labelLayer.string = text }
            labelLayer.frame = CGRect(
                x: 0, y: (bounds.height - uiFont.lineHeight) / 2, width: bounds.width, height: uiFont.lineHeight)
            glyphLayer.isHidden = true
            drawnGlyphs[index] = nil
            drawnImages[index] = nil
            layerWrites[index].label += 1
        } else if let name = Self.glyphName(for: key.kind, shift: shift),
            let image = glyph(name, size: size, color: style.label.color)
        {
            glyphLayer.isHidden = false
            // Replaced whenever the image is another object, never decided by the symbol's name: the name does not
            // change with the appearance or the scale (KEY-62 review round 2).
            if drawnImages[index] !== image {
                glyphLayer.contents = image.cgImage
                drawnImages[index] = image
            }
            drawnGlyphs[index] = name
            glyphLayer.contentsScale = image.scale
            glyphLayer.frame = CGRect(
                x: (bounds.width - image.size.width) / 2, y: (bounds.height - image.size.height) / 2,
                width: image.size.width, height: image.size.height)
            labelLayer.isHidden = true
            layerWrites[index].glyph += 1
        } else {
            labelLayer.isHidden = true
            glyphLayer.isHidden = true
            layerWrites[index].label += 1
            layerWrites[index].glyph += 1
        }
    }

    /// Only the text of letter key `index`, for a Shift change: its font, colour and frame stay.
    private func drawLetterText(_ index: Int, shift: ShiftState) {
        guard let texts = letterTexts[index] else { return }
        labelLayers[index].string = shift.isOn ? texts.upper : texts.lower
        layerWrites[index].label += 1
    }

    private func text(at index: Int, kind: KeyKind, shift: ShiftState, returnKind: ReturnKeyType) -> String? {
        switch kind {
        case .letter:
            guard let texts = letterTexts[index] else { return nil }
            return shift.isOn ? texts.upper : texts.lower
        case .space: return labels?.space
        case .modeSwitch: return labels?.modeSwitch
        case .returnKey: return labels?.returnTitle(returnKind)
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
        let cacheKey = "\(name) \(color.color.rgba)"
        if let cached = glyphCache[cacheKey] { return cached }
        let configuration = UIImage.SymbolConfiguration(pointSize: size)
        guard
            let symbol = UIImage(systemName: name, withConfiguration: configuration)?
                .withTintColor(Self.uiColor(color), renderingMode: .alwaysOriginal)
        else { return nil }
        let format = UIGraphicsImageRendererFormat(for: traitCollection)
        let image = UIGraphicsImageRenderer(size: symbol.size, format: format).image { _ in
            symbol.draw(at: .zero)
        }
        glyphCache[cacheKey] = image
        return image
    }

    /// The text on key `index`, or nil if it shows a glyph or nothing. For tests.
    public func labelText(at index: Int) -> String? {
        guard index < labelLayers.count, !labelLayers[index].isHidden else { return nil }
        return labelLayers[index].string as? String
    }

    /// The image in key `index`'s glyph layer, or nil if it shows no glyph. For tests: they read its pixels. It is the
    /// layer's own `contents`, returned only if that is the very image object last rendered for the key.
    public func glyphImage(at index: Int) -> CGImage? {
        guard index < glyphLayers.count, !glyphLayers[index].isHidden, let contents = glyphLayers[index].contents,
            let image = drawnImages[index]?.cgImage, (contents as AnyObject) === image
        else { return nil }
        return image
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

    /// See `KeyboardTypingObserver`. Redraws only what changed since it was last drawn (KEY-65): the fill of each key
    /// whose held state changed; on a Shift change, the letters' text (if their case changed) and Shift's glyph (if
    /// its symbol changed); on a change of the field's return key type, the return key. Reads the field's return key
    /// type once, and nothing else of the field.
    public func typingStateDidChange(_ typing: KeyboardTyping) {
        guard let layout, faceLayers.count == layout.keys.count, drawnHeld.count == layout.keys.count else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var index = 0
        while index < layout.keys.count {
            let held = typing.holds(index)
            if held != drawnHeld[index] { drawFill(index, held: held) }
            index += 1
        }

        let shift = typing.shiftState
        if shift != drawnShift {
            let caseChanged = shift.isOn != drawnShift.isOn
            let glyphChanged =
                Self.glyphName(for: .shift, shift: shift) != Self.glyphName(for: .shift, shift: drawnShift)
            drawnShift = shift
            index = 0
            while index < layout.keys.count {
                let key = layout.keys[index]
                switch key.kind {
                case .letter where caseChanged:
                    drawLetterText(index, shift: shift)
                case .shift where glyphChanged:
                    let style = Self.style(
                        of: .shift, returnKind: drawnReturnKind, appearance: appearance, layout: layout)
                    drawContent(index, key, style, shift: shift, returnKind: drawnReturnKind)
                default: break
                }
                index += 1
            }
        }

        let returnKind = typing.returnKeyKind
        if returnKind != drawnReturnKind {
            drawnReturnKind = returnKind
            index = 0
            while index < layout.keys.count {
                if layout.keys[index].kind == .returnKey {
                    drawKey(index, in: layout, shift: shift, returnKind: returnKind)
                }
                index += 1
            }
        }
        CATransaction.commit()
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

    /// A touch's identity: its `UITouch` object's address, which UIKit keeps for one finger from landing to lift.
    private static func id(_ touch: UITouch) -> Int {
        Int(bitPattern: ObjectIdentifier(touch))
    }

    /// Whether a touch at `point` is on the next-keyboard key, by the same hit-test as typing (the nearest key).
    private func isInputModeKey(at point: CGPoint) -> Bool {
        guard showsInputModeSwitchKey, let layout,
            let index = layout.keyIndex(
                at: Self.layoutPoint(point), by: typing?.hitTesting ?? .nearest,
                showsInputModeSwitchKey: showsInputModeSwitchKey)
        else { return false }
        return layout.keys[index].kind == .globe
    }

    /// Sends this touch to the next-keyboard handler if it began on that key.
    private func forwardInputModeTouch(_ touch: UITouch, _ event: UIEvent?, began: Bool) {
        let id = Self.id(touch)
        if began, isInputModeKey(at: touch.location(in: self)) { inputModeTouch = id }
        if inputModeTouch == id, let event { inputModeListHandler?(self, event) }
    }

    /// See `touchDown`. Fingers land in the order UIKit delivers them. Two fingers that land in the same touch event
    /// have no landing order (they have the same timestamp), and are taken in the order of the set, which is not
    /// defined: their keys may be typed in either order.
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

/// How many times the view has written one key's layers since they were built (`KeyboardView.layerWrites`), counted
/// where it writes them, for tests (KEY-65).
public struct KeyLayerWrites: Equatable, Sendable {
    /// The face's frame, visibility, radius and shadow (and the fill colours it makes, not yet set).
    public var face = 0
    /// The face's fill: held or at rest.
    public var fill = 0
    /// The text label: whole, or only its text on a Shift change. A key with neither label nor glyph counts here
    /// and under `glyph` when both are hidden.
    public var label = 0
    /// The glyph's image and frame.
    public var glyph = 0

    /// No writes.
    public init() {}
}
