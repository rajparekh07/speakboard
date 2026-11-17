import SpeakboardCore
import Testing

@Suite("Key labels and opaque colours")
struct KeyLabelsTests {
    @Test("English has a label for the space bar, 123 and every return key type")
    func english() throws {
        let labels = try #require(KeyLabels(locale: .english))
        #expect(labels.space == "space")
        #expect(labels.modeSwitch == "123")
        #expect(labels.returnTitle(.default) == "return")
        #expect(labels.returnTitle(.go) == "go")
        #expect(labels.returnTitle(.done) == "done")
        for type in ReturnKeyType.allCases {
            #expect(!labels.returnTitle(type).isEmpty, "\(type)")
        }
    }

    @Test("A regional variant gets its language's labels; a locale with none gets nil")
    func locales() {
        #expect(KeyLabels(locale: KeyboardLocale(identifier: "en-GB"))?.locale == .english)
        #expect(KeyLabels(locale: KeyboardLocale(identifier: "fr")) == nil)
    }

    @Test("An opaque colour keeps red, green and blue and has alpha 1")
    func opaque() {
        let color = RGBAColor(0x8989_8D40)
        #expect(color.opaque.rgba == 0x8989_8DFF)
        #expect(color.opaque.alpha == 1)
        #expect(color.opaque.red == color.red && color.opaque.blue == color.blue)
        #expect(RGBAColor(0x0000_00FF).opaque == RGBAColor(0x0000_00FF))
    }
}
