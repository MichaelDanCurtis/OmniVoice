# OmniVoice v2 Theme Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the v2 visual/settings foundation: theme tokens, 20 presets, custom accent derivation, waveform mode preferences, themed caption/hotkey/settings surfaces, a themed engine dashboard, and a collapsible embedded engine frame.

**Architecture:** Keep theme data in `OmniVoiceCore` as Codable value types so preferences, tests, and native UI can share one source of truth. Keep SwiftUI rendering adapters in `OmniVoiceApp`, because `OmniVoiceCore` should not depend on SwiftUI. Let the engine dashboard consume the same token names through CSS custom properties, with a default theme endpoint for standalone browser use and later native injection through the embedded frame.

**Tech Stack:** Swift 6, SwiftUI, AppKit, WebKit, XCTest, FastAPI, Pydantic, vanilla HTML/CSS/JS.

---

## Scope Split

This plan implements the first v2 slice only. It intentionally does not implement live translation, AI handoff, conversation transcription, diarization, or live text insertion. Those features depend on the shared theme/settings foundation and should get separate plans after this slice lands.

## File Structure

- Create `Sources/OmniVoiceCore/Theme.swift`: Codable theme IDs, waveform modes, commit animation modes, engine frame side, color tokens, preset registry, and accent derivation.
- Modify `Sources/OmniVoiceCore/PreferencesStore.swift`: add theme preferences and backward-compatible decoding defaults.
- Add tests in `Tests/OmniVoiceCoreTests/ThemeTests.swift`: preset count, default token values, custom accent derivation, CSS variable generation, and preference migration.
- Modify `Tests/OmniVoiceCoreTests/PreferencesStoreTests.swift`: assert theme defaults round-trip.
- Create `Sources/OmniVoiceApp/ThemeRendering.swift`: SwiftUI color conversion, glass material helpers, theme environment injection, and reusable themed surface modifier.
- Modify `Sources/OmniVoiceApp/AppModel.swift`: expose active theme, theme setters, waveform setters, and engine-frame side setters.
- Modify `Sources/OmniVoiceApp/SettingsView.swift`: add Appearance, Theme Presets, Custom Theme, Waveform/VU, Commit Animation, and Engine Frame sections.
- Modify `Sources/OmniVoiceApp/CaptionOverlayView.swift`: render themed glass caption and use selected waveform mode.
- Modify `Sources/OmniVoiceApp/HotkeyRecorderView.swift`: apply themed glass recorder treatment.
- Modify `Sources/OmniVoiceApp/MenuBarControlsView.swift`: expose theme state and engine frame action.
- Create `Sources/OmniVoiceApp/EngineFrameView.swift`: WebKit wrapper and collapsible left/right dashboard frame.
- Modify `Sources/OmniVoiceApp/OmniVoiceApp.swift`: compose the themed control center and embedded engine frame.
- Modify `engine/omnivoice_engine/schemas.py`: add `ThemePayload`.
- Modify `engine/omnivoice_engine/main.py`: add `/api/theme/default`.
- Modify `engine/omnivoice_engine/static/dashboard.css`: rename visual variables to `--ov-*` with fallback values.
- Modify `engine/omnivoice_engine/static/dashboard.js`: add theme application helper and load `/api/theme/default` in browser mode.
- Modify `engine/tests/test_api.py`: test the theme endpoint.

---

### Task 1: Core Theme Model

**Files:**
- Create: `Sources/OmniVoiceCore/Theme.swift`
- Test: `Tests/OmniVoiceCoreTests/ThemeTests.swift`

- [ ] **Step 1: Write failing tests for theme presets and defaults**

Create `Tests/OmniVoiceCoreTests/ThemeTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the new tests and verify they fail**

Run:

```bash
swift test --filter ThemeTests
```

Expected: FAIL because `OmniVoiceTheme`, `ThemeColor`, and related types do not exist.

- [ ] **Step 3: Add the theme model**

Create `Sources/OmniVoiceCore/Theme.swift`:

```swift
import Foundation

public enum OmniVoiceThemeID: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case auroraBlue
    case obsidianCyan
    case deepSignal
    case arcticGlass
    case cobaltPulse
    case neonLime
    case acidGlass
    case emeraldVoice
    case matrixSoft
    case prismBlue
    case prismPink
    case violetBeam
    case magentaGlass
    case emberWave
    case solarTrace
    case redline
    case graphiteIce
    case steelWhisper
    case monoGlass
    case highContrast
    case custom
}

public enum WaveformMode: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case bars
    case pulseRing
    case spectrumLine
    case orbMeter
    case glyphStream

    public var displayName: String {
        switch self {
        case .bars: "Bars"
        case .pulseRing: "Pulse Ring"
        case .spectrumLine: "Spectrum Line"
        case .orbMeter: "Orb Meter"
        case .glyphStream: "Glyph Stream"
        }
    }
}

public enum CommitAnimationMode: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case glyphStream
    case beamSnap
    case cometCollapse
    case none

    public var displayName: String {
        switch self {
        case .glyphStream: "Glyph Stream"
        case .beamSnap: "Beam Snap"
        case .cometCollapse: "Comet Collapse"
        case .none: "None"
        }
    }
}

public enum EngineFrameSide: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case left
    case right

    public var displayName: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        }
    }
}

public struct ThemeColor: Codable, Equatable, Hashable, Sendable {
    public let hex: String

    public init(hex: String) {
        let normalized = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.hex = normalized.hasPrefix("#") ? normalized : "#\(normalized)"
    }
}

public struct OmniVoiceTheme: Codable, Equatable, Sendable, Identifiable {
    public let id: OmniVoiceThemeID
    public let name: String
    public let accentColor: ThemeColor
    public let secondaryAccentColor: ThemeColor
    public let surfaceTint: ThemeColor
    public let glassOpacity: Double
    public let captionOpacity: Double
    public let glowStrength: Double
    public let contrastMode: String
    public let waveformMode: WaveformMode
    public let commitAnimationMode: CommitAnimationMode
    public let engineFrameSide: EngineFrameSide
    public let motionIntensity: Double

