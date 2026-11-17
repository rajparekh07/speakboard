import KeyboardKit
import SpeakboardCore
import Testing
import UIKit

@Suite("KeyboardKit: device classes")
struct DeviceClassResolverTests {
    @Test("Every class in the export resolves to itself, in both orientations", arguments: DeviceClass.allCases)
    func exact(deviceClass: DeviceClass) {
        let portrait = DeviceClassResolver.resolve(width: deviceClass.screenWidth, height: deviceClass.screenHeight)
        #expect(portrait.deviceClass == deviceClass)
        #expect(portrait.isExact)
        let landscape = DeviceClassResolver.resolve(width: deviceClass.screenHeight, height: deviceClass.screenWidth)
        #expect(landscape.deviceClass == deviceClass)
        #expect(landscape.isExact)
    }

    @Test("A size the export does not list gets the nearest class, and says so")
    func nearest() {
        let result = DeviceClassResolver.resolve(width: 401, height: 870)
        #expect(result.deviceClass == .iphone402x874)
        #expect(!result.isExact)
    }

    @Test("Wider than high is landscape")
    func orientation() {
        #expect(DeviceClassResolver.orientation(width: 874, height: 402) == .landscape)
        #expect(DeviceClassResolver.orientation(width: 402, height: 874) == .portrait)
    }
}

@Suite("KeyboardKit: the placeholder view")
@MainActor
struct PlaceholderKeyboardViewTests {
    @Test("Its height is the core's keyboard height for the device", arguments: DeviceClass.allCases)
    func height(deviceClass: DeviceClass) throws {
        let view = PlaceholderKeyboardView(frame: .zero)
        let height = view.update(screenWidth: deviceClass.screenWidth, screenHeight: deviceClass.screenHeight)
        let layout = try #require(KeyboardLayout(locale: .english, deviceClass: deviceClass, orientation: .portrait))
        #expect(height == layout.size.height)
        #expect(view.layout?.keys.count == layout.keys.count)
    }

    @Test("It says it is a placeholder, and names the core's layout")
    func text() {
        let view = PlaceholderKeyboardView(frame: .zero)
        view.update(screenWidth: 402, screenHeight: 874)
        #expect(view.lines.first == "Speakboard · placeholder keyboard")
        #expect(view.lines.contains { $0.contains("iphone-402x874 portrait") })
        #expect(!view.lines.contains { $0.hasPrefix("Full Access") })
    }

    @Test("It shows whether the keyboard has Full Access, when told")
    func fullAccess() {
        let view = PlaceholderKeyboardView(frame: .zero)
        view.update(screenWidth: 402, screenHeight: 874, hasFullAccess: true)
        #expect(view.lines.last == "Full Access: on")
        view.update(screenWidth: 402, screenHeight: 874, hasFullAccess: false)
        #expect(view.lines.last == "Full Access: off")
    }
}
