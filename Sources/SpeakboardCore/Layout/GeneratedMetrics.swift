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

/// The pinned token export these tables were generated from.
public enum TokenExport {
    /// The export's token set version.
    public static let tokenSetVersion = "0.2.2"

    /// The SHA-256 of the pinned speakboard-tokens.json.
    public static let sha256 = "a61b74b95f889492393a621e2130a2caff4c0079782d0a8048a3cad052af50b4"

    /// The publish label of the export in the design system.
    public static let publishLabel = "KEY-4 tokens v0.2.2"

    /// The iOS major version the tokens describe.
    public static let iosMajorVersion = 26
}

/// An iPhone size class in the token export, named by its portrait screen size in points.
public enum DeviceClass: String, CaseIterable, Sendable {
    /// iPhone SE (2nd generation), iPhone SE (3rd generation). Home button.
    case iphone375x667 = "iphone-375x667"

    /// iPhone 11 Pro, iPhone 12 mini, iPhone 13 mini. Home indicator.
    case iphone375x812 = "iphone-375x812"

    /// iPhone 12, iPhone 12 Pro, iPhone 13, iPhone 13 Pro, iPhone 14, iPhone 16e. Home indicator.
    case iphone390x844 = "iphone-390x844"

    /// iPhone 14 Pro, iPhone 15, iPhone 15 Pro, iPhone 16. Home indicator.
    case iphone393x852 = "iphone-393x852"

    /// iPhone 16 Pro, iPhone 17, iPhone 17 Pro. Home indicator.
    case iphone402x874 = "iphone-402x874"

    /// iPhone 11, iPhone 11 Pro Max. Home indicator.
    case iphone414x896 = "iphone-414x896"

    /// iPhone Air. Home indicator.
    case iphone420x912 = "iphone-420x912"

    /// iPhone 12 Pro Max, iPhone 13 Pro Max, iPhone 14 Plus. Home indicator.
    case iphone428x926 = "iphone-428x926"

    /// iPhone 14 Pro Max, iPhone 15 Plus, iPhone 15 Pro Max, iPhone 16 Plus. Home indicator.
    case iphone430x932 = "iphone-430x932"

    /// iPhone 16 Pro Max, iPhone 17 Pro Max. Home indicator.
    case iphone440x956 = "iphone-440x956"
}

extension DeviceClass {
    /// The screen width in portrait, in points.
    public var screenWidth: Double {
        switch self {
        case .iphone375x667: return 375.0
        case .iphone375x812: return 375.0
        case .iphone390x844: return 390.0
        case .iphone393x852: return 393.0
        case .iphone402x874: return 402.0
        case .iphone414x896: return 414.0
        case .iphone420x912: return 420.0
        case .iphone428x926: return 428.0
        case .iphone430x932: return 430.0
        case .iphone440x956: return 440.0
        }
    }

    /// The screen height in portrait, in points.
    public var screenHeight: Double {
        switch self {
        case .iphone375x667: return 667.0
        case .iphone375x812: return 812.0
        case .iphone390x844: return 844.0
        case .iphone393x852: return 852.0
        case .iphone402x874: return 874.0
        case .iphone414x896: return 896.0
        case .iphone420x912: return 912.0
        case .iphone428x926: return 926.0
        case .iphone430x932: return 932.0
        case .iphone440x956: return 956.0
        }
    }

    /// Whether the class has a home indicator (Face ID) rather than a home button.
    public var hasHomeIndicator: Bool {
        switch self {
        case .iphone375x667: return false
        case .iphone375x812: return true
        case .iphone390x844: return true
        case .iphone393x852: return true
        case .iphone402x874: return true
        case .iphone414x896: return true
        case .iphone420x912: return true
        case .iphone428x926: return true
        case .iphone430x932: return true
        case .iphone440x956: return true
        }
    }
}

/// The metrics for one device class and orientation: one cell per token in the export that varies by
/// device class and orientation. Read a row with `Metrics.of(_:_:)`.
public struct Metrics: Equatable, Sendable {
    /// `dictation.transcript.labelSize` (pt). Point size of the live transcript in the suggestion bar. An alias of
    /// `suggestionBar.candidate.labelSize`: it reads that token's value.
    public var dictationTranscriptLabelSize: MetricCell {
        .invented(suggestionBarCandidateLabelSize.value)
    }

    /// `key.cornerRadius` (pt). Corner radius of every key face.
    public let keyCornerRadius: MetricCell

    /// `key.delete.width` (pt). Width of the delete key at the right of row 3.
    public let keyDeleteWidth: MetricCell

    /// `key.function.glyphSize` (pt). Point size of glyphs on function keys (shift arrow, delete, globe, emoji).
    public let keyFunctionGlyphSize: MetricCell

    /// `key.function.labelSize` (pt). Point size of word labels on function keys ("space", "return", "123").
    public let keyFunctionLabelSize: MetricCell

    /// `key.gap.horizontal` (pt). Gap between adjacent keys in a row.
    public let keyGapHorizontal: MetricCell

    /// `key.gap.vertical` (pt). Gap between key rows.
    public let keyGapVertical: MetricCell

    /// `key.letter.height` (pt). Height of every key in the four rows (letter, function and bottom-row keys share
    /// it).
    public let keyLetterHeight: MetricCell

    /// `key.letter.labelSize` (pt). Point size of lowercase letter labels on letter keys.
    public let keyLetterLabelSize: MetricCell

    /// `key.letter.width` (pt). Width of a letter key. Row 1 holds 10 letters edge to edge; row 2 holds 9, centred;
    /// row 3 holds 7, centred between shift and delete.
    public let keyLetterWidth: MetricCell

    /// `key.modeSwitch.width` (pt). Width of the "123" / "ABC" key at the left of the bottom row.
    public let keyModeSwitchWidth: MetricCell

    /// `key.return.width` (pt). Width of the return key at the right of the bottom row.
    public let keyReturnWidth: MetricCell

    /// `key.shadow.offsetY` (pt). Vertical offset of the key shadow. Set to 0 if iOS 26 has no key shadow.
    public let keyShadowOffsetY: MetricCell

    /// `key.shift.width` (pt). Width of the shift key at the left of row 3.
    public let keyShiftWidth: MetricCell

    /// `key.space.width` (pt). Width of the space bar: whatever the bottom row leaves.
    public let keySpaceWidth: MetricCell

    /// `key.utility.width` (pt). Width of each utility key in the bottom row: the emoji key on Face ID iPhones, the
    /// globe and dictation keys on home-button iPhones.
    public let keyUtilityWidth: MetricCell

    /// `keyboard.backdrop.topCornerRadius` (pt). Corner radius at the top corners of the keyboard backdrop, if iOS
    /// 26 rounds them.
    public let keyboardBackdropTopCornerRadius: MetricCell

    /// `keyboard.inset.bottom` (pt). Distance from the bottom of the last key row to the bottom of the key area.
    /// Derived so the key area adds up.
    public let keyboardInsetBottom: MetricCell

    /// `keyboard.inset.side` (pt). Inset from the screen edge to the outer edge of the first and last key in a row.
    public let keyboardInsetSide: MetricCell

