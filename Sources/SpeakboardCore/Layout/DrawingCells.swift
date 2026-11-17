// The types the generated drawing tokens are made of. The tokens themselves are
// GeneratedDrawingTokens.swift, generated from the pinned design token export.
//
// Plain values only: no UIKit or Core Graphics types. The Apple side maps them:
// an `RGBAColor` to a colour from its four components, a `FontWeight` to the
// `UIFont.Weight` of the same name, `Typeface.system` to the system font. Every
// type here is a value with no references in it, so reading or copying one
// allocates nothing.

/// A light or dark appearance: the export's `appearance` axis, on which every colour token varies.
public enum Appearance: String, CaseIterable, Sendable {
    /// Light.
    case light
    /// Dark.
    case dark
}

/// A colour as the export writes it: `#RRGGBBAA` in sRGB, with straight (not premultiplied) alpha.
public struct RGBAColor: Equatable, Sendable {
    /// The colour as one number, read from `#RRGGBBAA`: red in the highest byte, alpha in the lowest.
    public let rgba: UInt32

    /// The colour `0xRRGGBBAA`.
    public init(_ rgba: UInt32) {
        self.rgba = rgba
    }

    /// Red, from 0 to 1.
    public var red: Double { Double((rgba >> 24) & 0xFF) / 255 }

    /// Green, from 0 to 1.
    public var green: Double { Double((rgba >> 16) & 0xFF) / 255 }

    /// Blue, from 0 to 1.
    public var blue: Double { Double((rgba >> 8) & 0xFF) / 255 }

    /// Alpha, from 0 to 1, straight: the colour components are not multiplied by it.
    public var alpha: Double { Double(rgba & 0xFF) / 255 }

    /// The same red, green and blue, fully opaque. For a drawing API that takes the opacity apart from the colour
    /// (a Core Animation shadow's `shadowOpacity`), pass this colour and `alpha` as the opacity, so the alpha is not
    /// applied twice.
    public var opaque: RGBAColor { RGBAColor(rgba | 0xFF) }
}

/// One colour token's value for one appearance, with where it comes from.
public struct ColorCell: Equatable, Sendable {
    /// The colour, exactly as the export gives it.
    public let color: RGBAColor

    /// Plus or minus, as a CIEDE2000 colour difference. `nil` for an invented colour, which is a decision, not an
    /// estimate.
    public let tolerance: Double?

    /// Where the colour comes from.
    public let kind: MetricKind

    /// True when the export gives the colour no basis at all (confidence "none").
    public let isPlaceholder: Bool

    /// An estimate with some basis.
    static func estimated(_ color: RGBAColor, _ tolerance: Double) -> ColorCell {
        ColorCell(color: color, tolerance: tolerance, kind: .estimated, isPlaceholder: false)
    }

    /// An estimate with no basis (confidence "none").
    static func placeholder(_ color: RGBAColor, _ tolerance: Double) -> ColorCell {
        ColorCell(color: color, tolerance: tolerance, kind: .estimated, isPlaceholder: true)
    }

    /// A measured colour.
    static func measured(_ color: RGBAColor, _ tolerance: Double) -> ColorCell {
        ColorCell(color: color, tolerance: tolerance, kind: .measured, isPlaceholder: false)
    }

    /// An invented colour.
    static func invented(_ color: RGBAColor) -> ColorCell {
        ColorCell(color: color, tolerance: nil, kind: .invented, isPlaceholder: false)
    }
}

/// A font weight, by the name of the `UIFont.Weight` it stands for: the export's `uifont-weight` unit.
public enum FontWeight: String, CaseIterable, Sendable {
    /// `UIFont.Weight.ultraLight`.
    case ultraLight
    /// `UIFont.Weight.thin`.
    case thin
    /// `UIFont.Weight.light`.
    case light
    /// `UIFont.Weight.regular`.
    case regular
    /// `UIFont.Weight.medium`.
    case medium
    /// `UIFont.Weight.semibold`.
    case semibold
    /// `UIFont.Weight.bold`.
    case bold
    /// `UIFont.Weight.heavy`.
    case heavy
    /// `UIFont.Weight.black`.
    case black
}

/// One weight token's value, with where it comes from.
public struct FontWeightCell: Equatable, Sendable {
    /// The weight, exactly as the export gives it.
    public let weight: FontWeight

    /// Plus or minus, in steps of `UIFont.Weight` (one step is one case of `FontWeight`). `nil` for an invented
    /// weight.
    public let tolerance: Double?

    /// Where the weight comes from.
    public let kind: MetricKind

    /// True when the export gives the weight no basis at all (confidence "none").
    public let isPlaceholder: Bool

    /// An estimate with some basis.
    static func estimated(_ weight: FontWeight, _ tolerance: Double) -> FontWeightCell {
        FontWeightCell(weight: weight, tolerance: tolerance, kind: .estimated, isPlaceholder: false)
    }

    /// An estimate with no basis (confidence "none").
    static func placeholder(_ weight: FontWeight, _ tolerance: Double) -> FontWeightCell {
        FontWeightCell(weight: weight, tolerance: tolerance, kind: .estimated, isPlaceholder: true)
    }

    /// A measured weight.
    static func measured(_ weight: FontWeight, _ tolerance: Double) -> FontWeightCell {
        FontWeightCell(weight: weight, tolerance: tolerance, kind: .measured, isPlaceholder: false)
    }

    /// An invented weight.
    static func invented(_ weight: FontWeight) -> FontWeightCell {
        FontWeightCell(weight: weight, tolerance: nil, kind: .invented, isPlaceholder: false)
    }
}

/// A typeface: the export's `font-family` unit. It defines one value.
public enum Typeface: String, CaseIterable, Sendable {
    /// The system font (SF Pro), used through `UIFont.systemFont(ofSize:weight:)`. We ship no Apple font files.
    case system
}

/// One typeface token's value, with where it comes from.
public struct TypefaceCell: Equatable, Sendable {
    /// The typeface, exactly as the export gives it.
    public let typeface: Typeface

    /// Plus or minus, in the export's `enum` tolerance unit: 0 means the value is either right or wrong. `nil` for
    /// an invented typeface.
    public let tolerance: Double?

    /// Where the typeface comes from.
    public let kind: MetricKind

    /// True when the export gives the typeface no basis at all (confidence "none").
    public let isPlaceholder: Bool

    /// An estimate with some basis.
    static func estimated(_ typeface: Typeface, _ tolerance: Double) -> TypefaceCell {
        TypefaceCell(typeface: typeface, tolerance: tolerance, kind: .estimated, isPlaceholder: false)
    }

    /// An estimate with no basis (confidence "none").
    static func placeholder(_ typeface: Typeface, _ tolerance: Double) -> TypefaceCell {
        TypefaceCell(typeface: typeface, tolerance: tolerance, kind: .estimated, isPlaceholder: true)
    }

    /// A measured typeface.
    static func measured(_ typeface: Typeface, _ tolerance: Double) -> TypefaceCell {
        TypefaceCell(typeface: typeface, tolerance: tolerance, kind: .measured, isPlaceholder: false)
    }

    /// An invented typeface.
    static func invented(_ typeface: Typeface) -> TypefaceCell {
        TypefaceCell(typeface: typeface, tolerance: nil, kind: .invented, isPlaceholder: false)
    }
}
