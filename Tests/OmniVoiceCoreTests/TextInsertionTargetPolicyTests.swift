import XCTest
@testable import OmniVoiceCore

final class TextInsertionTargetPolicyTests: XCTestCase {
    func testCodexNamedAppUsesPasteboardOnlyInsertion() {
        let strategy = TextInsertionTargetPolicy.strategy(
            bundleIdentifier: "com.openai.codex",
            applicationName: "Codex",
            currentValue: "Build iOS Apps",
            selectedRange: NSRange(location: 14, length: 0)
        )

        XCTAssertEqual(strategy, .pasteboardOnly)
    }

    func testBrowserRichComposerUsesPasteboardOnlyInsertion() {
        let strategy = TextInsertionTargetPolicy.strategy(
            bundleIdentifier: "com.google.Chrome",
            applicationName: "Google Chrome",
            currentValue: "Build macOS Apps",
            selectedRange: NSRange(location: 16, length: 0)
        )

        XCTAssertEqual(strategy, .pasteboardOnly)
    }

    func testPlainNativeTextTargetUsesDirectAccessibilityInsertion() {
        let strategy = TextInsertionTargetPolicy.strategy(
            bundleIdentifier: "com.apple.TextEdit",
            applicationName: "TextEdit",
            currentValue: "Hello",
            selectedRange: NSRange(location: 5, length: 0)
        )

        XCTAssertEqual(strategy, .directAccessibility)
    }

    func testArcSubstringDoesNotFalsePositiveOnUnrelatedApps() {
        let archiveUtility = TextInsertionTargetPolicy.strategy(
            bundleIdentifier: "com.apple.archiveutility",
            applicationName: "Archive Utility",
            currentValue: "",
            selectedRange: NSRange(location: 0, length: 0)
        )
        let searchApp = TextInsertionTargetPolicy.strategy(
            bundleIdentifier: "com.example.search",
            applicationName: "Search",
            currentValue: "",
            selectedRange: NSRange(location: 0, length: 0)
        )

        XCTAssertEqual(archiveUtility, .directAccessibility)
        XCTAssertEqual(searchApp, .directAccessibility)
    }

    func testArcBrowserUsesPasteboardOnlyInsertion() {
        let byBundleID = TextInsertionTargetPolicy.strategy(
            bundleIdentifier: "company.thebrowser.Browser",
            applicationName: "Browser",
            currentValue: "",
            selectedRange: NSRange(location: 0, length: 0)
        )
        let byName = TextInsertionTargetPolicy.strategy(
            bundleIdentifier: "com.example.custom",
            applicationName: "Arc",
            currentValue: "",
            selectedRange: NSRange(location: 0, length: 0)
        )

        XCTAssertEqual(byBundleID, .pasteboardOnly)
        XCTAssertEqual(byName, .pasteboardOnly)
    }

    func testElectronEditorsAndTerminalsUsePasteboardOnlyInsertion() {
        let targets: [(String, String)] = [
            ("com.google.antigravity", "Antigravity"),
            ("com.microsoft.VSCode", "Code"),
            ("com.todesktop.230313mzl4w4u92", "Cursor"),
            ("com.mitchellh.ghostty", "Ghostty"),
            ("com.apple.Terminal", "Terminal"),
        ]

        for (bundleID, appName) in targets {
            let strategy = TextInsertionTargetPolicy.strategy(
                bundleIdentifier: bundleID,
                applicationName: appName,
                currentValue: "",
                selectedRange: NSRange(location: 0, length: 0)
            )
            XCTAssertEqual(strategy, .pasteboardOnly, "Expected pasteboardOnly for \(appName) (\(bundleID))")
        }
    }
}