    public init(
        id: OmniVoiceThemeID,
        name: String,
        accentColor: ThemeColor,
        secondaryAccentColor: ThemeColor,
        surfaceTint: ThemeColor,
        glassOpacity: Double,
        captionOpacity: Double,
        glowStrength: Double,
        contrastMode: String = "standard",
        waveformMode: WaveformMode = .bars,
        commitAnimationMode: CommitAnimationMode = .glyphStream,
        engineFrameSide: EngineFrameSide = .right,
        motionIntensity: Double = 0.78
    ) {
        self.id = id
        self.name = name
        self.accentColor = accentColor
        self.secondaryAccentColor = secondaryAccentColor
        self.surfaceTint = surfaceTint
        self.glassOpacity = glassOpacity
        self.captionOpacity = captionOpacity
        self.glowStrength = glowStrength
        self.contrastMode = contrastMode
        self.waveformMode = waveformMode
        self.commitAnimationMode = commitAnimationMode
        self.engineFrameSide = engineFrameSide
        self.motionIntensity = motionIntensity
    }

    public static var defaultTheme: OmniVoiceTheme {
        builtInTheme(id: .auroraBlue) ?? builtIn[0]
    }

    public static func builtInTheme(id: OmniVoiceThemeID) -> OmniVoiceTheme? {
        builtIn.first { $0.id == id }
    }

    public static func custom(accent: ThemeColor) -> OmniVoiceTheme {
        OmniVoiceTheme(
            id: .custom,
            name: "Custom",
            accentColor: accent,
            secondaryAccentColor: ThemeColor(hex: "#7DD3FC"),
            surfaceTint: ThemeColor(hex: "#06121C"),
            glassOpacity: 0.42,
            captionOpacity: 0.14,
            glowStrength: 0.34
        )
    }

    public var cssVariables: [String: String] {
        [
            "--ov-accent": accentColor.hex,
            "--ov-accent-secondary": secondaryAccentColor.hex,
            "--ov-bg": "#03070D",
            "--ov-surface": rgba(surfaceTint.hex, opacity: glassOpacity),
            "--ov-surface-strong": rgba(surfaceTint.hex, opacity: min(glassOpacity + 0.16, 0.86)),
            "--ov-text": contrastMode == "high" ? "#FFFFFF" : "#F5FAFF",
            "--ov-muted": contrastMode == "high" ? "#D9E7F2" : "#9FB2C6",
            "--ov-border": rgba(accentColor.hex, opacity: 0.26),
            "--ov-glow": rgba(accentColor.hex, opacity: glowStrength),
            "--ov-caption-bg": rgba(surfaceTint.hex, opacity: captionOpacity)
        ]
    }

    private func rgba(_ hex: String, opacity: Double) -> String {
        let components = Self.rgbComponents(hex: hex)
        return "rgba(\(components.r), \(components.g), \(components.b), \(String(format: "%.2f", opacity)))"
    }

    private static func rgbComponents(hex: String) -> (r: Int, g: Int, b: Int) {
        let cleaned = hex.replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else {
            return (56, 189, 248)
        }
        return ((value >> 16) & 255, (value >> 8) & 255, value & 255)
    }
}

