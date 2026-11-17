// What a key looks like: one lookup the keyboard view calls per key, per
// appearance, so that no colour, size, weight or radius is ever typed into view
// code (KEY-62). It reads only generated tokens: `Palette` and `Typography`
// (GeneratedDrawingTokens.swift) and `Metrics` (GeneratedMetrics.swift).
//
// Which token each kind of key reads is decided here, from the tokens'
// descriptions in the export:
// - key.letter.fill: "letter keys and the space bar".
// - key.function.fill and key.function.fillPressed: "function keys (shift,
//   delete, 123, emoji, globe, return when not prominent)". Apple's dictation
//   key, in the bottom row of iPhones with a home button, is not named there;
//   it is drawn as a function key too, a decision of KEY-62, not the export's.
// - key.return.fillProminent and key.return.labelProminent: the return key
//   "when the field's return key type makes it prominent (Go, Search, Send,
//   Done)". See `ReturnKeyFace`.
// - key.label: "Label and glyph colour on letter and function keys".
// - key.letter.labelSize and key.letter.labelWeight: letter labels.
// - key.function.labelSize and key.function.labelWeight: "word labels on
//   function keys ("space", "return", "123")".
// - key.function.glyphSize: "glyphs on function keys (shift arrow, delete,
//   globe, emoji)"; the export gives no glyph weight.
//
// What the export does not give, so this file does not either: a pressed face
// for letter keys, the space bar or the prominent return key (`pressedFill` is
// nil for them); what Shift shows when on or in caps lock; a disabled return
// key; the glyphs themselves and the labels' text; the shadow's blur, opacity
// and horizontal offset; the Liquid Glass backdrop (only an opaque fallback
// colour, `Palette.keyboardBackdropFallback`).
//
// Nothing here allocates: every type is a value with no references in it, the
// tokens are computed in `switch` statements, and no global state is read.

/// The face the return key takes, as the token export tells the two apart.
public enum ReturnKeyFace: Equatable, Sendable {
    /// Drawn as a function key: key.function.fill, with key.label.
    case standard
    /// Drawn prominent: key.return.fillProminent, with key.return.labelProminent.
    case prominent

    /// The face the export gives the return key a field asks for, or nil where the export does not say.
    ///
    /// key.return.fillProminent's description names Go, Search, Send and Done as prominent, and key.function.fill's
    /// names "return when not prominent", which the default return key is. The export says nothing of the other
    /// kinds (Google, Join, Next, Route, Yahoo, Emergency Call, Continue), so they give nil: drawing them is a gap in
    /// the tokens, to be measured, not guessed here.
    public init?(_ type: ReturnKeyType) {
        switch type {
        case .default: self = .standard
        case .go, .search, .send, .done: self = .prominent
        case .google, .join, .next, .route, .yahoo, .emergencyCall, .continue: return nil
        }
    }
}

/// The font of a key's text label.
public struct KeyFont: Equatable, Sendable {
    /// The weight: key.letter.labelWeight or key.function.labelWeight.
    public let weight: FontWeightCell
    /// The typeface: typeface.family.
    public let typeface: TypefaceCell
}

/// How a key's label or glyph is drawn.
public struct KeyLabelStyle: Equatable, Sendable {
    /// The label's or glyph's colour: key.label, or key.return.labelProminent on the prominent return key.
    public let color: ColorCell
    /// The point size: key.letter.labelSize for letters, key.function.labelSize for word labels ("space", "return",
    /// "123"), key.function.glyphSize for glyphs.
    public let size: MetricCell
    /// The font of a text label, or nil for a key that shows a glyph (shift, delete, emoji, globe, dictation), whose
    /// artwork comes from our own icon set and whose weight the export does not give.
    public let font: KeyFont?
}

/// The shadow under a key face.
public struct KeyShadow: Equatable, Sendable {
    /// key.shadow.color. Its dark value has no basis in the export (`isPlaceholder`).
    public let color: ColorCell
    /// key.shadow.offsetY, downward, in points. The export gives no blur, opacity or horizontal offset.
    public let offsetY: MetricCell
}

/// What one key looks like in one appearance, on one device class and orientation: every colour, size, weight and
/// radius its drawing needs, from the generated tokens. Ask with `KeyStyle.of(_:returnKey:appearance:metrics:)`.
public struct KeyStyle: Equatable, Sendable {
    /// The key face's colour at rest.
    public let fill: ColorCell
    /// The key face's colour while the key is held: key.function.fillPressed on function keys. Nil where the export
    /// gives no pressed face: letter keys, the space bar and the prominent return key.
    public let pressedFill: ColorCell?
    /// The label or glyph.
    public let label: KeyLabelStyle
    /// The key face's corner radius: key.cornerRadius.
    public let cornerRadius: MetricCell
    /// The shadow under the key face.
    public let shadow: KeyShadow

    /// The key face's colour when held (`pressed`) or at rest. Nil when held on a key whose pressed face the export
    /// does not give (see `pressedFill`).
    public func fill(pressed: Bool) -> ColorCell? {
        pressed ? pressedFill : fill
    }

    /// The style of a key of `kind` in `appearance`, with the sizes and radius of `metrics` (the layout's
    /// `metrics`, for its device class and orientation). `returnKey` is the return key's face (see
    /// `ReturnKeyFace(_:)`); it is read for `.returnKey` only.
    ///
    /// Allocates nothing.
    public static func of(
        _ kind: KeyKind, returnKey: ReturnKeyFace, appearance: Appearance, metrics: Metrics
    ) -> KeyStyle {
        let palette = Palette.of(appearance)
        let typeface = Typography.typefaceFamily
        let letterFont = KeyFont(weight: Typography.keyLetterLabelWeight, typeface: typeface)
        let wordFont = KeyFont(weight: Typography.keyFunctionLabelWeight, typeface: typeface)

        let fill: ColorCell
        let pressedFill: ColorCell?
        let label: KeyLabelStyle
        switch kind {
        case .letter:
            fill = palette.keyLetterFill
            pressedFill = nil
            label = KeyLabelStyle(color: palette.keyLabel, size: metrics.keyLetterLabelSize, font: letterFont)
        case .space:
            fill = palette.keyLetterFill
            pressedFill = nil
            label = KeyLabelStyle(color: palette.keyLabel, size: metrics.keyFunctionLabelSize, font: wordFont)
        case .modeSwitch:
            fill = palette.keyFunctionFill
            pressedFill = palette.keyFunctionFillPressed
            label = KeyLabelStyle(color: palette.keyLabel, size: metrics.keyFunctionLabelSize, font: wordFont)
        case .shift, .delete, .emoji, .globe, .dictation:
            fill = palette.keyFunctionFill
            pressedFill = palette.keyFunctionFillPressed
            label = KeyLabelStyle(color: palette.keyLabel, size: metrics.keyFunctionGlyphSize, font: nil)
        case .returnKey:
            switch returnKey {
            case .standard:
                fill = palette.keyFunctionFill
                pressedFill = palette.keyFunctionFillPressed
                label = KeyLabelStyle(color: palette.keyLabel, size: metrics.keyFunctionLabelSize, font: wordFont)
            case .prominent:
                fill = palette.keyReturnFillProminent
                pressedFill = nil
                label = KeyLabelStyle(
                    color: palette.keyReturnLabelProminent, size: metrics.keyFunctionLabelSize, font: wordFont)
            }
        }
        return KeyStyle(
            fill: fill, pressedFill: pressedFill, label: label, cornerRadius: metrics.keyCornerRadius,
            shadow: KeyShadow(color: palette.keyShadowColor, offsetY: metrics.keyShadowOffsetY))
    }
}