    /// `keyboard.inset.top` (pt). Distance from the top of the key area to the top of the first key row.
    public let keyboardInsetTop: MetricCell

    /// `keyboard.keyArea.height` (pt). Height of the key area: top inset, four rows and their gaps, bottom inset.
    /// Excludes the suggestion bar and the system's bottom strip.
    public let keyboardKeyAreaHeight: MetricCell

    /// `keyboard.keyArea.width` (pt). Width available to keys: screen width in this orientation minus both side
    /// insets.
    public let keyboardKeyAreaWidth: MetricCell

    /// `keyboard.totalHeight` (pt). Suggestion bar plus key area: the height our input view asks for. iOS adds its
    /// own strip below on Face ID iPhones.
    public let keyboardTotalHeight: MetricCell

    /// `mic.glyphSize` (pt). Point size of the mic glyph on our mic key. An alias of `key.function.glyphSize`: it
    /// reads that token's value.
    public var micGlyphSize: MetricCell {
        .invented(keyFunctionGlyphSize.value)
    }

    /// `popup.accent.cellHeight` (pt). Height of one cell in the long-press accent strip.
    public let popupAccentCellHeight: MetricCell

    /// `popup.accent.cellWidthRatio` (ratio). Width of one cell in the long-press accent strip, as a multiple of
    /// key.letter.width.
    public let popupAccentCellWidthRatio: MetricCell

    /// `popup.accent.selectionCornerRadius` (pt). Corner radius of the highlight behind the selected accent.
    public let popupAccentSelectionCornerRadius: MetricCell

    /// `popup.key.cornerRadius` (pt). Corner radius of the key popup balloon.
    public let popupKeyCornerRadius: MetricCell

    /// `popup.key.glyphSize` (pt). Point size of the enlarged letter in the key popup.
    public let popupKeyGlyphSize: MetricCell

    /// `popup.key.riseAboveKey` (pt). How far the top of the popup balloon rises above the top edge of the pressed
    /// key, as Apple draws it. We draw min(popup.key.riseAboveKey, popup.key.riseLimit): on a top-row key the
    /// balloon's stem shortens and its top edge is never clipped.
    public let popupKeyRiseAboveKey: MetricCell

    /// `popup.key.riseLimit` (pt). Headroom above a top-row key inside our own view. Popups are compressed to fit
    /// it.
    public let popupKeyRiseLimit: MetricCell

    /// `popup.key.sideOverhang` (pt). How far the popup balloon extends past each side of the pressed key. Edge
    /// keys (q, p, a, l) shift the balloon inward instead.
    public let popupKeySideOverhang: MetricCell

    /// `suggestionBar.candidate.labelSize` (pt). Point size of suggestion candidates.
    public let suggestionBarCandidateLabelSize: MetricCell

    /// `suggestionBar.height` (pt). Height of the suggestion bar strip above the key area. With keyboard.inset.top
    /// it is the only headroom top-row popups have.
    public let suggestionBarHeight: MetricCell

    /// `systemStrip.height` (pt). Height of the strip iOS draws below a keyboard on Face ID iPhones (globe,
    /// dictation, home indicator). Informational: we never draw it.
    public let systemStripHeight: MetricCell
}