public extension OmniVoiceTheme {
    static let builtIn: [OmniVoiceTheme] = [
        OmniVoiceTheme(id: .auroraBlue, name: "Aurora Blue", accentColor: ThemeColor(hex: "#38BDF8"), secondaryAccentColor: ThemeColor(hex: "#22D3EE"), surfaceTint: ThemeColor(hex: "#06121C"), glassOpacity: 0.46, captionOpacity: 0.14, glowStrength: 0.34),
        OmniVoiceTheme(id: .obsidianCyan, name: "Obsidian Cyan", accentColor: ThemeColor(hex: "#00E5FF"), secondaryAccentColor: ThemeColor(hex: "#A7F3D0"), surfaceTint: ThemeColor(hex: "#041011"), glassOpacity: 0.44, captionOpacity: 0.13, glowStrength: 0.36),
        OmniVoiceTheme(id: .deepSignal, name: "Deep Signal", accentColor: ThemeColor(hex: "#60A5FA"), secondaryAccentColor: ThemeColor(hex: "#34D399"), surfaceTint: ThemeColor(hex: "#071426"), glassOpacity: 0.48, captionOpacity: 0.15, glowStrength: 0.32),
        OmniVoiceTheme(id: .arcticGlass, name: "Arctic Glass", accentColor: ThemeColor(hex: "#BAE6FD"), secondaryAccentColor: ThemeColor(hex: "#67E8F9"), surfaceTint: ThemeColor(hex: "#101A22"), glassOpacity: 0.40, captionOpacity: 0.12, glowStrength: 0.24),
        OmniVoiceTheme(id: .cobaltPulse, name: "Cobalt Pulse", accentColor: ThemeColor(hex: "#2563EB"), secondaryAccentColor: ThemeColor(hex: "#06B6D4"), surfaceTint: ThemeColor(hex: "#071225"), glassOpacity: 0.50, captionOpacity: 0.16, glowStrength: 0.38),
        OmniVoiceTheme(id: .neonLime, name: "Neon Lime", accentColor: ThemeColor(hex: "#DFFF46"), secondaryAccentColor: ThemeColor(hex: "#5DF48A"), surfaceTint: ThemeColor(hex: "#0D1108"), glassOpacity: 0.46, captionOpacity: 0.13, glowStrength: 0.34),
        OmniVoiceTheme(id: .acidGlass, name: "Acid Glass", accentColor: ThemeColor(hex: "#B6FF3B"), secondaryAccentColor: ThemeColor(hex: "#40F99B"), surfaceTint: ThemeColor(hex: "#0B1008"), glassOpacity: 0.42, captionOpacity: 0.12, glowStrength: 0.36),
        OmniVoiceTheme(id: .emeraldVoice, name: "Emerald Voice", accentColor: ThemeColor(hex: "#10B981"), secondaryAccentColor: ThemeColor(hex: "#5EEAD4"), surfaceTint: ThemeColor(hex: "#04140F"), glassOpacity: 0.45, captionOpacity: 0.13, glowStrength: 0.30),
        OmniVoiceTheme(id: .matrixSoft, name: "Matrix Soft", accentColor: ThemeColor(hex: "#86EFAC"), secondaryAccentColor: ThemeColor(hex: "#22C55E"), surfaceTint: ThemeColor(hex: "#071007"), glassOpacity: 0.43, captionOpacity: 0.12, glowStrength: 0.24),
        OmniVoiceTheme(id: .prismBlue, name: "Prism Blue", accentColor: ThemeColor(hex: "#7DD3FC"), secondaryAccentColor: ThemeColor(hex: "#A78BFA"), surfaceTint: ThemeColor(hex: "#08121F"), glassOpacity: 0.46, captionOpacity: 0.14, glowStrength: 0.34),
        OmniVoiceTheme(id: .prismPink, name: "Prism Pink", accentColor: ThemeColor(hex: "#F472B6"), secondaryAccentColor: ThemeColor(hex: "#7DD3FC"), surfaceTint: ThemeColor(hex: "#180A14"), glassOpacity: 0.44, captionOpacity: 0.13, glowStrength: 0.32),
        OmniVoiceTheme(id: .violetBeam, name: "Violet Beam", accentColor: ThemeColor(hex: "#A78BFA"), secondaryAccentColor: ThemeColor(hex: "#22D3EE"), surfaceTint: ThemeColor(hex: "#100B1D"), glassOpacity: 0.45, captionOpacity: 0.14, glowStrength: 0.32),
        OmniVoiceTheme(id: .magentaGlass, name: "Magenta Glass", accentColor: ThemeColor(hex: "#E879F9"), secondaryAccentColor: ThemeColor(hex: "#38BDF8"), surfaceTint: ThemeColor(hex: "#17081C"), glassOpacity: 0.44, captionOpacity: 0.13, glowStrength: 0.32),
        OmniVoiceTheme(id: .emberWave, name: "Ember Wave", accentColor: ThemeColor(hex: "#FB7185"), secondaryAccentColor: ThemeColor(hex: "#FBBF24"), surfaceTint: ThemeColor(hex: "#1A0B0B"), glassOpacity: 0.43, captionOpacity: 0.13, glowStrength: 0.30),
        OmniVoiceTheme(id: .solarTrace, name: "Solar Trace", accentColor: ThemeColor(hex: "#FACC15"), secondaryAccentColor: ThemeColor(hex: "#38BDF8"), surfaceTint: ThemeColor(hex: "#151204"), glassOpacity: 0.42, captionOpacity: 0.12, glowStrength: 0.28),
        OmniVoiceTheme(id: .redline, name: "Redline", accentColor: ThemeColor(hex: "#EF4444"), secondaryAccentColor: ThemeColor(hex: "#F97316"), surfaceTint: ThemeColor(hex: "#170909"), glassOpacity: 0.45, captionOpacity: 0.13, glowStrength: 0.32),
        OmniVoiceTheme(id: .graphiteIce, name: "Graphite Ice", accentColor: ThemeColor(hex: "#CBD5E1"), secondaryAccentColor: ThemeColor(hex: "#38BDF8"), surfaceTint: ThemeColor(hex: "#111827"), glassOpacity: 0.42, captionOpacity: 0.13, glowStrength: 0.22),
        OmniVoiceTheme(id: .steelWhisper, name: "Steel Whisper", accentColor: ThemeColor(hex: "#94A3B8"), secondaryAccentColor: ThemeColor(hex: "#67E8F9"), surfaceTint: ThemeColor(hex: "#0F172A"), glassOpacity: 0.43, captionOpacity: 0.12, glowStrength: 0.22),
        OmniVoiceTheme(id: .monoGlass, name: "Mono Glass", accentColor: ThemeColor(hex: "#E5E7EB"), secondaryAccentColor: ThemeColor(hex: "#9CA3AF"), surfaceTint: ThemeColor(hex: "#111111"), glassOpacity: 0.40, captionOpacity: 0.12, glowStrength: 0.16),
        OmniVoiceTheme(id: .highContrast, name: "High Contrast", accentColor: ThemeColor(hex: "#FFFFFF"), secondaryAccentColor: ThemeColor(hex: "#00E5FF"), surfaceTint: ThemeColor(hex: "#000000"), glassOpacity: 0.70, captionOpacity: 0.28, glowStrength: 0.42, contrastMode: "high")
    ]
}
```

- [ ] **Step 4: Run tests and commit**

Run:

```bash
swift test --filter ThemeTests
```

Expected: PASS.

Commit:

```bash
git add Sources/OmniVoiceCore/Theme.swift Tests/OmniVoiceCoreTests/ThemeTests.swift
git commit -m "feat: add v2 theme model"
```

---

### Task 2: Theme Preferences And Migration

**Files:**
- Modify: `Sources/OmniVoiceCore/PreferencesStore.swift`
- Modify: `Tests/OmniVoiceCoreTests/PreferencesStoreTests.swift`

- [ ] **Step 1: Write failing preference tests**

Append these tests to `PreferencesStoreTests`:

```swift
func testDefaultsIncludeV2ThemeSettings() {
    let preferences = OmniVoicePreferences.defaults

    XCTAssertEqual(preferences.themeID, .auroraBlue)
    XCTAssertEqual(preferences.customAccentColor, ThemeColor(hex: "#38BDF8"))
    XCTAssertEqual(preferences.waveformMode, .bars)
    XCTAssertEqual(preferences.commitAnimationMode, .glyphStream)
    XCTAssertEqual(preferences.engineFrameSide, .right)
}

