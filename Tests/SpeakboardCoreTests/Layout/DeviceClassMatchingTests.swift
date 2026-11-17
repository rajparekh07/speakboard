import Testing

@testable import SpeakboardCore

@Suite("Keyboard layout: the device class and orientation of a screen")
struct DeviceClassMatchingTests {
    @Test("Every class in the export matches itself exactly, in both orientations", arguments: DeviceClass.allCases)
    func exact(deviceClass: DeviceClass) {
        let portrait = DeviceClass.match(screenWidth: deviceClass.screenWidth, screenHeight: deviceClass.screenHeight)
        #expect(portrait == DeviceClassMatch(deviceClass: deviceClass, isExact: true))
        let landscape = DeviceClass.match(screenWidth: deviceClass.screenHeight, screenHeight: deviceClass.screenWidth)
        #expect(landscape == DeviceClassMatch(deviceClass: deviceClass, isExact: true))
    }

    @Test("An unlisted size gets the class nearest by portrait width, and is not exact")
    func nearestWidth() {
        #expect(
            DeviceClass.match(screenWidth: 401, screenHeight: 870) == .init(deviceClass: .iphone402x874, isExact: false)
        )
        #expect(
            DeviceClass.match(screenWidth: 870, screenHeight: 401) == .init(deviceClass: .iphone402x874, isExact: false)
        )
    }

    @Test("With the width tied, the nearer portrait height decides")
    func nearestHeight() {
        // 375 points wide matches two classes exactly in width: 375x667 and 375x812.
        #expect(DeviceClass.match(screenWidth: 375, screenHeight: 700).deviceClass == .iphone375x667)
        #expect(DeviceClass.match(screenWidth: 375, screenHeight: 780).deviceClass == .iphone375x812)
        // The same width, 1 point taller than the class: nearest, not exact.
        #expect(
            DeviceClass.match(screenWidth: 375, screenHeight: 813) == .init(deviceClass: .iphone375x812, isExact: false)
        )
    }

    @Test("Equally near in width and height, the class listed first wins")
    func equalDistance() {
        // 391.5 is 1.5 from 390 and from 393; 848 is 4 from 844 and from 852.
        #expect(DeviceClass.match(screenWidth: 391.5, screenHeight: 848).deviceClass == .iphone390x844)
        // 375 wide, and 739.5 is 72.5 from both 667 and 812.
        #expect(DeviceClass.match(screenWidth: 375, screenHeight: 739.5).deviceClass == .iphone375x667)
    }

    @Test("Sizes far from every class get the nearest edge of the list")
    func farSizes() {
        #expect(
            DeviceClass.match(screenWidth: 320, screenHeight: 568) == .init(deviceClass: .iphone375x667, isExact: false)
        )
        #expect(DeviceClass.match(screenWidth: 1024, screenHeight: 1366).deviceClass == .iphone440x956)
        #expect(DeviceClass.match(screenWidth: 0, screenHeight: 0).deviceClass == .iphone375x667)
    }

    @Test("A huge finite size, in either order, gets the widest class")
    func hugeSizes() {
        let huge = Double.greatestFiniteMagnitude
        let sizes: [(Double, Double)] = [(1e308, 1e308), (huge, huge), (1e308, 874), (874, 1e308), (1e17, 1e17)]
        for (width, height) in sizes {
            #expect(
                DeviceClass.match(screenWidth: width, screenHeight: height)
                    == .init(deviceClass: .iphone440x956, isExact: false),
                "\(width) x \(height)")
        }
    }

    @Test("A negative side counts as 0, in either order")
    func negativeSides() {
        // Portrait width 0: the two 375-point classes, then the nearer height (874 is nearer 812 than 667).
        #expect(DeviceClass.match(screenWidth: -5, screenHeight: 874).deviceClass == .iphone375x812)
        #expect(DeviceClass.match(screenWidth: 874, screenHeight: -5).deviceClass == .iphone375x812)
        #expect(DeviceClass.match(screenWidth: -1e308, screenHeight: -1e308).deviceClass == .iphone375x667)
    }

    @Test("A side that is not finite, in either argument, gets the first class, not exact")
    func nonFiniteSides() {
        let sizes: [(Double, Double)] = [
            (.nan, 874), (874, .nan), (.nan, .nan),
            (.infinity, 874), (874, .infinity), (.infinity, .infinity),
            (-.infinity, 874), (874, -.infinity), (.infinity, -.infinity),
        ]
        for (width, height) in sizes {
            #expect(
                DeviceClass.match(screenWidth: width, screenHeight: height)
                    == .init(deviceClass: .iphone375x667, isExact: false),
                "\(width) x \(height)")
        }
    }

    @Test("Wider than high is landscape; otherwise, a square included, portrait")
    func orientation() {
        #expect(Orientation(screenWidth: 874, screenHeight: 402) == .landscape)
        #expect(Orientation(screenWidth: 402, screenHeight: 874) == .portrait)
        #expect(Orientation(screenWidth: 500, screenHeight: 500) == .portrait)
        #expect(Orientation(screenWidth: .nan, screenHeight: 874) == .portrait)
        #expect(Orientation(screenWidth: 874, screenHeight: .nan) == .portrait)
    }
}