extension Metrics {
    /// The metrics row for a device class and orientation.
    public static func of(_ deviceClass: DeviceClass, _ orientation: Orientation) -> Metrics {
        switch (deviceClass, orientation) {
        case (.iphone375x667, .portrait):
            return Metrics(
                keyCornerRadius: .estimated(8.0, 4.0),
                keyDeleteWidth: .estimated(41.9, 5.5),
                keyFunctionGlyphSize: .estimated(20.0, 3.0),
                keyFunctionLabelSize: .estimated(16.0, 2.0),
                keyGapHorizontal: .estimated(6.0, 1.5),
                keyGapVertical: .estimated(12.0, 2.0),
                keyLetterHeight: .estimated(42.0, 3.0),
                keyLetterLabelSize: .estimated(22.0, 2.5),
                keyLetterWidth: .estimated(31.5, 1.7),
                keyModeSwitchWidth: .estimated(41.9, 5.5),
                keyReturnWidth: .estimated(88.2, 11.1),
                keyShadowOffsetY: .estimated(1.0, 1.0),
                keyShiftWidth: .estimated(41.9, 5.5),
                keySpaceWidth: .estimated(131.1, 36.6),
                keyUtilityWidth: .estimated(41.9, 5.5),
                keyboardBackdropTopCornerRadius: .placeholder(0.0, 30.0),
                keyboardInsetBottom: .estimated(3.0, 33.0),
                keyboardInsetSide: .estimated(3.0, 1.5),
                keyboardInsetTop: .estimated(9.0, 3.0),
                keyboardKeyAreaHeight: .estimated(216.0, 12.0),
                keyboardKeyAreaWidth: .estimated(369.0, 3.0),
                keyboardTotalHeight: .estimated(260.0, 18.0),
                popupAccentCellHeight: .estimated(46.0, 8.0),
                popupAccentCellWidthRatio: .estimated(1.0, 0.2),
                popupAccentSelectionCornerRadius: .estimated(6.0, 3.0),
                popupKeyCornerRadius: .estimated(10.0, 4.0),
                popupKeyGlyphSize: .estimated(34.0, 6.0),
                popupKeyRiseAboveKey: .estimated(58.0, 12.0),
                popupKeyRiseLimit: .estimated(53.0, 9.0),
                popupKeySideOverhang: .estimated(10.0, 4.0),
                suggestionBarCandidateLabelSize: .estimated(16.0, 2.0),
                suggestionBarHeight: .estimated(44.0, 6.0),
                systemStripHeight: .estimated(0.0, 0.0)
            )
        case (.iphone375x667, .landscape):
            return Metrics(
                keyCornerRadius: .estimated(8.0, 4.0),
                keyDeleteWidth: .placeholder(80.7, 21.1),
                keyFunctionGlyphSize: .estimated(20.0, 4.0),
                keyFunctionLabelSize: .estimated(16.0, 3.0),
                keyGapHorizontal: .estimated(6.0, 2.0),
                keyGapVertical: .estimated(6.0, 2.0),
                keyLetterHeight: .estimated(32.0, 4.0),
                keyLetterLabelSize: .estimated(22.0, 3.0),
                keyLetterWidth: .estimated(60.7, 2.1),
                keyModeSwitchWidth: .placeholder(80.7, 21.1),
                keyReturnWidth: .placeholder(170.0, 42.3),
                keyShadowOffsetY: .estimated(1.0, 1.0),
                keyShiftWidth: .placeholder(80.7, 21.1),
                keySpaceWidth: .placeholder(224.9, 116.6),
                keyUtilityWidth: .placeholder(80.7, 21.1),
                keyboardBackdropTopCornerRadius: .placeholder(0.0, 30.0),
                keyboardInsetBottom: .estimated(8.0, 39.0),
                keyboardInsetSide: .estimated(3.0, 1.5),
                keyboardInsetTop: .estimated(8.0, 3.0),
                keyboardKeyAreaHeight: .estimated(162.0, 14.0),
                keyboardKeyAreaWidth: .estimated(661.0, 3.0),
                keyboardTotalHeight: .estimated(200.0, 20.0),
                popupAccentCellHeight: .placeholder(46.0, 14.0),
                popupAccentCellWidthRatio: .placeholder(1.0, 0.4),
                popupAccentSelectionCornerRadius: .estimated(6.0, 3.0),
                popupKeyCornerRadius: .estimated(10.0, 4.0),
                popupKeyGlyphSize: .estimated(34.0, 8.0),
                popupKeyRiseAboveKey: .placeholder(58.0, 20.0),
                popupKeyRiseLimit: .estimated(46.0, 9.0),
                popupKeySideOverhang: .placeholder(10.0, 6.0),
                suggestionBarCandidateLabelSize: .estimated(16.0, 3.0),
                suggestionBarHeight: .estimated(38.0, 6.0),
                systemStripHeight: .estimated(0.0, 0.0)
            )
        case (.iphone375x812, .portrait):
            return Metrics(
                keyCornerRadius: .estimated(8.0, 4.0),
                keyDeleteWidth: .estimated(41.9, 5.5),
                keyFunctionGlyphSize: .estimated(20.0, 3.0),
                keyFunctionLabelSize: .estimated(16.0, 2.0),
                keyGapHorizontal: .estimated(6.0, 1.5),
                keyGapVertical: .estimated(12.0, 2.0),
                keyLetterHeight: .estimated(42.0, 3.0),
                keyLetterLabelSize: .estimated(22.0, 2.5),
                keyLetterWidth: .estimated(31.5, 1.7),
                keyModeSwitchWidth: .estimated(41.9, 5.5),
                keyReturnWidth: .estimated(88.2, 11.1),
                keyShadowOffsetY: .estimated(1.0, 1.0),
                keyShiftWidth: .estimated(41.9, 5.5),
                keySpaceWidth: .estimated(179.0, 29.6),
                keyUtilityWidth: .estimated(41.9, 5.5),
                keyboardBackdropTopCornerRadius: .placeholder(0.0, 30.0),
                keyboardInsetBottom: .estimated(3.0, 33.0),
                keyboardInsetSide: .estimated(3.0, 1.5),
                keyboardInsetTop: .estimated(9.0, 3.0),
                keyboardKeyAreaHeight: .estimated(216.0, 12.0),
                keyboardKeyAreaWidth: .estimated(369.0, 3.0),
                keyboardTotalHeight: .estimated(260.0, 18.0),
                popupAccentCellHeight: .estimated(46.0, 8.0),
                popupAccentCellWidthRatio: .estimated(1.0, 0.2),
                popupAccentSelectionCornerRadius: .estimated(6.0, 3.0),
                popupKeyCornerRadius: .estimated(10.0, 4.0),
                popupKeyGlyphSize: .estimated(34.0, 6.0),
                popupKeyRiseAboveKey: .estimated(58.0, 12.0),
                popupKeyRiseLimit: .estimated(53.0, 9.0),
                popupKeySideOverhang: .estimated(10.0, 4.0),
                suggestionBarCandidateLabelSize: .estimated(16.0, 2.0),
                suggestionBarHeight: .estimated(44.0, 6.0),
                systemStripHeight: .estimated(75.0, 12.0)
            )
        case (.iphone375x812, .landscape):
            return Metrics(
                keyCornerRadius: .estimated(8.0, 4.0),
                keyDeleteWidth: .placeholder(84.9, 29.6),
                keyFunctionGlyphSize: .estimated(20.0, 4.0),
                keyFunctionLabelSize: .estimated(16.0, 3.0),
                keyGapHorizontal: .estimated(6.0, 2.0),
                keyGapVertical: .estimated(6.0, 2.0),
                keyLetterHeight: .estimated(32.0, 4.0),
                keyLetterLabelSize: .estimated(22.0, 3.0),
                keyLetterWidth: .placeholder(63.8, 7.8),
                keyModeSwitchWidth: .placeholder(84.9, 29.6),
                keyReturnWidth: .placeholder(178.6, 60.2),
                keyShadowOffsetY: .estimated(1.0, 1.0),
                keyShiftWidth: .placeholder(84.9, 29.6),
                keySpaceWidth: .placeholder(325.6, 185.4),
                keyUtilityWidth: .placeholder(84.9, 29.6),
                keyboardBackdropTopCornerRadius: .placeholder(0.0, 30.0),
                keyboardInsetBottom: .estimated(8.0, 39.0),
                keyboardInsetSide: .placeholder(60.0, 30.0),
                keyboardInsetTop: .estimated(8.0, 3.0),
                keyboardKeyAreaHeight: .estimated(162.0, 14.0),
                keyboardKeyAreaWidth: .placeholder(692.0, 60.0),
                keyboardTotalHeight: .estimated(200.0, 20.0),
                popupAccentCellHeight: .placeholder(46.0, 14.0),
                popupAccentCellWidthRatio: .placeholder(1.0, 0.4),
                popupAccentSelectionCornerRadius: .estimated(6.0, 3.0),
                popupKeyCornerRadius: .estimated(10.0, 4.0),
                popupKeyGlyphSize: .estimated(34.0, 8.0),
                popupKeyRiseAboveKey: .placeholder(58.0, 20.0),
                popupKeyRiseLimit: .estimated(46.0, 9.0),
                popupKeySideOverhang: .placeholder(10.0, 6.0),
                suggestionBarCandidateLabelSize: .estimated(16.0, 3.0),
                suggestionBarHeight: .estimated(38.0, 6.0),
                systemStripHeight: .placeholder(34.0, 20.0)
            )
        case (.iphone390x844, .portrait):
            return Metrics(
                keyCornerRadius: .estimated(8.0, 4.0),
                keyDeleteWidth: .estimated(43.9, 5.6),
                keyFunctionGlyphSize: .estimated(20.0, 3.0),
                keyFunctionLabelSize: .estimated(16.0, 2.0),
                keyGapHorizontal: .estimated(6.0, 1.5),
                keyGapVertical: .estimated(12.0, 2.0),
                keyLetterHeight: .estimated(42.0, 3.0),
                keyLetterLabelSize: .estimated(22.0, 2.5),
                keyLetterWidth: .estimated(33.0, 1.7),
                keyModeSwitchWidth: .estimated(43.9, 5.6),
                keyReturnWidth: .estimated(92.4, 11.4),
                keyShadowOffsetY: .estimated(1.0, 1.0),
                keyShiftWidth: .estimated(43.9, 5.6),
                keySpaceWidth: .estimated(185.8, 30.1),
                keyUtilityWidth: .estimated(43.9, 5.6),
                keyboardBackdropTopCornerRadius: .placeholder(0.0, 30.0),
                keyboardInsetBottom: .estimated(3.0, 33.0),
                keyboardInsetSide: .estimated(3.0, 1.5),
                keyboardInsetTop: .estimated(9.0, 3.0),
                keyboardKeyAreaHeight: .estimated(216.0, 12.0),
                keyboardKeyAreaWidth: .estimated(384.0, 3.0),
                keyboardTotalHeight: .estimated(260.0, 18.0),
                popupAccentCellHeight: .estimated(46.0, 8.0),
                popupAccentCellWidthRatio: .estimated(1.0, 0.2),
                popupAccentSelectionCornerRadius: .estimated(6.0, 3.0),
                popupKeyCornerRadius: .estimated(10.0, 4.0),
                popupKeyGlyphSize: .estimated(34.0, 6.0),
                popupKeyRiseAboveKey: .estimated(58.0, 12.0),
                popupKeyRiseLimit: .estimated(53.0, 9.0),
                popupKeySideOverhang: .estimated(10.0, 4.0),
                suggestionBarCandidateLabelSize: .estimated(16.0, 2.0),
                suggestionBarHeight: .estimated(44.0, 6.0),
                systemStripHeight: .estimated(75.0, 12.0)
            )
        case (.iphone390x844, .landscape):
            return Metrics(
                keyCornerRadius: .estimated(8.0, 4.0),
                keyDeleteWidth: .placeholder(89.1, 30.5),
                keyFunctionGlyphSize: .estimated(20.0, 4.0),
                keyFunctionLabelSize: .estimated(16.0, 3.0),
                keyGapHorizontal: .estimated(6.0, 2.0),
                keyGapVertical: .estimated(6.0, 2.0),
                keyLetterHeight: .estimated(32.0, 4.0),
                keyLetterLabelSize: .estimated(22.0, 3.0),
                keyLetterWidth: .placeholder(67.0, 7.8),
                keyModeSwitchWidth: .placeholder(89.1, 30.5),
                keyReturnWidth: .placeholder(187.6, 62.1),
                keyShadowOffsetY: .estimated(1.0, 1.0),
                keyShiftWidth: .placeholder(89.1, 30.5),
                keySpaceWidth: .placeholder(340.2, 189.1),
                keyUtilityWidth: .placeholder(89.1, 30.5),
                keyboardBackdropTopCornerRadius: .placeholder(0.0, 30.0),
                keyboardInsetBottom: .estimated(8.0, 39.0),
                keyboardInsetSide: .placeholder(60.0, 30.0),
                keyboardInsetTop: .estimated(8.0, 3.0),
                keyboardKeyAreaHeight: .estimated(162.0, 14.0),
                keyboardKeyAreaWidth: .placeholder(724.0, 60.0),
                keyboardTotalHeight: .estimated(200.0, 20.0),
                popupAccentCellHeight: .placeholder(46.0, 14.0),
                popupAccentCellWidthRatio: .placeholder(1.0, 0.4),
                popupAccentSelectionCornerRadius: .estimated(6.0, 3.0),
                popupKeyCornerRadius: .estimated(10.0, 4.0),
                popupKeyGlyphSize: .estimated(34.0, 8.0),
                popupKeyRiseAboveKey: .placeholder(58.0, 20.0),
                popupKeyRiseLimit: .estimated(46.0, 9.0),
                popupKeySideOverhang: .placeholder(10.0, 6.0),
                suggestionBarCandidateLabelSize: .estimated(16.0, 3.0),
                suggestionBarHeight: .estimated(38.0, 6.0),
                systemStripHeight: .placeholder(34.0, 20.0)
            )
        case (.iphone393x852, .portrait):
            return Metrics(
                keyCornerRadius: .estimated(8.0, 4.0),
                keyDeleteWidth: .estimated(44.3, 5.6),
                keyFunctionGlyphSize: .estimated(20.0, 3.0),
                keyFunctionLabelSize: .estimated(16.0, 2.0),
                keyGapHorizontal: .estimated(6.0, 1.5),
                keyGapVertical: .estimated(12.0, 2.0),
                keyLetterHeight: .estimated(42.0, 3.0),
                keyLetterLabelSize: .estimated(22.0, 2.5),
                keyLetterWidth: .estimated(33.3, 1.7),
                keyModeSwitchWidth: .estimated(44.3, 5.6),
                keyReturnWidth: .estimated(93.2, 11.5),
                keyShadowOffsetY: .estimated(1.0, 1.0),
                keyShiftWidth: .estimated(44.3, 5.6),
                keySpaceWidth: .estimated(187.2, 30.2),
                keyUtilityWidth: .estimated(44.3, 5.6),
                keyboardBackdropTopCornerRadius: .placeholder(0.0, 30.0),
                keyboardInsetBottom: .estimated(3.0, 33.0),
                keyboardInsetSide: .estimated(3.0, 1.5),
                keyboardInsetTop: .estimated(9.0, 3.0),
                keyboardKeyAreaHeight: .estimated(216.0, 12.0),
                keyboardKeyAreaWidth: .estimated(387.0, 3.0),
                keyboardTotalHeight: .estimated(260.0, 18.0),
                popupAccentCellHeight: .estimated(46.0, 8.0),
                popupAccentCellWidthRatio: .estimated(1.0, 0.2),
                popupAccentSelectionCornerRadius: .estimated(6.0, 3.0),
                popupKeyCornerRadius: .estimated(10.0, 4.0),
                popupKeyGlyphSize: .estimated(34.0, 6.0),
                popupKeyRiseAboveKey: .estimated(58.0, 12.0),
                popupKeyRiseLimit: .estimated(53.0, 9.0),
                popupKeySideOverhang: .estimated(10.0, 4.0),
                suggestionBarCandidateLabelSize: .estimated(16.0, 2.0),
                suggestionBarHeight: .estimated(44.0, 6.0),
                systemStripHeight: .estimated(75.0, 12.0)
            )
        case (.iphone393x852, .landscape):
            return Metrics(
                keyCornerRadius: .estimated(8.0, 4.0),
                keyDeleteWidth: .placeholder(90.2, 30.8),
                keyFunctionGlyphSize: .estimated(20.0, 4.0),
                keyFunctionLabelSize: .estimated(16.0, 3.0),
                keyGapHorizontal: .estimated(6.0, 2.0),
                keyGapVertical: .estimated(6.0, 2.0),
                keyLetterHeight: .estimated(32.0, 4.0),
                keyLetterLabelSize: .estimated(22.0, 3.0),
                keyLetterWidth: .placeholder(67.8, 7.8),
                keyModeSwitchWidth: .placeholder(90.2, 30.8),
                keyReturnWidth: .placeholder(189.8, 62.6),
                keyShadowOffsetY: .estimated(1.0, 1.0),
                keyShiftWidth: .placeholder(90.2, 30.8),
                keySpaceWidth: .placeholder(343.8, 190.2),
                keyUtilityWidth: .placeholder(90.2, 30.8),
                keyboardBackdropTopCornerRadius: .placeholder(0.0, 30.0),
                keyboardInsetBottom: .estimated(8.0, 39.0),
                keyboardInsetSide: .placeholder(60.0, 30.0),
                keyboardInsetTop: .estimated(8.0, 3.0),
                keyboardKeyAreaHeight: .estimated(162.0, 14.0),
                keyboardKeyAreaWidth: .placeholder(732.0, 60.0),
                keyboardTotalHeight: .estimated(200.0, 20.0),
                popupAccentCellHeight: .placeholder(46.0, 14.0),
                popupAccentCellWidthRatio: .placeholder(1.0, 0.4),
                popupAccentSelectionCornerRadius: .estimated(6.0, 3.0),
                popupKeyCornerRadius: .estimated(10.0, 4.0),
                popupKeyGlyphSize: .estimated(34.0, 8.0),
                popupKeyRiseAboveKey: .placeholder(58.0, 20.0),
                popupKeyRiseLimit: .estimated(46.0, 9.0),
                popupKeySideOverhang: .placeholder(10.0, 6.0),
                suggestionBarCandidateLabelSize: .estimated(16.0, 3.0),
                suggestionBarHeight: .estimated(38.0, 6.0),
                systemStripHeight: .placeholder(34.0, 20.0)
            )
        case (.iphone402x874, .portrait):
            return Metrics(
                keyCornerRadius: .estimated(8.0, 4.0),
                keyDeleteWidth: .estimated(45.5, 5.7),
                keyFunctionGlyphSize: .estimated(20.0, 3.0),
                keyFunctionLabelSize: .estimated(16.0, 2.0),
                keyGapHorizontal: .estimated(6.0, 1.5),
                keyGapVertical: .estimated(12.0, 2.0),
                keyLetterHeight: .estimated(42.0, 3.0),
                keyLetterLabelSize: .estimated(22.0, 2.5),
                keyLetterWidth: .estimated(34.2, 1.7),
                keyModeSwitchWidth: .estimated(45.5, 5.7),
                keyReturnWidth: .estimated(95.8, 11.6),
                keyShadowOffsetY: .estimated(1.0, 1.0),
                keyShiftWidth: .estimated(45.5, 5.7),
                keySpaceWidth: .estimated(191.2, 30.5),
                keyUtilityWidth: .estimated(45.5, 5.7),
                keyboardBackdropTopCornerRadius: .placeholder(0.0, 30.0),
                keyboardInsetBottom: .estimated(3.0, 33.0),
                keyboardInsetSide: .estimated(3.0, 1.5),
                keyboardInsetTop: .estimated(9.0, 3.0),
                keyboardKeyAreaHeight: .estimated(216.0, 12.0),
                keyboardKeyAreaWidth: .estimated(396.0, 3.0),
                keyboardTotalHeight: .estimated(260.0, 18.0),
                popupAccentCellHeight: .estimated(46.0, 8.0),
                popupAccentCellWidthRatio: .estimated(1.0, 0.2),
                popupAccentSelectionCornerRadius: .estimated(6.0, 3.0),
                popupKeyCornerRadius: .estimated(10.0, 4.0),
                popupKeyGlyphSize: .estimated(34.0, 6.0),
                popupKeyRiseAboveKey: .estimated(58.0, 12.0),
                popupKeyRiseLimit: .estimated(53.0, 9.0),
                popupKeySideOverhang: .estimated(10.0, 4.0),
                suggestionBarCandidateLabelSize: .estimated(16.0, 2.0),
                suggestionBarHeight: .estimated(44.0, 6.0),
                systemStripHeight: .estimated(75.0, 12.0)
            )
        case (.iphone402x874, .landscape):
            return Metrics(
                keyCornerRadius: .estimated(8.0, 4.0),
                keyDeleteWidth: .placeholder(93.1, 31.4),
                keyFunctionGlyphSize: .estimated(20.0, 4.0),
                keyFunctionLabelSize: .estimated(16.0, 3.0),
                keyGapHorizontal: .estimated(6.0, 2.0),
                keyGapVertical: .estimated(6.0, 2.0),
                keyLetterHeight: .estimated(32.0, 4.0),
                keyLetterLabelSize: .estimated(22.0, 3.0),
                keyLetterWidth: .placeholder(70.0, 7.8),
                keyModeSwitchWidth: .placeholder(93.1, 31.4),
                keyReturnWidth: .placeholder(196.0, 63.9),
                keyShadowOffsetY: .estimated(1.0, 1.0),
                keyShiftWidth: .placeholder(93.1, 31.4),
                keySpaceWidth: .placeholder(353.8, 192.7),
                keyUtilityWidth: .placeholder(93.1, 31.4),
                keyboardBackdropTopCornerRadius: .placeholder(0.0, 30.0),
                keyboardInsetBottom: .estimated(8.0, 39.0),
                keyboardInsetSide: .placeholder(60.0, 30.0),
                keyboardInsetTop: .estimated(8.0, 3.0),
                keyboardKeyAreaHeight: .estimated(162.0, 14.0),
                keyboardKeyAreaWidth: .placeholder(754.0, 60.0),
                keyboardTotalHeight: .estimated(200.0, 20.0),
                popupAccentCellHeight: .placeholder(46.0, 14.0),
                popupAccentCellWidthRatio: .placeholder(1.0, 0.4),
                popupAccentSelectionCornerRadius: .estimated(6.0, 3.0),
                popupKeyCornerRadius: .estimated(10.0, 4.0),
                popupKeyGlyphSize: .estimated(34.0, 8.0),
                popupKeyRiseAboveKey: .placeholder(58.0, 20.0),
                popupKeyRiseLimit: .estimated(46.0, 9.0),
                popupKeySideOverhang: .placeholder(10.0, 6.0),
                suggestionBarCandidateLabelSize: .estimated(16.0, 3.0),
                suggestionBarHeight: .estimated(38.0, 6.0),
                systemStripHeight: .placeholder(34.0, 20.0)
            )
        case (.iphone414x896, .portrait):
            return Metrics(
                keyCornerRadius: .estimated(8.0, 4.0),
                keyDeleteWidth: .estimated(47.1, 5.9),
                keyFunctionGlyphSize: .estimated(20.0, 3.0),
                keyFunctionLabelSize: .estimated(16.0, 2.0),
                keyGapHorizontal: .estimated(6.0, 1.5),
                keyGapVertical: .estimated(12.0, 2.0),
                keyLetterHeight: .estimated(45.0, 3.0),
                keyLetterLabelSize: .estimated(22.0, 2.5),
                keyLetterWidth: .estimated(35.4, 1.7),
                keyModeSwitchWidth: .estimated(47.1, 5.9),
                keyReturnWidth: .estimated(99.1, 11.9),
                keyShadowOffsetY: .estimated(1.0, 1.0),
                keyShiftWidth: .estimated(47.1, 5.9),
                keySpaceWidth: .estimated(196.7, 31.2),
                keyUtilityWidth: .estimated(47.1, 5.9),
                keyboardBackdropTopCornerRadius: .placeholder(0.0, 30.0),
                keyboardInsetBottom: .estimated(2.0, 33.0),
                keyboardInsetSide: .estimated(3.0, 1.5),
                keyboardInsetTop: .estimated(8.0, 3.0),
                keyboardKeyAreaHeight: .estimated(226.0, 12.0),
                keyboardKeyAreaWidth: .estimated(408.0, 3.0),
                keyboardTotalHeight: .estimated(270.0, 18.0),
                popupAccentCellHeight: .estimated(46.0, 8.0),
                popupAccentCellWidthRatio: .estimated(1.0, 0.2),
                popupAccentSelectionCornerRadius: .estimated(6.0, 3.0),
                popupKeyCornerRadius: .estimated(10.0, 4.0),
                popupKeyGlyphSize: .estimated(34.0, 6.0),
                popupKeyRiseAboveKey: .estimated(58.0, 12.0),
                popupKeyRiseLimit: .estimated(52.0, 9.0),
                popupKeySideOverhang: .estimated(10.0, 4.0),
                suggestionBarCandidateLabelSize: .estimated(16.0, 2.0),
                suggestionBarHeight: .estimated(44.0, 6.0),
                systemStripHeight: .estimated(75.0, 12.0)
            )
        case (.iphone414x896, .landscape):
            return Metrics(
                keyCornerRadius: .estimated(8.0, 4.0),
                keyDeleteWidth: .placeholder(96.0, 32.1),
                keyFunctionGlyphSize: .estimated(20.0, 4.0),
                keyFunctionLabelSize: .estimated(16.0, 3.0),
                keyGapHorizontal: .estimated(6.0, 2.0),
                keyGapVertical: .estimated(6.0, 2.0),
                keyLetterHeight: .estimated(32.0, 4.0),
                keyLetterLabelSize: .estimated(22.0, 3.0),
                keyLetterWidth: .placeholder(72.2, 7.8),
                keyModeSwitchWidth: .placeholder(96.0, 32.1),
                keyReturnWidth: .placeholder(202.2, 65.2),
                keyShadowOffsetY: .estimated(1.0, 1.0),
                keyShiftWidth: .placeholder(96.0, 32.1),
                keySpaceWidth: .placeholder(363.8, 195.4),
                keyUtilityWidth: .placeholder(96.0, 32.1),
                keyboardBackdropTopCornerRadius: .placeholder(0.0, 30.0),
                keyboardInsetBottom: .estimated(8.0, 39.0),
                keyboardInsetSide: .placeholder(60.0, 30.0),
                keyboardInsetTop: .estimated(8.0, 3.0),
                keyboardKeyAreaHeight: .estimated(162.0, 14.0),
                keyboardKeyAreaWidth: .placeholder(776.0, 60.0),
                keyboardTotalHeight: .estimated(200.0, 20.0),
                popupAccentCellHeight: .placeholder(46.0, 14.0),
                popupAccentCellWidthRatio: .placeholder(1.0, 0.4),
                popupAccentSelectionCornerRadius: .estimated(6.0, 3.0),
                popupKeyCornerRadius: .estimated(10.0, 4.0),
                popupKeyGlyphSize: .estimated(34.0, 8.0),
                popupKeyRiseAboveKey: .placeholder(58.0, 20.0),
                popupKeyRiseLimit: .estimated(46.0, 9.0),
                popupKeySideOverhang: .placeholder(10.0, 6.0),
                suggestionBarCandidateLabelSize: .estimated(16.0, 3.0),
                suggestionBarHeight: .estimated(38.0, 6.0),
                systemStripHeight: .placeholder(34.0, 20.0)
            )
        case (.iphone420x912, .portrait):
            return Metrics(
                keyCornerRadius: .estimated(8.0, 4.0),
                keyDeleteWidth: .estimated(47.9, 5.9),
                keyFunctionGlyphSize: .estimated(20.0, 3.0),
                keyFunctionLabelSize: .estimated(16.0, 2.0),
                keyGapHorizontal: .estimated(6.0, 1.5),
                keyGapVertical: .estimated(12.0, 2.0),
                keyLetterHeight: .estimated(45.0, 3.0),
                keyLetterLabelSize: .estimated(22.0, 2.5),
                keyLetterWidth: .estimated(36.0, 1.7),
                keyModeSwitchWidth: .estimated(47.9, 5.9),
                keyReturnWidth: .estimated(100.8, 12.0),
                keyShadowOffsetY: .estimated(1.0, 1.0),
                keyShiftWidth: .estimated(47.9, 5.9),
                keySpaceWidth: .estimated(199.4, 31.3),
                keyUtilityWidth: .estimated(47.9, 5.9),
                keyboardBackdropTopCornerRadius: .placeholder(0.0, 30.0),
                keyboardInsetBottom: .estimated(2.0, 33.0),
                keyboardInsetSide: .estimated(3.0, 1.5),
                keyboardInsetTop: .estimated(8.0, 3.0),
                keyboardKeyAreaHeight: .estimated(226.0, 12.0),
                keyboardKeyAreaWidth: .estimated(414.0, 3.0),
                keyboardTotalHeight: .estimated(270.0, 18.0),
                popupAccentCellHeight: .estimated(46.0, 8.0),
                popupAccentCellWidthRatio: .estimated(1.0, 0.2),
                popupAccentSelectionCornerRadius: .estimated(6.0, 3.0),
                popupKeyCornerRadius: .estimated(10.0, 4.0),
                popupKeyGlyphSize: .estimated(34.0, 6.0),
                popupKeyRiseAboveKey: .estimated(58.0, 12.0),
                popupKeyRiseLimit: .estimated(52.0, 9.0),
                popupKeySideOverhang: .estimated(10.0, 4.0),
                suggestionBarCandidateLabelSize: .estimated(16.0, 2.0),
                suggestionBarHeight: .estimated(44.0, 6.0),
                systemStripHeight: .estimated(75.0, 12.0)
            )
        case (.iphone420x912, .landscape):
            return Metrics(
                keyCornerRadius: .estimated(8.0, 4.0),
                keyDeleteWidth: .placeholder(98.2, 32.6),
                keyFunctionGlyphSize: .estimated(20.0, 4.0),
                keyFunctionLabelSize: .estimated(16.0, 3.0),
                keyGapHorizontal: .estimated(6.0, 2.0),
                keyGapVertical: .estimated(6.0, 2.0),
                keyLetterHeight: .estimated(32.0, 4.0),
                keyLetterLabelSize: .estimated(22.0, 3.0),
                keyLetterWidth: .placeholder(73.8, 7.8),
                keyModeSwitchWidth: .placeholder(98.2, 32.6),
                keyReturnWidth: .placeholder(206.6, 66.2),
                keyShadowOffsetY: .estimated(1.0, 1.0),
                keyShiftWidth: .placeholder(98.2, 32.6),
                keySpaceWidth: .placeholder(371.0, 197.4),
                keyUtilityWidth: .placeholder(98.2, 32.6),
                keyboardBackdropTopCornerRadius: .placeholder(0.0, 30.0),
                keyboardInsetBottom: .estimated(8.0, 39.0),
                keyboardInsetSide: .placeholder(60.0, 30.0),
                keyboardInsetTop: .estimated(8.0, 3.0),
                keyboardKeyAreaHeight: .estimated(162.0, 14.0),
                keyboardKeyAreaWidth: .placeholder(792.0, 60.0),
                keyboardTotalHeight: .estimated(200.0, 20.0),
                popupAccentCellHeight: .placeholder(46.0, 14.0),
                popupAccentCellWidthRatio: .placeholder(1.0, 0.4),
                popupAccentSelectionCornerRadius: .estimated(6.0, 3.0),
                popupKeyCornerRadius: .estimated(10.0, 4.0),
                popupKeyGlyphSize: .estimated(34.0, 8.0),
                popupKeyRiseAboveKey: .placeholder(58.0, 20.0),
                popupKeyRiseLimit: .estimated(46.0, 9.0),
                popupKeySideOverhang: .placeholder(10.0, 6.0),
                suggestionBarCandidateLabelSize: .estimated(16.0, 3.0),
                suggestionBarHeight: .estimated(38.0, 6.0),
                systemStripHeight: .placeholder(34.0, 20.0)
            )
        case (.iphone428x926, .portrait):
            return Metrics(
                keyCornerRadius: .estimated(8.0, 4.0),
                keyDeleteWidth: .estimated(48.9, 6.0),
                keyFunctionGlyphSize: .estimated(20.0, 3.0),
                keyFunctionLabelSize: .estimated(16.0, 2.0),
                keyGapHorizontal: .estimated(6.0, 1.5),
                keyGapVertical: .estimated(12.0, 2.0),
                keyLetterHeight: .estimated(45.0, 3.0),
                keyLetterLabelSize: .estimated(22.0, 2.5),
                keyLetterWidth: .estimated(36.8, 1.7),
                keyModeSwitchWidth: .estimated(48.9, 6.0),
                keyReturnWidth: .estimated(103.0, 12.2),
                keyShadowOffsetY: .estimated(1.0, 1.0),
                keyShiftWidth: .estimated(48.9, 6.0),
                keySpaceWidth: .estimated(203.2, 31.7),
                keyUtilityWidth: .estimated(48.9, 6.0),
                keyboardBackdropTopCornerRadius: .placeholder(0.0, 30.0),
                keyboardInsetBottom: .estimated(2.0, 33.0),
                keyboardInsetSide: .estimated(3.0, 1.5),
                keyboardInsetTop: .estimated(8.0, 3.0),
                keyboardKeyAreaHeight: .estimated(226.0, 12.0),
                keyboardKeyAreaWidth: .estimated(422.0, 3.0),
                keyboardTotalHeight: .estimated(270.0, 18.0),
                popupAccentCellHeight: .estimated(46.0, 8.0),
                popupAccentCellWidthRatio: .estimated(1.0, 0.2),
                popupAccentSelectionCornerRadius: .estimated(6.0, 3.0),
                popupKeyCornerRadius: .estimated(10.0, 4.0),
                popupKeyGlyphSize: .estimated(34.0, 6.0),
                popupKeyRiseAboveKey: .estimated(58.0, 12.0),
                popupKeyRiseLimit: .estimated(52.0, 9.0),
                popupKeySideOverhang: .estimated(10.0, 4.0),
                suggestionBarCandidateLabelSize: .estimated(16.0, 2.0),
                suggestionBarHeight: .estimated(44.0, 6.0),
                systemStripHeight: .estimated(75.0, 12.0)
            )
        case (.iphone428x926, .landscape):
            return Metrics(
                keyCornerRadius: .estimated(8.0, 4.0),
                keyDeleteWidth: .placeholder(100.0, 33.0),
                keyFunctionGlyphSize: .estimated(20.0, 4.0),
                keyFunctionLabelSize: .estimated(16.0, 3.0),
                keyGapHorizontal: .estimated(6.0, 2.0),
                keyGapVertical: .estimated(6.0, 2.0),
                keyLetterHeight: .estimated(32.0, 4.0),
                keyLetterLabelSize: .estimated(22.0, 3.0),
                keyLetterWidth: .placeholder(75.2, 7.8),
                keyModeSwitchWidth: .placeholder(100.0, 33.0),
                keyReturnWidth: .placeholder(210.6, 67.0),
                keyShadowOffsetY: .estimated(1.0, 1.0),
                keyShiftWidth: .placeholder(100.0, 33.0),
                keySpaceWidth: .placeholder(377.4, 199.0),
                keyUtilityWidth: .placeholder(100.0, 33.0),
                keyboardBackdropTopCornerRadius: .placeholder(0.0, 30.0),
                keyboardInsetBottom: .estimated(8.0, 39.0),
                keyboardInsetSide: .placeholder(60.0, 30.0),
                keyboardInsetTop: .estimated(8.0, 3.0),
                keyboardKeyAreaHeight: .estimated(162.0, 14.0),
                keyboardKeyAreaWidth: .placeholder(806.0, 60.0),
                keyboardTotalHeight: .estimated(200.0, 20.0),
                popupAccentCellHeight: .placeholder(46.0, 14.0),
                popupAccentCellWidthRatio: .placeholder(1.0, 0.4),
                popupAccentSelectionCornerRadius: .estimated(6.0, 3.0),
                popupKeyCornerRadius: .estimated(10.0, 4.0),
                popupKeyGlyphSize: .estimated(34.0, 8.0),
                popupKeyRiseAboveKey: .placeholder(58.0, 20.0),
                popupKeyRiseLimit: .estimated(46.0, 9.0),
                popupKeySideOverhang: .placeholder(10.0, 6.0),
                suggestionBarCandidateLabelSize: .estimated(16.0, 3.0),
                suggestionBarHeight: .estimated(38.0, 6.0),
                systemStripHeight: .placeholder(34.0, 20.0)
            )
        case (.iphone430x932, .portrait):
            return Metrics(
                keyCornerRadius: .estimated(8.0, 4.0),
                keyDeleteWidth: .estimated(49.2, 6.0),
                keyFunctionGlyphSize: .estimated(20.0, 3.0),
                keyFunctionLabelSize: .estimated(16.0, 2.0),
                keyGapHorizontal: .estimated(6.0, 1.5),
                keyGapVertical: .estimated(12.0, 2.0),
                keyLetterHeight: .estimated(45.0, 3.0),
                keyLetterLabelSize: .estimated(22.0, 2.5),
                keyLetterWidth: .estimated(37.0, 1.7),
                keyModeSwitchWidth: .estimated(49.2, 6.0),
                keyReturnWidth: .estimated(103.6, 12.2),
                keyShadowOffsetY: .estimated(1.0, 1.0),
                keyShiftWidth: .estimated(49.2, 6.0),
                keySpaceWidth: .estimated(204.0, 31.7),
                keyUtilityWidth: .estimated(49.2, 6.0),
                keyboardBackdropTopCornerRadius: .placeholder(0.0, 30.0),
                keyboardInsetBottom: .estimated(2.0, 33.0),
                keyboardInsetSide: .estimated(3.0, 1.5),
                keyboardInsetTop: .estimated(8.0, 3.0),
                keyboardKeyAreaHeight: .estimated(226.0, 12.0),
                keyboardKeyAreaWidth: .estimated(424.0, 3.0),
                keyboardTotalHeight: .estimated(270.0, 18.0),
                popupAccentCellHeight: .estimated(46.0, 8.0),
                popupAccentCellWidthRatio: .estimated(1.0, 0.2),
                popupAccentSelectionCornerRadius: .estimated(6.0, 3.0),
                popupKeyCornerRadius: .estimated(10.0, 4.0),
                popupKeyGlyphSize: .estimated(34.0, 6.0),
                popupKeyRiseAboveKey: .estimated(58.0, 12.0),
                popupKeyRiseLimit: .estimated(52.0, 9.0),
                popupKeySideOverhang: .estimated(10.0, 4.0),
                suggestionBarCandidateLabelSize: .estimated(16.0, 2.0),
                suggestionBarHeight: .estimated(44.0, 6.0),
                systemStripHeight: .estimated(75.0, 12.0)
            )
        case (.iphone430x932, .landscape):
            return Metrics(
                keyCornerRadius: .estimated(8.0, 4.0),
                keyDeleteWidth: .placeholder(100.8, 33.2),
                keyFunctionGlyphSize: .estimated(20.0, 4.0),
                keyFunctionLabelSize: .estimated(16.0, 3.0),
                keyGapHorizontal: .estimated(6.0, 2.0),
                keyGapVertical: .estimated(6.0, 2.0),
                keyLetterHeight: .estimated(32.0, 4.0),
                keyLetterLabelSize: .estimated(22.0, 3.0),
                keyLetterWidth: .placeholder(75.8, 7.8),
                keyModeSwitchWidth: .placeholder(100.8, 33.2),
                keyReturnWidth: .placeholder(212.2, 67.4),
                keyShadowOffsetY: .estimated(1.0, 1.0),
                keyShiftWidth: .placeholder(100.8, 33.2),
                keySpaceWidth: .placeholder(380.2, 199.8),
                keyUtilityWidth: .placeholder(100.8, 33.2),
                keyboardBackdropTopCornerRadius: .placeholder(0.0, 30.0),
                keyboardInsetBottom: .estimated(8.0, 39.0),
                keyboardInsetSide: .placeholder(60.0, 30.0),
                keyboardInsetTop: .estimated(8.0, 3.0),
                keyboardKeyAreaHeight: .estimated(162.0, 14.0),
                keyboardKeyAreaWidth: .placeholder(812.0, 60.0),
                keyboardTotalHeight: .estimated(200.0, 20.0),
                popupAccentCellHeight: .placeholder(46.0, 14.0),
                popupAccentCellWidthRatio: .placeholder(1.0, 0.4),
                popupAccentSelectionCornerRadius: .estimated(6.0, 3.0),
                popupKeyCornerRadius: .estimated(10.0, 4.0),
                popupKeyGlyphSize: .estimated(34.0, 8.0),
                popupKeyRiseAboveKey: .placeholder(58.0, 20.0),
                popupKeyRiseLimit: .estimated(46.0, 9.0),
                popupKeySideOverhang: .placeholder(10.0, 6.0),
                suggestionBarCandidateLabelSize: .estimated(16.0, 3.0),
                suggestionBarHeight: .estimated(38.0, 6.0),
                systemStripHeight: .placeholder(34.0, 20.0)
            )
        case (.iphone440x956, .portrait):
            return Metrics(
                keyCornerRadius: .estimated(8.0, 4.0),
                keyDeleteWidth: .estimated(50.5, 6.1),
                keyFunctionGlyphSize: .estimated(20.0, 3.0),
                keyFunctionLabelSize: .estimated(16.0, 2.0),
                keyGapHorizontal: .estimated(6.0, 1.5),
                keyGapVertical: .estimated(12.0, 2.0),
                keyLetterHeight: .estimated(45.0, 3.0),
                keyLetterLabelSize: .estimated(22.0, 2.5),
                keyLetterWidth: .estimated(38.0, 1.7),
                keyModeSwitchWidth: .estimated(50.5, 6.1),
                keyReturnWidth: .estimated(106.4, 12.4),
                keyShadowOffsetY: .estimated(1.0, 1.0),
                keyShiftWidth: .estimated(50.5, 6.1),
                keySpaceWidth: .estimated(208.6, 32.1),
                keyUtilityWidth: .estimated(50.5, 6.1),
                keyboardBackdropTopCornerRadius: .placeholder(0.0, 30.0),
                keyboardInsetBottom: .estimated(2.0, 33.0),
                keyboardInsetSide: .estimated(3.0, 1.5),
                keyboardInsetTop: .estimated(8.0, 3.0),
                keyboardKeyAreaHeight: .estimated(226.0, 12.0),
                keyboardKeyAreaWidth: .estimated(434.0, 3.0),
                keyboardTotalHeight: .estimated(270.0, 18.0),
                popupAccentCellHeight: .estimated(46.0, 8.0),
                popupAccentCellWidthRatio: .estimated(1.0, 0.2),
                popupAccentSelectionCornerRadius: .estimated(6.0, 3.0),
                popupKeyCornerRadius: .estimated(10.0, 4.0),
                popupKeyGlyphSize: .estimated(34.0, 6.0),
                popupKeyRiseAboveKey: .estimated(58.0, 12.0),
                popupKeyRiseLimit: .estimated(52.0, 9.0),
                popupKeySideOverhang: .estimated(10.0, 4.0),
                suggestionBarCandidateLabelSize: .estimated(16.0, 2.0),
                suggestionBarHeight: .estimated(44.0, 6.0),
                systemStripHeight: .estimated(75.0, 12.0)
            )
        case (.iphone440x956, .landscape):
            return Metrics(
                keyCornerRadius: .estimated(8.0, 4.0),
                keyDeleteWidth: .placeholder(104.0, 33.9),
                keyFunctionGlyphSize: .estimated(20.0, 4.0),
                keyFunctionLabelSize: .estimated(16.0, 3.0),
                keyGapHorizontal: .estimated(6.0, 2.0),
                keyGapVertical: .estimated(6.0, 2.0),
                keyLetterHeight: .estimated(32.0, 4.0),
                keyLetterLabelSize: .estimated(22.0, 3.0),
                keyLetterWidth: .placeholder(78.2, 7.8),
                keyModeSwitchWidth: .placeholder(104.0, 33.9),
                keyReturnWidth: .placeholder(219.0, 68.8),
                keyShadowOffsetY: .estimated(1.0, 1.0),
                keyShiftWidth: .placeholder(104.0, 33.9),
                keySpaceWidth: .placeholder(391.0, 202.6),
                keyUtilityWidth: .placeholder(104.0, 33.9),
                keyboardBackdropTopCornerRadius: .placeholder(0.0, 30.0),
                keyboardInsetBottom: .estimated(8.0, 39.0),
                keyboardInsetSide: .placeholder(60.0, 30.0),
                keyboardInsetTop: .estimated(8.0, 3.0),
                keyboardKeyAreaHeight: .estimated(162.0, 14.0),
                keyboardKeyAreaWidth: .placeholder(836.0, 60.0),
                keyboardTotalHeight: .estimated(200.0, 20.0),
                popupAccentCellHeight: .placeholder(46.0, 14.0),
                popupAccentCellWidthRatio: .placeholder(1.0, 0.4),
                popupAccentSelectionCornerRadius: .estimated(6.0, 3.0),
                popupKeyCornerRadius: .estimated(10.0, 4.0),
                popupKeyGlyphSize: .estimated(34.0, 8.0),
                popupKeyRiseAboveKey: .placeholder(58.0, 20.0),
                popupKeyRiseLimit: .estimated(46.0, 9.0),
                popupKeySideOverhang: .placeholder(10.0, 6.0),
                suggestionBarCandidateLabelSize: .estimated(16.0, 3.0),
                suggestionBarHeight: .estimated(38.0, 6.0),
                systemStripHeight: .placeholder(34.0, 20.0)
            )
        }
    }
}