func testOldPreferencesDecodeWithThemeDefaults() throws {
    let json = """
    {
      "asr_provider": "parakeet-tdt",
      "style": "neutral",
      "dictionary_terms": [],
      "microphone_id": null,
      "dictation_hotkey": { "key_code": 49, "modifiers": 2304 },
      "style_hotkey": { "key_code": 1, "modifiers": 2304 }
    }
    """.data(using: .utf8)!

    let preferences = try EngineCoding.decoder.decode(OmniVoicePreferences.self, from: json)

    XCTAssertEqual(preferences.themeID, .auroraBlue)
    XCTAssertEqual(preferences.waveformMode, .bars)
    XCTAssertEqual(preferences.engineFrameSide, .right)
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
swift test --filter PreferencesStoreTests
```

Expected: FAIL because `OmniVoicePreferences` has no v2 theme fields and old JSON decoding cannot provide them.

- [ ] **Step 3: Add preference fields and custom decoding**

Modify `OmniVoicePreferences` in `Sources/OmniVoiceCore/PreferencesStore.swift`:

```swift
public struct OmniVoicePreferences: Codable, Equatable, Sendable {
    public var asrProvider: ASRProviderKind
    public var style: StyleProfile
    public var dictionaryTerms: [String]
    public var microphoneId: String?
    public var dictationHotkey: HotkeyBinding
    public var styleHotkey: HotkeyBinding
    public var themeID: OmniVoiceThemeID
    public var customAccentColor: ThemeColor
    public var waveformMode: WaveformMode
    public var commitAnimationMode: CommitAnimationMode
    public var engineFrameSide: EngineFrameSide

    enum CodingKeys: String, CodingKey {
        case asrProvider = "asr_provider"
        case style
        case dictionaryTerms = "dictionary_terms"
        case microphoneId = "microphone_id"
        case dictationHotkey = "dictation_hotkey"
        case styleHotkey = "style_hotkey"
        case themeID = "theme_id"
        case customAccentColor = "custom_accent_color"
        case waveformMode = "waveform_mode"
        case commitAnimationMode = "commit_animation_mode"
        case engineFrameSide = "engine_frame_side"
    }

    public var microphoneID: String? {
        get { microphoneId }
        set { microphoneId = newValue }
    }

    public static let defaults = OmniVoicePreferences(
        asrProvider: .parakeetTDT,
        style: .neutral,
        dictionaryTerms: [],
        microphoneID: nil,
        dictationHotkey: .defaultDictation,
        styleHotkey: .defaultStyle,
        themeID: .auroraBlue,
        customAccentColor: ThemeColor(hex: "#38BDF8"),
        waveformMode: .bars,
        commitAnimationMode: .glyphStream,
        engineFrameSide: .right
    )

    public init(
        asrProvider: ASRProviderKind,
        style: StyleProfile,
        dictionaryTerms: [String],
        microphoneID: String? = nil,
        dictationHotkey: HotkeyBinding = .defaultDictation,
        styleHotkey: HotkeyBinding = .defaultStyle,
        themeID: OmniVoiceThemeID = .auroraBlue,
        customAccentColor: ThemeColor = ThemeColor(hex: "#38BDF8"),
        waveformMode: WaveformMode = .bars,
        commitAnimationMode: CommitAnimationMode = .glyphStream,
        engineFrameSide: EngineFrameSide = .right
    ) {
        self.asrProvider = asrProvider
        self.style = style
        self.dictionaryTerms = dictionaryTerms
        self.microphoneId = microphoneID
        self.dictationHotkey = dictationHotkey
        self.styleHotkey = styleHotkey
        self.themeID = themeID
        self.customAccentColor = customAccentColor
        self.waveformMode = waveformMode
        self.commitAnimationMode = commitAnimationMode
        self.engineFrameSide = engineFrameSide
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.defaults
        self.asrProvider = try container.decodeIfPresent(ASRProviderKind.self, forKey: .asrProvider) ?? defaults.asrProvider
        self.style = try container.decodeIfPresent(StyleProfile.self, forKey: .style) ?? defaults.style
        self.dictionaryTerms = try container.decodeIfPresent([String].self, forKey: .dictionaryTerms) ?? defaults.dictionaryTerms
        self.microphoneId = try container.decodeIfPresent(String.self, forKey: .microphoneId)
        self.dictationHotkey = try container.decodeIfPresent(HotkeyBinding.self, forKey: .dictationHotkey) ?? defaults.dictationHotkey
        self.styleHotkey = try container.decodeIfPresent(HotkeyBinding.self, forKey: .styleHotkey) ?? defaults.styleHotkey
        self.themeID = try container.decodeIfPresent(OmniVoiceThemeID.self, forKey: .themeID) ?? defaults.themeID
        self.customAccentColor = try container.decodeIfPresent(ThemeColor.self, forKey: .customAccentColor) ?? defaults.customAccentColor
        self.waveformMode = try container.decodeIfPresent(WaveformMode.self, forKey: .waveformMode) ?? defaults.waveformMode
        self.commitAnimationMode = try container.decodeIfPresent(CommitAnimationMode.self, forKey: .commitAnimationMode) ?? defaults.commitAnimationMode
        self.engineFrameSide = try container.decodeIfPresent(EngineFrameSide.self, forKey: .engineFrameSide) ?? defaults.engineFrameSide
    }
}
```

Keep existing `cycleStyle()` and `cycleASRProvider()` methods below the new initializer.

- [ ] **Step 4: Update existing round-trip test construction**

In `testPreferencesRoundTripThroughStore`, add explicit non-default theme fields:

```swift
themeID: .neonLime,
customAccentColor: ThemeColor(hex: "#00A3FF"),
waveformMode: .glyphStream,
commitAnimationMode: .beamSnap,
engineFrameSide: .left
```

- [ ] **Step 5: Run tests and commit**

Run:

```bash
swift test --filter PreferencesStoreTests
```

Expected: PASS.

Commit:

```bash
git add Sources/OmniVoiceCore/PreferencesStore.swift Tests/OmniVoiceCoreTests/PreferencesStoreTests.swift
git commit -m "feat: persist v2 theme preferences"
```

---

### Task 3: Native Theme Rendering Adapter

**Files:**
- Create: `Sources/OmniVoiceApp/ThemeRendering.swift`
- Modify: `Sources/OmniVoiceApp/AppModel.swift`

- [ ] **Step 1: Add active theme API to `AppModel`**

Add computed properties and setters to `AppModel`:

```swift
var activeTheme: OmniVoiceTheme {
    if preferences.themeID == .custom {
        var theme = OmniVoiceTheme.custom(accent: preferences.customAccentColor)
        theme = theme.withModes(
            waveformMode: preferences.waveformMode,
            commitAnimationMode: preferences.commitAnimationMode,
            engineFrameSide: preferences.engineFrameSide
        )
        return theme
    }

    var theme = OmniVoiceTheme.builtInTheme(id: preferences.themeID) ?? .defaultTheme
    theme = theme.withModes(
        waveformMode: preferences.waveformMode,
        commitAnimationMode: preferences.commitAnimationMode,
        engineFrameSide: preferences.engineFrameSide
    )
    return theme
}

func setThemeID(_ themeID: OmniVoiceThemeID) {
    preferences.themeID = themeID
    persistPreferences()
    statusText = "Theme: \(activeTheme.name)"
}

func setCustomAccentColor(_ color: ThemeColor) {
    preferences.customAccentColor = color
    preferences.themeID = .custom
    persistPreferences()
    statusText = "Custom accent: \(color.hex)"
}

func setWaveformMode(_ mode: WaveformMode) {
    preferences.waveformMode = mode
    persistPreferences()
    statusText = "Waveform: \(mode.displayName)"
}

func setCommitAnimationMode(_ mode: CommitAnimationMode) {
    preferences.commitAnimationMode = mode
    persistPreferences()
    statusText = "Animation: \(mode.displayName)"
}

func setEngineFrameSide(_ side: EngineFrameSide) {
    preferences.engineFrameSide = side
    persistPreferences()
    statusText = "Engine frame: \(side.displayName)"
}
```

Add this helper to `Theme.swift`:

```swift
public extension OmniVoiceTheme {
    func withModes(
        waveformMode: WaveformMode,
        commitAnimationMode: CommitAnimationMode,
        engineFrameSide: EngineFrameSide
    ) -> OmniVoiceTheme {
        OmniVoiceTheme(
            id: id,
            name: name,
            accentColor: accentColor,
            secondaryAccentColor: secondaryAccentColor,
            surfaceTint: surfaceTint,
            glassOpacity: glassOpacity,
            captionOpacity: captionOpacity,
            glowStrength: glowStrength,
            contrastMode: contrastMode,
            waveformMode: waveformMode,
            commitAnimationMode: commitAnimationMode,
            engineFrameSide: engineFrameSide,
            motionIntensity: motionIntensity
        )
    }
}
```

- [ ] **Step 2: Create SwiftUI rendering helpers**

Create `Sources/OmniVoiceApp/ThemeRendering.swift`:

```swift
import SwiftUI
import OmniVoiceCore

extension Color {
    init(themeColor: ThemeColor) {
        let hex = themeColor.hex.replacingOccurrences(of: "#", with: "")
        let value = Int(hex, radix: 16) ?? 0x38BDF8
        self.init(
            red: Double((value >> 16) & 255) / 255.0,
            green: Double((value >> 8) & 255) / 255.0,
            blue: Double(value & 255) / 255.0
        )
    }
}

struct ThemeSurface: ViewModifier {
    let theme: OmniVoiceTheme
    let cornerRadius: CGFloat
    let strong: Bool

    func body(content: Content) -> some View {
        let accent = Color(themeColor: theme.accentColor)
        let tint = Color(themeColor: theme.surfaceTint)
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(tint.opacity(strong ? theme.glassOpacity + 0.12 : theme.glassOpacity))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(accent.opacity(strong ? 0.34 : 0.22), lineWidth: 1)
            }
            .shadow(color: accent.opacity(theme.glowStrength * 0.55), radius: strong ? 24 : 14, y: strong ? 10 : 6)
    }
}

