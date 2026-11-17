// GENERATED FILE. Do not edit by hand: run `make metrics`. `make check` fails if this file differs
// from what scripts/generate-metrics.swift makes from the pinned export.
//
// Source: the design token export pinned in DesignTokens/tokens.pin.
//   Design system: https://claude.ai/artifact/X7uXynbGsf54dHirJhbb9x
//   Publish label: KEY-4 tokens v0.2.2
//   Token set version: 0.2.2 (schema 1.3.0), iOS 26
//   SHA-256 of speakboard-tokens.json: a61b74b95f889492393a621e2130a2caff4c0079782d0a8048a3cad052af50b4
//
// Every value is copied from the export as it is: estimates and placeholders until the measured
// tokens ticket replaces them. Each cell keeps its tolerance, kind and placeholder flag.

// The drawing tokens: every colour token (axes ["appearance"]) as a column of `Palette`, one row per
// appearance, and every weight and typeface token (no axes) as a member of `Typography`. Sizes, radii and
// the key shadow's offset vary by device class: they are columns of `Metrics` (GeneratedMetrics.swift).

/// The colours of one appearance: one cell per colour token in the export, each of which varies by
/// appearance. Read a row with `Palette.of(_:)`.
public struct Palette: Equatable, Sendable {
    /// `dictation.armed.glyphColor` (srgb-hex8). Mic glyph colour in the armed state. An alias of `key.label`: it
    /// reads that token's value.
    public var dictationArmedGlyphColor: ColorCell {
        .invented(keyLabel.color)
    }

    /// `dictation.armed.indicatorColor` (srgb-hex8). Status dot colour in the armed state.
    public let dictationArmedIndicatorColor: ColorCell

    /// `dictation.armed.keyFill` (srgb-hex8). Mic key face colour in the armed state. An alias of
    /// `key.function.fill`: it reads that token's value.
    public var dictationArmedKeyFill: ColorCell {
        .invented(keyFunctionFill.color)
    }

    /// `dictation.failed.glyphColor` (srgb-hex8). Mic glyph colour in the failed state.
    public let dictationFailedGlyphColor: ColorCell

    /// `dictation.failed.keyFill` (srgb-hex8). Mic key face colour in the failed state.
    public let dictationFailedKeyFill: ColorCell

    /// `dictation.listening.glyphColor` (srgb-hex8). Mic glyph colour in the listening state. An alias of
    /// `key.return.labelProminent`: it reads that token's value.
    public var dictationListeningGlyphColor: ColorCell {
        .invented(keyReturnLabelProminent.color)
    }

    /// `dictation.listening.keyFill` (srgb-hex8). Mic key face colour in the listening state. An alias of
    /// `key.return.fillProminent`: it reads that token's value.
    public var dictationListeningKeyFill: ColorCell {
        .invented(keyReturnFillProminent.color)
    }

    /// `dictation.processing.glyphColor` (srgb-hex8). Mic glyph colour in the processing state. An alias of
    /// `key.return.labelProminent`: it reads that token's value.
    public var dictationProcessingGlyphColor: ColorCell {
        .invented(keyReturnLabelProminent.color)
    }

    /// `dictation.processing.keyFill` (srgb-hex8). Mic key face colour in the processing state. An alias of
    /// `key.return.fillProminent`: it reads that token's value.
    public var dictationProcessingKeyFill: ColorCell {
        .invented(keyReturnFillProminent.color)
    }

    /// `dictation.recovered.glyphColor` (srgb-hex8). Mic glyph colour in the recovered state. An alias of
    /// `key.label`: it reads that token's value.
    public var dictationRecoveredGlyphColor: ColorCell {
        .invented(keyLabel.color)
    }

    /// `dictation.recovered.indicatorColor` (srgb-hex8). Status dot colour in the recovered state.
    public let dictationRecoveredIndicatorColor: ColorCell

    /// `dictation.recovered.keyFill` (srgb-hex8). Mic key face colour in the recovered state. An alias of
    /// `key.function.fill`: it reads that token's value.
    public var dictationRecoveredKeyFill: ColorCell {
        .invented(keyFunctionFill.color)
    }

    /// `dictation.rest.glyphColor` (srgb-hex8). Mic glyph colour in the rest state. An alias of `key.label`: it
    /// reads that token's value.
    public var dictationRestGlyphColor: ColorCell {
        .invented(keyLabel.color)
    }

    /// `dictation.rest.keyFill` (srgb-hex8). Mic key face colour in the rest state. An alias of
    /// `key.function.fill`: it reads that token's value.
    public var dictationRestKeyFill: ColorCell {
        .invented(keyFunctionFill.color)
    }

    /// `dictation.transcript.partialColor` (srgb-hex8). Colour of the live, not-yet-final transcript shown in the
    /// suggestion bar while listening.
    public let dictationTranscriptPartialColor: ColorCell

    /// `key.function.fill` (srgb-hex8). Face colour of function keys (shift, delete, 123, emoji, globe, return when
    /// not prominent).
    public let keyFunctionFill: ColorCell

    /// `key.function.fillPressed` (srgb-hex8). Face colour of a function key while held: it takes the letter key
    /// colour.
    public let keyFunctionFillPressed: ColorCell

    /// `key.label` (srgb-hex8). Label and glyph colour on letter and function keys.
    public let keyLabel: ColorCell

    /// `key.letter.fill` (srgb-hex8). Face colour of letter keys and the space bar.
    public let keyLetterFill: ColorCell

    /// `key.return.fillProminent` (srgb-hex8). Return key face when the field's return key type makes it prominent
    /// (Go, Search, Send, Done).
    public let keyReturnFillProminent: ColorCell

