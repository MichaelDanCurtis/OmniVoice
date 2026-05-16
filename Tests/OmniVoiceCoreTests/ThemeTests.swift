import XCTest
@testable import OmniVoiceCore

final class ThemeTests: XCTestCase {
    func testBuiltInThemesContainTwentyPresets() {
        XCTAssertEqual(OmniVoiceTheme.builtIn.count, 20)
        XCTAssertEqual(Set(OmniVoiceTheme.builtIn.map(\.id)).count, 20)
    }

    func testDefaultThemeIsAuroraBlue() throws {
        let theme = try XCTUnwrap(OmniVoiceTheme.builtInTheme(id: .auroraBlue))

        XCTAssertEqual(theme.name, "Aurora Blue")
        XCTAssertEqual(theme.accentColor.hex, "#38BDF8")
        XCTAssertEqual(theme.waveformMode, .bars)
        XCTAssertEqual(theme.commitAnimationMode, .glyphStream)
        XCTAssertEqual(theme.engineFrameSide, .right)
    }

    func testCustomAccentDerivesReadableTheme() {
        let theme = OmniVoiceTheme.custom(accent: ThemeColor(hex: "#00A3FF"))

        XCTAssertEqual(theme.id, .custom)
        XCTAssertEqual(theme.accentColor.hex, "#00A3FF")
        XCTAssertGreaterThan(theme.glassOpacity, 0.30)
        XCTAssertLessThanOrEqual(theme.captionOpacity, 0.24)
        XCTAssertEqual(theme.waveformMode, .bars)
    }

    func testCSSVariablesUseOmniVoiceNames() throws {
        let theme = try XCTUnwrap(OmniVoiceTheme.builtInTheme(id: .auroraBlue))

        XCTAssertEqual(theme.cssVariables["--ov-accent"], "#38BDF8")
        XCTAssertEqual(theme.cssVariables["--ov-caption-bg"], "rgba(6, 18, 28, 0.14)")
        XCTAssertEqual(theme.cssVariables["--ov-glow"], "rgba(56, 189, 248, 0.34)")
    }
}