extension View {
    func themeSurface(_ theme: OmniVoiceTheme, cornerRadius: CGFloat = 8, strong: Bool = false) -> some View {
        modifier(ThemeSurface(theme: theme, cornerRadius: cornerRadius, strong: strong))
    }
}
```

- [ ] **Step 3: Build and commit**

Run:

```bash
swift test
```

Expected: PASS.

Commit:

```bash
git add Sources/OmniVoiceCore/Theme.swift Sources/OmniVoiceApp/AppModel.swift Sources/OmniVoiceApp/ThemeRendering.swift
git commit -m "feat: add native theme rendering adapter"
```

---

### Task 4: Themed Caption, Hotkey Recorder, And Menu Bar

**Files:**
- Modify: `Sources/OmniVoiceApp/CaptionOverlayView.swift`
- Modify: `Sources/OmniVoiceApp/CaptionOverlayWindow.swift`
- Modify: `Sources/OmniVoiceApp/HotkeyRecorderView.swift`
- Modify: `Sources/OmniVoiceApp/MenuBarControlsView.swift`
- Modify: `Sources/OmniVoiceApp/OmniVoiceApp.swift`

- [ ] **Step 1: Update caption view inputs**

Change `CaptionOverlayView` initializer properties to:

```swift
let text: String
let styleName: String
let level: Float
let theme: OmniVoiceTheme
```

Update the caption body to use the theme:

```swift
let accent = Color(themeColor: theme.accentColor)
let secondary = Color(themeColor: theme.secondaryAccentColor)

Text(text.isEmpty ? "Listening..." : text)
    .font(.system(size: 14, weight: .medium))
    .foregroundStyle(.white.opacity(0.88))
    .lineLimit(3)
    .multilineTextAlignment(.center)
    .padding(.horizontal, 14)
    .padding(.vertical, 7)
    .themeSurface(theme, cornerRadius: 8, strong: false)

WaveformPreview(mode: theme.waveformMode, level: level, accent: accent, secondary: secondary)
    .frame(height: 22)
```

Add this private `WaveformPreview` view in the same file:

```swift
private struct WaveformPreview: View {
    let mode: WaveformMode
    let level: Float
    let accent: Color
    let secondary: Color