    /// `key.return.labelProminent` (srgb-hex8). Label colour on the prominent return key.
    public let keyReturnLabelProminent: ColorCell

    /// `key.shadow.color` (srgb-hex8). Colour of the thin shadow under each key face. iOS 26 may have no key
    /// shadow.
    public let keyShadowColor: ColorCell

    /// `keyboard.backdrop.fallback` (srgb-hex8). Opaque backdrop colour for when no glass material is drawn (Reduce
    /// Transparency, or if we cannot reproduce Liquid Glass). The iOS 26 backdrop itself is a material, not a
    /// colour; its parameters are not tokenised yet.
    public let keyboardBackdropFallback: ColorCell

    /// `popup.fill` (srgb-hex8). Face colour of the key popup balloon and the accent strip.
    public let popupFill: ColorCell

    /// `suggestionBar.candidate.highlight` (srgb-hex8). Background behind the candidate that autocorrect will apply
    /// on space.
    public let suggestionBarCandidateHighlight: ColorCell

    /// `suggestionBar.candidate.label` (srgb-hex8). Text colour of suggestion candidates.
    public let suggestionBarCandidateLabel: ColorCell

    /// `suggestionBar.divider` (srgb-hex8). Hairline between suggestion candidates.
    public let suggestionBarDivider: ColorCell
}

extension Palette {
    /// The palette for an appearance.
    public static func of(_ appearance: Appearance) -> Palette {
        switch appearance {
        case .light:
            return Palette(
                dictationArmedIndicatorColor: .invented(RGBAColor(0xA33A00FF)),
                dictationFailedGlyphColor: .invented(RGBAColor(0xFFFFFFFF)),
                dictationFailedKeyFill: .invented(RGBAColor(0xFF3B30FF)),
                dictationRecoveredIndicatorColor: .invented(RGBAColor(0x0040DDFF)),
                dictationTranscriptPartialColor: .invented(RGBAColor(0x545458FF)),
                keyFunctionFill: .estimated(RGBAColor(0xACB1BAFF), 12.0),
                keyFunctionFillPressed: .estimated(RGBAColor(0xFFFFFFFF), 10.0),
                keyLabel: .estimated(RGBAColor(0x000000FF), 3.0),
                keyLetterFill: .estimated(RGBAColor(0xFFFFFFFF), 10.0),
                keyReturnFillProminent: .estimated(RGBAColor(0x007AFFFF), 6.0),
                keyReturnLabelProminent: .estimated(RGBAColor(0xFFFFFFFF), 3.0),
                keyShadowColor: .estimated(RGBAColor(0x898A8DFF), 15.0),
                keyboardBackdropFallback: .estimated(RGBAColor(0xD1D3D9FF), 12.0),
                popupFill: .estimated(RGBAColor(0xFFFFFFFF), 10.0),
                suggestionBarCandidateHighlight: .estimated(RGBAColor(0xFFFFFFFF), 15.0),
                suggestionBarCandidateLabel: .estimated(RGBAColor(0x000000FF), 3.0),
                suggestionBarDivider: .estimated(RGBAColor(0xBFC2C9FF), 15.0)
            )
        case .dark:
            return Palette(
                dictationArmedIndicatorColor: .invented(RGBAColor(0xFF9F0AFF)),
                dictationFailedGlyphColor: .invented(RGBAColor(0xFFFFFFFF)),
                dictationFailedKeyFill: .invented(RGBAColor(0xFF453AFF)),
                dictationRecoveredIndicatorColor: .invented(RGBAColor(0x409CFFFF)),
                dictationTranscriptPartialColor: .invented(RGBAColor(0xA1A1A8FF)),
                keyFunctionFill: .estimated(RGBAColor(0x474747FF), 15.0),
                keyFunctionFillPressed: .estimated(RGBAColor(0x6B6B6BFF), 12.0),
                keyLabel: .estimated(RGBAColor(0xFFFFFFFF), 3.0),
                keyLetterFill: .estimated(RGBAColor(0x6B6B6BFF), 12.0),
                keyReturnFillProminent: .estimated(RGBAColor(0x0A84FFFF), 6.0),
                keyReturnLabelProminent: .estimated(RGBAColor(0xFFFFFFFF), 3.0),
                keyShadowColor: .placeholder(RGBAColor(0x000000FF), 30.0),
                keyboardBackdropFallback: .estimated(RGBAColor(0x2C2C2EFF), 15.0),
                popupFill: .estimated(RGBAColor(0x6B6B6BFF), 12.0),
                suggestionBarCandidateHighlight: .estimated(RGBAColor(0x6B6B6BFF), 15.0),
                suggestionBarCandidateLabel: .estimated(RGBAColor(0xFFFFFFFF), 3.0),
                suggestionBarDivider: .estimated(RGBAColor(0x58585CFF), 15.0)
            )
        }
    }
}

/// The weight and typeface tokens: those with no axes, one value for every device class, orientation and
/// appearance. Each member is computed, so reading one allocates nothing and holds no global state.
public enum Typography {
    /// `key.function.labelWeight` (uifont-weight). Weight of function key word labels.
    public static var keyFunctionLabelWeight: FontWeightCell { .estimated(.regular, 1.0) }

    /// `key.letter.labelWeight` (uifont-weight). Weight of letter key labels.
    public static var keyLetterLabelWeight: FontWeightCell { .estimated(.regular, 1.0) }

    /// `typeface.family` (font-family). Typeface for every label on the keyboard: the system font (SF Pro), used
    /// through UIFont.systemFont. We ship no Apple font files.
    public static var typefaceFamily: TypefaceCell { .estimated(.system, 0.0) }
}
