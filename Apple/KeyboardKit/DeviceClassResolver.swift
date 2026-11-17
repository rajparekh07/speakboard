import SpeakboardCore

/// Picks the core's device class for a screen. A thin adapter: the classes and their sizes are the core's, from the
/// design token export.
public enum DeviceClassResolver {
    /// The device class for a screen of `width` by `height` points, in either orientation, and whether the size
    /// matched a class exactly. A size the export does not list gets the class with the nearest portrait width,
    /// then the nearest portrait height, so the keyboard still has a layout on a new iPhone.
    public static func resolve(width: Double, height: Double) -> (deviceClass: DeviceClass, isExact: Bool) {
        let portraitWidth = min(width, height)
        let portraitHeight = max(width, height)
        if let exact = DeviceClass.allCases.first(where: {
            $0.screenWidth == portraitWidth && $0.screenHeight == portraitHeight
        }) {
            return (exact, true)
        }
        var best = DeviceClass.allCases[0]
        for candidate in DeviceClass.allCases {
            let candidateDistance = (
                abs(candidate.screenWidth - portraitWidth), abs(candidate.screenHeight - portraitHeight)
            )
            let bestDistance = (abs(best.screenWidth - portraitWidth), abs(best.screenHeight - portraitHeight))
            if candidateDistance < bestDistance {
                best = candidate
            }
        }
        return (best, false)
    }

    /// The orientation of a screen of `width` by `height` points: landscape when it is wider than it is high.
    public static func orientation(width: Double, height: Double) -> Orientation {
        width > height ? .landscape : .portrait
    }
}
