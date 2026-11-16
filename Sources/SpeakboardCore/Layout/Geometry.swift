// The small geometry types the layout needs. The core has no CoreGraphics, so it
// has its own. Coordinates are points, with the origin at the top left of the
// keyboard view (the suggestion bar's top left) and y growing downwards, as in
// UIKit.

/// A point, in points.
public struct LayoutPoint: Equatable, Sendable {
    /// The horizontal coordinate.
    public var x: Double
    /// The vertical coordinate, growing downwards.
    public var y: Double

    /// A point at `x`, `y`.
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A size, in points.
public struct LayoutSize: Equatable, Sendable {
    /// The width.
    public var width: Double
    /// The height.
    public var height: Double

    /// A size of `width` by `height`.
    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

/// A rectangle, in points: its top-left corner and its size.
public struct LayoutRect: Equatable, Sendable {
    /// The left edge.
    public var x: Double
    /// The top edge.
    public var y: Double
    /// The width.
    public var width: Double
    /// The height.
    public var height: Double

    /// A rectangle with its top-left corner at `x`, `y`.
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// The left edge.
    public var minX: Double { x }
    /// The right edge.
    public var maxX: Double { x + width }
    /// The top edge.
    public var minY: Double { y }
    /// The bottom edge.
    public var maxY: Double { y + height }
    /// The centre.
    public var center: LayoutPoint { LayoutPoint(x: x + width / 2, y: y + height / 2) }

    /// Whether the rectangle contains `point`. The left and top edges are inside and the right and bottom edges
    /// outside, so two rectangles that share an edge never both contain a point on it.
    public func contains(_ point: LayoutPoint) -> Bool {
        point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
    }
}
