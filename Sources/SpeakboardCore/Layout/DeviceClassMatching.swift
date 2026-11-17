// Which device class and orientation a screen gets: the layout policy for a
// screen size, kept in the core (ADR-0005) so it is tested on Linux, and the
// keyboard extension only passes in its screen's bounds (KEY-8).

/// The device class a screen gets, and whether its size is one the token export lists.
public struct DeviceClassMatch: Equatable, Sendable {
    /// The class whose layout the screen gets.
    public let deviceClass: DeviceClass
    /// True when the screen's size is exactly the class's size, in either orientation.
    public let isExact: Bool
}

extension DeviceClass {
    /// The device class for a screen of `screenWidth` by `screenHeight` points, in either orientation.
    ///
    /// A size the token export lists, in portrait or landscape, gets its own class. Any other size gets the class
    /// nearest to it: by portrait width first, then by portrait height, and on a tie in both the class listed first
    /// in `allCases` (the narrower, then the shorter). This fallback is a decision of KEY-8, not a token: it keeps
    /// a keyboard on an iPhone the export does not know yet.
    ///
    /// Sizes far from every class: each side is clamped to 0 through 10 000 points before the distances are
    /// measured (no class is near either bound), so the distances are exact whatever the size, and a size far
    /// from every class gets the nearest edge of the list. Anything narrower than 375 points in portrait, a negative
    /// side included, gets `iphone375x667` or `iphone375x812` by its height; anything wider than 440 points, up to
    /// the largest finite `Double`, gets `iphone440x956`.
    ///
    /// A size with a side that is not finite (NaN, or either infinity), in either argument, gets the first class,
    /// `iphone375x667`, not exact: there is no nearest class to a size that is not a number.
    public static func match(screenWidth: Double, screenHeight: Double) -> DeviceClassMatch {
        let classes = DeviceClass.allCases
        guard screenWidth.isFinite && screenHeight.isFinite else {
            return DeviceClassMatch(deviceClass: classes[0], isExact: false)
        }
        let portraitWidth = clampedSide(min(screenWidth, screenHeight))
        let portraitHeight = clampedSide(max(screenWidth, screenHeight))
        var best = classes[0]
        var bestWidthDistance = abs(best.screenWidth - portraitWidth)
        var bestHeightDistance = abs(best.screenHeight - portraitHeight)
        var index = 1
        while index < classes.count {
            let candidate = classes[index]
            let widthDistance = abs(candidate.screenWidth - portraitWidth)
            let heightDistance = abs(candidate.screenHeight - portraitHeight)
            if widthDistance < bestWidthDistance
                || (widthDistance == bestWidthDistance && heightDistance < bestHeightDistance)
            {
                best = candidate
                bestWidthDistance = widthDistance
                bestHeightDistance = heightDistance
            }
            index += 1
        }
        return DeviceClassMatch(deviceClass: best, isExact: bestWidthDistance == 0 && bestHeightDistance == 0)
    }

    /// A finite side clamped to 0 through 10 000 points. Every class's sides are inside that range, so clamping
    /// does not change which class is nearest, and it keeps the distances small enough to be exact.
    private static func clampedSide(_ side: Double) -> Double {
        min(max(side, 0), 10_000)
    }
}

extension Orientation {
    /// The orientation of a screen of `screenWidth` by `screenHeight` points: landscape when it is wider than it
    /// is high, portrait otherwise: a square screen is portrait, and so is one with a NaN side, since no comparison
    /// with NaN holds.
    public init(screenWidth: Double, screenHeight: Double) {
        self = screenWidth > screenHeight ? .landscape : .portrait
    }
}
