// The types the generated metrics tables are made of. The tables themselves are
// GeneratedMetrics.swift, generated from the pinned design token export.

/// A device orientation. Landscape width is the portrait screen height.
public enum Orientation: String, CaseIterable, Sendable {
    /// Portrait.
    case portrait
    /// Landscape.
    case landscape
}

/// Where a metric's value comes from, as the token export records it.
public enum MetricKind: Sendable {
    /// Measured from the system keyboard.
    case measured
    /// An estimate, not yet measured.
    case estimated
    /// Our own decision, not an estimate of Apple's value.
    case invented
}

/// One cell of the metrics table: a token's value for one device class and orientation.
public struct MetricCell: Equatable, Sendable {
    /// The value, in the token's unit (points or a ratio), exactly as the export gives it.
    public let value: Double

    /// Plus or minus, in the value's unit. `nil` for an invented value, which is a decision, not an estimate.
    public let tolerance: Double?

    /// Where the value comes from.
    public let kind: MetricKind

    /// True when the export gives the value no basis at all (confidence "none").
    public let isPlaceholder: Bool

    /// An estimate with some basis.
    static func estimated(_ value: Double, _ tolerance: Double) -> MetricCell {
        MetricCell(value: value, tolerance: tolerance, kind: .estimated, isPlaceholder: false)
    }

    /// An estimate with no basis (confidence "none").
    static func placeholder(_ value: Double, _ tolerance: Double) -> MetricCell {
        MetricCell(value: value, tolerance: tolerance, kind: .estimated, isPlaceholder: true)
    }

    /// A measured value.
    static func measured(_ value: Double, _ tolerance: Double) -> MetricCell {
        MetricCell(value: value, tolerance: tolerance, kind: .measured, isPlaceholder: false)
    }

    /// An invented value.
    static func invented(_ value: Double) -> MetricCell {
        MetricCell(value: value, tolerance: nil, kind: .invented, isPlaceholder: false)
    }
}
