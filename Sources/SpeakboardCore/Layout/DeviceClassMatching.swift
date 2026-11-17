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
    /// a keyboard on an iPhone the export does not know yet. A size far from every class gets the nearest edge of
    /// the list: anything narrower than 375 points gets `iphone375x667` or `iphone375x812`, anything wider than
    /// 440 points gets `iphone440x956`. A size with a non-finite side gets the first class, `iphone375x667`.
    public static func match(screenWidth: Double, screenHeight: Double) -> DeviceClassMatch {
        let portraitWidth = min(screenWidth, screenHeight)
        let portraitHeight = max(screenWidth, screenHeight)
        let classes = DeviceClass.allCases
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
}

extension Orientation {
    /// The orientation of a screen of `screenWidth` by `screenHeight` points: landscape when it is wider than it
    /// is high, portrait otherwise (a square screen is portrait).
    public init(screenWidth: Double, screenHeight: Double) {
        self = screenWidth > screenHeight ? .landscape : .portrait
    }
}
