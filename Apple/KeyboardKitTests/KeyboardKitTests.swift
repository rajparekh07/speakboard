import KeyboardKit
import SpeakboardCore
import Testing
import UIKit

// Which class and orientation a screen gets is the core's (DeviceClass.match, Orientation(screenWidth:...)),
// tested on Linux in Tests/SpeakboardCoreTests/Layout/DeviceClassMatchingTests.swift. These tests check the view
// passes the screen in and shows what the core returns.

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

    @Test("A screen the export does not list gets the core's nearest class, and says so")
    func nearest() {
        let view = PlaceholderKeyboardView(frame: .zero)
        let height = view.update(screenWidth: 401, screenHeight: 870)
        #expect(view.layout?.deviceClass == .iphone402x874)
        #expect(view.lines.contains { $0.contains("(nearest to 401x870)") })
        #expect(
            height == KeyboardLayout(locale: .english, deviceClass: .iphone402x874, orientation: .portrait)?.size.height
        )
    }

    @Test("A landscape screen gets the landscape layout")
    func landscape() throws {
        let view = PlaceholderKeyboardView(frame: .zero)
        let height = view.update(screenWidth: 874, screenHeight: 402)
        let layout = try #require(
            KeyboardLayout(locale: .english, deviceClass: .iphone402x874, orientation: .landscape))
        #expect(view.layout?.orientation == .landscape)
        #expect(height == layout.size.height)
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