    var body: some View {
        switch mode {
        case .bars:
            HStack(spacing: 3) {
                ForEach(0..<14, id: \.self) { index in
                    Capsule()
                        .fill(index < activeBars ? accent.opacity(0.82) : Color.white.opacity(0.10))
                        .frame(width: 4, height: CGFloat(5 + (index % 5) * 3))
                }
            }
        case .pulseRing:
            ZStack {
                Circle().stroke(accent.opacity(0.22), lineWidth: 2)
                Circle()
                    .stroke(secondary.opacity(0.72), lineWidth: 2)
                    .scaleEffect(0.52 + CGFloat(normalizedLevel) * 0.40)
            }
            .frame(width: 22, height: 22)
        case .spectrumLine:
            HStack(spacing: 2) {
                ForEach(0..<22, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index.isMultiple(of: 2) ? accent.opacity(0.78) : secondary.opacity(0.56))
                        .frame(width: 3, height: CGFloat(4 + ((index * 7) % 14)))
                }
            }
        case .orbMeter:
            Circle()
                .fill(
                    RadialGradient(
                        colors: [accent.opacity(0.82), secondary.opacity(0.22), .clear],
                        center: .center,
                        startRadius: 1,
                        endRadius: 16
                    )
                )
                .frame(width: 18 + CGFloat(normalizedLevel) * 12, height: 18 + CGFloat(normalizedLevel) * 12)
        case .glyphStream:
            HStack(spacing: 5) {
                ForEach(["O", "m", "n", "i", "Voice"], id: \.self) { glyph in
                    Text(glyph)
                        .font(.system(size: glyph == "Voice" ? 10 : 12, weight: .bold, design: .rounded))
                        .foregroundStyle(glyph == "Voice" ? secondary.opacity(0.74) : accent.opacity(0.86))
                }
            }
        }
    }

    private var normalizedLevel: Double {
        min(max(Double(level) * 45, 0), 1)
    }

    private var activeBars: Int {
        Int((normalizedLevel * 14).rounded(.up))
    }
}
```

- [ ] **Step 2: Pass theme through the overlay window**

Change `CaptionOverlayWindow.show` signature:

```swift
func show(text: String, styleName: String, level: Float = 0, theme: OmniVoiceTheme)
```

Create the hosting view with:

```swift
let content = DraggableCaptionHostingView(
    rootView: CaptionOverlayView(text: text, styleName: styleName, level: level, theme: theme)
)
```

- [ ] **Step 3: Update app overlay calls**

In every `appDelegate.showOverlay` call in `OmniVoiceApp.swift`, pass:

```swift
theme: model.activeTheme
```

- [ ] **Step 4: Theme the hotkey recorder**

Add `theme: OmniVoiceTheme` to `HotkeyRecorderView`. Wrap the recorder display `HStack` with:

```swift
.padding(.horizontal, 8)
.padding(.vertical, 6)
.themeSurface(theme, cornerRadius: 8)
```

Update both `HotkeyRecorderView` call sites in `SettingsView` to pass `model.activeTheme`.

- [ ] **Step 5: Theme the menu bar controls**

In `MenuBarControlsView`, add a theme swatch row below the status:

```swift
HStack(spacing: 8) {
    Circle()
        .fill(Color(themeColor: model.activeTheme.accentColor))
        .frame(width: 10, height: 10)
    Text("Theme: \(model.activeTheme.name)")
        .lineLimit(1)
}
```

- [ ] **Step 6: Build and commit**

Run:

```bash
swift build
```

Expected: build succeeds.

Commit:

```bash
git add Sources/OmniVoiceApp/CaptionOverlayView.swift Sources/OmniVoiceApp/CaptionOverlayWindow.swift Sources/OmniVoiceApp/HotkeyRecorderView.swift Sources/OmniVoiceApp/MenuBarControlsView.swift Sources/OmniVoiceApp/OmniVoiceApp.swift
git commit -m "feat: theme caption and hotkey surfaces"
```

---

### Task 5: Theme Settings UI

**Files:**
- Modify: `Sources/OmniVoiceApp/SettingsView.swift`

- [ ] **Step 1: Add bindings**

Add these computed bindings:

```swift
private var themeIDBinding: Binding<OmniVoiceThemeID> {
    Binding(
        get: { model.preferences.themeID },
        set: { model.setThemeID($0) }
    )
}

private var waveformModeBinding: Binding<WaveformMode> {
    Binding(
        get: { model.preferences.waveformMode },
        set: { model.setWaveformMode($0) }
    )
}

private var commitAnimationModeBinding: Binding<CommitAnimationMode> {
    Binding(
        get: { model.preferences.commitAnimationMode },
        set: { model.setCommitAnimationMode($0) }
    )
}

private var engineFrameSideBinding: Binding<EngineFrameSide> {
    Binding(
        get: { model.preferences.engineFrameSide },
        set: { model.setEngineFrameSide($0) }
    )
}
```

- [ ] **Step 2: Add settings sections after Status**

Add:

```swift
Section("Appearance") {
    Picker("Theme", selection: themeIDBinding) {
        ForEach(OmniVoiceTheme.builtIn, id: \.id) { theme in
            Text(theme.name).tag(theme.id)
        }
        Text("Custom").tag(OmniVoiceThemeID.custom)
    }

    ColorPicker(
        "Custom Accent",
        selection: Binding(
            get: { Color(themeColor: model.preferences.customAccentColor) },
            set: { model.setCustomAccentColor(ThemeColor(color: $0)) }
        )
    )

    ThemePreview(theme: model.activeTheme)
}

Section("Waveform And Motion") {
    Picker("Waveform", selection: waveformModeBinding) {
        ForEach(WaveformMode.allCases, id: \.self) { mode in
            Text(mode.displayName).tag(mode)
        }
    }

    Picker("Commit Animation", selection: commitAnimationModeBinding) {
        ForEach(CommitAnimationMode.allCases, id: \.self) { mode in
            Text(mode.displayName).tag(mode)
        }
    }
}

Section("Engine Frame") {
    Picker("Frame Side", selection: engineFrameSideBinding) {
        ForEach(EngineFrameSide.allCases, id: \.self) { side in
            Text(side.displayName).tag(side)
        }
    }
}
```

Add `ThemePreview` as a private view in `SettingsView.swift`:

```swift
private struct ThemePreview: View {
    let theme: OmniVoiceTheme

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(themeColor: theme.accentColor))
                .frame(width: 22, height: 22)
                .shadow(color: Color(themeColor: theme.accentColor).opacity(theme.glowStrength), radius: 10)

            VStack(alignment: .leading, spacing: 3) {
                Text(theme.name)
                    .font(.headline)
                Text("\(theme.waveformMode.displayName) / \(theme.commitAnimationMode.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .themeSurface(theme, cornerRadius: 8, strong: true)
    }
}
```

Add a `ThemeColor.init(color:)` helper in `ThemeRendering.swift`:

```swift
import AppKit

