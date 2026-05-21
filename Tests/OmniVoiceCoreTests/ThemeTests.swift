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

    func testBuiltInPresetModeDefaultsAreAvailable() throws {
        let neonLime = try XCTUnwrap(OmniVoiceTheme.builtInTheme(id: .neonLime))
        XCTAssertEqual(neonLime.waveformMode, .bars)
        XCTAssertEqual(neonLime.commitAnimationMode, .beamSnap)
        XCTAssertEqual(neonLime.engineFrameSide, .left)

        let deepSignal = try XCTUnwrap(OmniVoiceTheme.builtInTheme(id: .deepSignal))
        XCTAssertEqual(deepSignal.waveformMode, .spectrumLine)
        XCTAssertEqual(deepSignal.commitAnimationMode, .glyphStream)
        XCTAssertEqual(deepSignal.engineFrameSide, .left)
    }

    func testCustomAccentDerivesReadableTheme() {
        let theme = OmniVoiceTheme.custom(accent: ThemeColor(hex: "#00A3FF"))

        XCTAssertEqual(theme.id, .custom)
        XCTAssertEqual(theme.accentColor.hex, "#00A3FF")
        XCTAssertGreaterThan(theme.glassOpacity, 0.30)
        XCTAssertLessThanOrEqual(theme.captionOpacity, 0.24)
        XCTAssertEqual(theme.waveformMode, .bars)
    }

    func testThemeColorDecodingNormalizesHex() throws {
        let data = Data(#"{"hex":"38bdf8"}"#.utf8)

        let color = try JSONDecoder().decode(ThemeColor.self, from: data)

        XCTAssertEqual(color.hex, "#38BDF8")
    }

    func testAppearanceModesExposeDisplayNames() {
        XCTAssertEqual(AppAppearanceMode.system.displayName, "System")
        XCTAssertEqual(AppAppearanceMode.dark.displayName, "Dark")
        XCTAssertEqual(AppAppearanceMode.light.displayName, "Light")
    }

    func testCSSVariablesClampAlphaValues() {
        let theme = OmniVoiceTheme(
            id: .custom,
            name: "Clamp Test",
            accentColor: ThemeColor(hex: "#38BDF8"),
            secondaryAccentColor: ThemeColor(hex: "#818CF8"),
            surfaceTint: ThemeColor(hex: "#06121C"),
            glassOpacity: 1.50,
            captionOpacity: -0.25,
            glowStrength: 1.75,
            contrastMode: .standard,
            waveformMode: .bars,
            commitAnimationMode: .glyphStream,
            engineFrameSide: .right,
            motionIntensity: 2.0
        )

        XCTAssertEqual(theme.cssVariables["--ov-surface"], "rgba(6, 18, 28, 1.00)")
        XCTAssertEqual(theme.cssVariables["--ov-surface-strong"], "rgba(6, 18, 28, 1.00)")
        XCTAssertEqual(theme.cssVariables["--ov-caption-bg"], "rgba(6, 18, 28, 0.00)")
        XCTAssertEqual(theme.cssVariables["--ov-glow"], "rgba(56, 189, 248, 1.00)")
    }

    func testBorderOpacityTokenDrivesCSSBorderAlpha() throws {
        let theme = try XCTUnwrap(OmniVoiceTheme.builtInTheme(id: .monoGlass))

        XCTAssertEqual(theme.borderOpacity, 0.26)
        XCTAssertEqual(theme.cssVariables["--ov-border"], "rgba(248, 250, 252, 0.26)")
    }

    func testReadableTextTokensDriveCSSVariables() throws {
        let lightTheme = try XCTUnwrap(OmniVoiceTheme.builtInTheme(id: .arcticGlass))

        XCTAssertEqual(lightTheme.textColor.hex, "#06121C")
        XCTAssertEqual(lightTheme.mutedTextColor.hex, "#06121C")
        XCTAssertEqual(lightTheme.mutedTextOpacity, 0.64)
        XCTAssertEqual(lightTheme.cssVariables["--ov-text"], lightTheme.textColor.hex)
        XCTAssertEqual(lightTheme.cssVariables["--ov-muted"], ThemeColor.cssRGBA(red: 6, green: 18, blue: 28, alpha: lightTheme.mutedTextOpacity))

        let highContrastTheme = try XCTUnwrap(OmniVoiceTheme.builtInTheme(id: .highContrast))
        XCTAssertEqual(highContrastTheme.textColor.hex, "#FFFFFF")
        XCTAssertEqual(highContrastTheme.cssVariables["--ov-muted"], ThemeColor.cssRGBA(red: 255, green: 255, blue: 255, alpha: highContrastTheme.mutedTextOpacity))
    }

    func testResolvedAccentTextMeetsContrastInLightAndDarkModes() {
        for theme in OmniVoiceTheme.builtIn {
            for appearance in [ThemeResolvedAppearance.light, .dark] {
                let palette = theme.resolvedPalette(for: appearance)

                XCTAssertGreaterThanOrEqual(
                    palette.accentText.contrastRatio(against: palette.windowBackground),
                    4.5,
                    "\(theme.name) \(appearance) accent text should be readable"
                )
                XCTAssertGreaterThanOrEqual(
                    palette.secondaryAccentText.contrastRatio(against: palette.windowBackground),
                    4.5,
                    "\(theme.name) \(appearance) secondary accent text should be readable"
                )
                XCTAssertGreaterThanOrEqual(
                    palette.onAccentText.contrastRatio(against: palette.accentGraphic),
                    4.5,
                    "\(theme.name) \(appearance) on-accent text should be readable"
                )
            }
        }
    }

    func testDockIconSpectrumProfileUsesSubtleNormalizedVULevels() {
        let profile = DockIconSpectrumProfile.subtleVU

        XCTAssertEqual(profile.normalizedLevels.count, 9)
        XCTAssertEqual(profile.normalizedLevels, profile.normalizedLevels.reversed())
        XCTAssertEqual(profile.normalizedLevels.max(), 1.0)
        XCTAssertGreaterThan(profile.normalizedLevels[4], profile.normalizedLevels[0])
        XCTAssertLessThanOrEqual(profile.glowOpacity, 0.24)
    }

    func testCSSVariablesUseOmniVoiceNames() throws {
        let theme = try XCTUnwrap(OmniVoiceTheme.builtInTheme(id: .auroraBlue))

        XCTAssertEqual(Set(theme.cssVariables.keys), [
            "--ov-accent",
            "--ov-accent-text",
            "--ov-accent-secondary",
            "--ov-accent-secondary-text",
            "--ov-bg",
            "--ov-surface",
            "--ov-surface-strong",
            "--ov-text",
            "--ov-muted",
            "--ov-on-accent",
            "--ov-border",
            "--ov-glow",
            "--ov-caption-bg"
        ])
        XCTAssertEqual(theme.cssVariables["--ov-accent"], "#38BDF8")
        XCTAssertEqual(theme.cssVariables["--ov-accent-text"], "#38BDF8")
        XCTAssertEqual(theme.cssVariables["--ov-accent-secondary"], "#818CF8")
        XCTAssertEqual(theme.cssVariables["--ov-accent-secondary-text"], "#818CF8")
        XCTAssertEqual(theme.cssVariables["--ov-bg"], "#06121C")
        XCTAssertEqual(theme.cssVariables["--ov-surface"], "rgba(6, 18, 28, 0.36)")
        XCTAssertEqual(theme.cssVariables["--ov-surface-strong"], "rgba(6, 18, 28, 0.54)")
        XCTAssertEqual(theme.cssVariables["--ov-text"], "#F8FAFC")
        XCTAssertEqual(theme.cssVariables["--ov-muted"], "rgba(248, 250, 252, 0.64)")
        XCTAssertEqual(theme.cssVariables["--ov-on-accent"], "#06121C")
        XCTAssertEqual(theme.cssVariables["--ov-border"], "rgba(56, 189, 248, 0.26)")
        XCTAssertEqual(theme.cssVariables["--ov-caption-bg"], "rgba(6, 18, 28, 0.14)")
        XCTAssertEqual(theme.cssVariables["--ov-glow"], "rgba(56, 189, 248, 0.34)")
    }
}