extension ThemeColor {
    init(color: Color) {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? .systemBlue
        let red = Int((nsColor.redComponent * 255).rounded())
        let green = Int((nsColor.greenComponent * 255).rounded())
        let blue = Int((nsColor.blueComponent * 255).rounded())
        self.init(hex: String(format: "#%02X%02X%02X", red, green, blue))
    }
}
```

- [ ] **Step 3: Build and commit**

Run:

```bash
swift build
```

Expected: build succeeds.

Commit:

```bash
git add Sources/OmniVoiceApp/SettingsView.swift Sources/OmniVoiceApp/ThemeRendering.swift
git commit -m "feat: add theme settings controls"
```

---

### Task 6: Engine Dashboard Theme Endpoint And CSS Variables

**Files:**
- Modify: `engine/omnivoice_engine/schemas.py`
- Modify: `engine/omnivoice_engine/main.py`
- Modify: `engine/tests/test_api.py`
- Modify: `engine/omnivoice_engine/static/dashboard.css`
- Modify: `engine/omnivoice_engine/static/dashboard.js`

- [ ] **Step 1: Write failing API test**

Add to `engine/tests/test_api.py`:

```python
def test_default_theme_endpoint_returns_css_variables():
    response = client.get("/api/theme/default")

    assert response.status_code == 200
    payload = response.json()
    assert payload["id"] == "auroraBlue"
    assert payload["name"] == "Aurora Blue"
    assert payload["css_variables"]["--ov-accent"] == "#38BDF8"
    assert "--ov-caption-bg" in payload["css_variables"]
```

- [ ] **Step 2: Run the API test and verify failure**

Run:

```bash
cd engine
pytest tests/test_api.py::test_default_theme_endpoint_returns_css_variables -q
```

Expected: FAIL with 404.

- [ ] **Step 3: Add schema and endpoint**

Add to `schemas.py`:

```python
class ThemePayload(BaseModel):
    id: str
    name: str
    css_variables: dict[str, str]
```

Import `ThemePayload` in `main.py` and add:

```python
DEFAULT_THEME_CSS_VARIABLES = {
    "--ov-accent": "#38BDF8",
    "--ov-accent-secondary": "#22D3EE",
    "--ov-bg": "#03070D",
    "--ov-surface": "rgba(6, 18, 28, 0.46)",
    "--ov-surface-strong": "rgba(6, 18, 28, 0.62)",
    "--ov-text": "#F5FAFF",
    "--ov-muted": "#9FB2C6",
    "--ov-border": "rgba(56, 189, 248, 0.26)",
    "--ov-glow": "rgba(56, 189, 248, 0.34)",
    "--ov-caption-bg": "rgba(6, 18, 28, 0.14)",
}


@app.get("/api/theme/default", response_model=ThemePayload)
def default_theme() -> ThemePayload:
    return ThemePayload(
        id="auroraBlue",
        name="Aurora Blue",
        css_variables=DEFAULT_THEME_CSS_VARIABLES,
    )
```

- [ ] **Step 4: Update CSS variable names**

In `dashboard.css`, keep existing layout but replace hardcoded local variables with `--ov-*` names:

```css
:root {
  color-scheme: dark;
  --ov-accent: #38BDF8;
  --ov-accent-secondary: #22D3EE;
  --ov-bg: #03070D;
  --ov-surface: rgba(6, 18, 28, 0.46);
  --ov-surface-strong: rgba(6, 18, 28, 0.62);
  --ov-text: #F5FAFF;
  --ov-muted: #9FB2C6;
  --ov-border: rgba(56, 189, 248, 0.26);
  --ov-glow: rgba(56, 189, 248, 0.34);
  --ov-caption-bg: rgba(6, 18, 28, 0.14);
  --good: #5df48a;
  --warn: #ffd95a;
  --bad: #ff6f6f;
  --info: #65ddff;
  --shadow: rgba(0, 0, 0, 0.58);
}
```

Then replace `var(--bg)` with `var(--ov-bg)`, `var(--panel)` with `var(--ov-surface)`, `var(--panel-strong)` with `var(--ov-surface-strong)`, `var(--text)` with `var(--ov-text)`, `var(--muted)` with `var(--ov-muted)`, `var(--line-soft)` with `var(--ov-border)`, and `var(--accent)` with `var(--ov-accent)`.

- [ ] **Step 5: Add JS theme application**

At the top of `dashboard.js`, add:

```javascript
window.omniVoiceApplyTheme = function omniVoiceApplyTheme(payload) {
  if (!payload || !payload.css_variables) return;
  for (const [name, value] of Object.entries(payload.css_variables)) {
    document.documentElement.style.setProperty(name, value);
  }
};
```

In `refresh()`, before loading status, call:

```javascript
await loadTheme();
```

Add:

```javascript
async function loadTheme() {
  if (window.__OMNIVOICE_THEME__) {
    window.omniVoiceApplyTheme(window.__OMNIVOICE_THEME__);
    return;
  }
  const theme = await fetchJson("/api/theme/default");
  window.omniVoiceApplyTheme(theme);
}
```

- [ ] **Step 6: Test and commit**

Run:

```bash
cd engine
pytest tests/test_api.py::test_default_theme_endpoint_returns_css_variables -q
```

Expected: PASS.

Commit:

```bash
git add engine/omnivoice_engine/schemas.py engine/omnivoice_engine/main.py engine/tests/test_api.py engine/omnivoice_engine/static/dashboard.css engine/omnivoice_engine/static/dashboard.js
git commit -m "feat: theme engine dashboard"
```

---

### Task 7: Embedded Engine Frame

**Files:**
- Create: `Sources/OmniVoiceApp/EngineFrameView.swift`
- Modify: `Sources/OmniVoiceApp/OmniVoiceApp.swift`
- Modify: `Sources/OmniVoiceApp/SettingsView.swift`

- [ ] **Step 1: Create WebKit wrapper**

Create `Sources/OmniVoiceApp/EngineFrameView.swift`:

```swift
import SwiftUI
import WebKit
import OmniVoiceCore

struct EngineFrameView: View {
    let theme: OmniVoiceTheme
    let side: EngineFrameSide
    @State private var isExpanded = false

    var body: some View {
        HStack(spacing: 0) {
            if side == .left {
                frameContent
                collapseHandle
            } else {
                collapseHandle
                frameContent
            }
        }
        .frame(width: isExpanded ? 430 : 38)
        .animation(.snappy(duration: 0.18), value: isExpanded)
    }

    private var collapseHandle: some View {
        Button {
            isExpanded.toggle()
        } label: {
            Image(systemName: isExpanded ? "sidebar.trailing" : "sidebar.leading")
        }
        .buttonStyle(.plain)
        .frame(width: 38, maxHeight: .infinity)
        .themeSurface(theme, cornerRadius: 8, strong: true)
        .help(isExpanded ? "Hide engine dashboard" : "Show engine dashboard")
    }

    @ViewBuilder
    private var frameContent: some View {
        if isExpanded {
            EngineDashboardWebView(theme: theme)
                .frame(width: 392)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .themeSurface(theme, cornerRadius: 8, strong: true)
        }
    }
}

struct EngineDashboardWebView: NSViewRepresentable {
    let theme: OmniVoiceTheme

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.load(URLRequest(url: URL(string: "http://127.0.0.1:8765/")!))
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        let payload = themePayloadJSON(theme)
        nsView.evaluateJavaScript("window.__OMNIVOICE_THEME__ = \(payload); window.omniVoiceApplyTheme && window.omniVoiceApplyTheme(window.__OMNIVOICE_THEME__);")
    }

    private func themePayloadJSON(_ theme: OmniVoiceTheme) -> String {
        let payload: [String: Any] = [
            "id": theme.id.rawValue,
            "name": theme.name,
            "css_variables": theme.cssVariables
        ]
        let data = try? JSONSerialization.data(withJSONObject: payload, options: [])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}
```

- [ ] **Step 2: Compose settings and engine frame**

In `OmniVoiceApp.swift`, add these helper views inside `OmniVoiceApp`:

```swift
private var controlPanelContent: some View {
    HStack(spacing: 12) {
        if model.preferences.engineFrameSide == .left {
            EngineFrameView(theme: model.activeTheme, side: model.preferences.engineFrameSide)
        }

        settingsContent

        if model.preferences.engineFrameSide == .right {
            EngineFrameView(theme: model.activeTheme, side: model.preferences.engineFrameSide)
        }
    }
    .padding(12)
    .background(Color(themeColor: model.activeTheme.surfaceTint).opacity(0.72))
}

private var settingsContent: some View {
    SettingsView(
        model: model,
        showTestCaption: {
            appDelegate.showOverlay(
                text: model.lastTestResult == "No test run yet" ? "OmniVoice is running" : model.lastTestResult,
                styleName: model.preferences.style.displayName,
                theme: model.activeTheme
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                appDelegate.hideOverlay()
            }
        },
        requestAccessibilityPermission: {
            appDelegate.requestAccessibilityPermission()
        },
        refreshPermissions: {
            appDelegate.refreshPermissionStatus()
        }
    )
    .task {
        appDelegate.attach(model: model)
        await model.refreshEngineStatus()
    }
}
```

Use `controlPanelContent` in the main `WindowGroup`. Keep the `Settings` scene on `settingsContent` without the embedded frame.

- [ ] **Step 3: Build and commit**

Run:

```bash
swift build
```

Expected: build succeeds.

Commit:

```bash
git add Sources/OmniVoiceApp/EngineFrameView.swift Sources/OmniVoiceApp/OmniVoiceApp.swift Sources/OmniVoiceApp/SettingsView.swift
git commit -m "feat: embed themed engine frame"
```

---

### Task 8: Final Verification

**Files:**
- No planned edits unless verification finds a real issue.

- [ ] **Step 1: Run Swift tests**

Run:

```bash
swift test
```

Expected: all Swift tests pass.

- [ ] **Step 2: Run engine tests**

Run:

```bash
cd engine
pytest
```

Expected: all Python tests pass.

- [ ] **Step 3: Run dashboard smoke check**

Run:

```bash
./scripts/run-engine.sh
```

Expected: engine starts on `http://127.0.0.1:8765/`.

Open the dashboard in the in-app browser and verify:

- health pill renders
- dashboard uses blue/cyan theme variables
- transcripts panel remains readable
- model download buttons still render
- `Start Desktop App` button still renders

- [ ] **Step 4: Run app smoke check**

Run:

```bash
swift run OmniVoiceApp
```

Expected:

- app launches as a menu-bar app
- settings window opens
- default Aurora Blue theme renders
- switching theme updates settings preview
- Show Caption uses selected theme
- changing waveform mode changes caption preview
- engine frame expands and collapses on selected side
- standalone engine dashboard remains usable in the browser

- [ ] **Step 5: Handle verification fixes**

If verification required edits, run:

```bash
git status --short
```

Stage only the files changed by the verification fix, then commit:

```bash
git commit -m "fix: stabilize v2 theme foundation"
```

If verification required no edits, leave the branch without an extra commit.

---

## Self-Review

Spec coverage:

- Theme/glass system: covered by Tasks 1, 3, 4, and 5.
- 20 built-in themes: covered by Task 1.
- Custom accent color: covered by Tasks 1, 2, and 5.
- Caption and hotkey theme support: covered by Task 4.
- Waveform/VU modes: covered by Tasks 1, 2, 4, and 5.
- Engine frame side selection: covered by Tasks 2, 5, and 7.
- Engine web theme bridge: covered by Tasks 6 and 7.
- Live translation, AI handoff, conversation transcription, and live typed streaming: intentionally out of scope for this first implementation slice.

Placeholder scan:

- This plan uses concrete file paths, commands, expected results, type names, endpoint names, and code snippets.
- No step depends on a hidden future decision.

Execution recommendation:

- Use subagent-driven development with one worker per task where write sets do not overlap.
- Keep Task 1 and Task 2 sequential because preferences depend on the theme model.
- Task 6 can run in parallel with Task 3 after Task 1 lands because the engine CSS endpoint does not touch Swift files.
