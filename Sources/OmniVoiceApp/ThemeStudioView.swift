import AppKit
import SwiftUI
import OmniVoiceCore

struct ThemeStudioView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredLook: ThemeLook?
    @State private var browsedLook: ThemeLook?
    @State private var dwellApplyTask: Task<Void, Never>?
    @State private var dwellProgress: CGFloat = 0

    var body: some View {
        let activeTheme = model.activeTheme
        let looks = OmniVoiceTheme.signatureLooks
        let currentLook = browsedLook ?? activeTheme.look
        let previewLook = hoveredLook ?? currentLook
        let displayedIndex = looks.firstIndex(where: { $0.look == currentLook }) ?? 0
        let isPendingApply = browsedLook != nil && browsedLook != activeTheme.look
        let activeAccent = Color(themeColor: activeTheme.resolvedPalette(for: colorScheme).accentText)

        VStack(alignment: .leading, spacing: 14) {
            studioHeaderCard(theme: activeTheme)

            OmniGlassCard(theme: activeTheme, cornerRadius: 14, strong: false, padding: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Label("Signature Looks", systemImage: "paintpalette.fill")
                            .font(.subheadline.weight(.semibold))
                            .fontDesign(activeTheme.look.headerFontDesign)

                        Text("· \(previewLook.tagline)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 6)

                        if isPendingApply {
                            HStack(spacing: 5) {
                                GeometryReader { geo in
                                    Capsule(style: .continuous)
                                        .fill(activeAccent.opacity(0.22))
                                        .overlay(alignment: .leading) {
                                            Capsule(style: .continuous)
                                                .fill(activeAccent)
                                                .frame(width: max(4, geo.size.width * dwellProgress))
                                        }
                                }
                                .frame(width: 34, height: 4)

                                Text("Applying…")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(activeAccent)
                            }
                        }

                        Text("\(displayedIndex + 1) / \(looks.count)")
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    SignatureLookRolodex(
                        looks: looks,
                        activeTheme: activeTheme,
                        appliedLook: activeTheme.look,
                        focusedIndex: displayedIndex,
                        onBrowseLook: { look in
                            scheduleDwellApply(for: look)
                        },
                        onCommitLookNow: { look in
                            commitLookImmediately(look)
                        },
                        onHoverLook: { look in
                            hoveredLook = look
                        }
                    )
                }
            }
            .onChange(of: activeTheme.look) { _, newLook in
                // Keep Rolodex in sync if changed via the Visual Look or Palette picker below
                if browsedLook == nil || browsedLook == newLook {
                    dwellApplyTask?.cancel()
                    dwellApplyTask = nil
                    browsedLook = nil
                    dwellProgress = 0
                }
            }
            .onDisappear {
                dwellApplyTask?.cancel()
                dwellApplyTask = nil
            }

            customizeLookCard(theme: activeTheme)
        }
    }

    private func scheduleDwellApply(for look: ThemeLook) {
        dwellApplyTask?.cancel()
        dwellApplyTask = nil

        if look == model.activeTheme.look {
            browsedLook = nil
            dwellProgress = 0
            return
        }

        browsedLook = look
        var resetTx = Transaction()
        resetTx.disablesAnimations = true
        withTransaction(resetTx) {
            dwellProgress = 0
        }
        withAnimation(.linear(duration: 1.0)) {
            dwellProgress = 1.0
        }

        dwellApplyTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(1.0))
            } catch {
                return
            }
            guard !Task.isCancelled, browsedLook == look else { return }
            browsedLook = nil
            dwellProgress = 0
            model.applySignatureLook(look)
        }
    }

    private func commitLookImmediately(_ look: ThemeLook) {
        dwellApplyTask?.cancel()
        dwellApplyTask = nil
        browsedLook = nil
        dwellProgress = 0
        if model.activeTheme.look != look {
            model.applySignatureLook(look)
        }
    }

    @ViewBuilder
    private func studioHeaderCard(theme: OmniVoiceTheme) -> some View {
        let accent = Color(themeColor: theme.resolvedPalette(for: colorScheme).accentText)

        OmniGlassCard(theme: theme, cornerRadius: 14, strong: true, padding: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        OmniStatusPill(
                            title: theme.look.displayName,
                            tint: accent,
                            systemImage: "sparkles",
                            theme: theme
                        )

                        Text(theme.name)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Text(theme.look.tagline)
                        .font(.callout)
                        .foregroundStyle(.primary)
                }

                Spacer()

                if model.preferences.themeLookOverride != nil {
                    Button("Auto Look") {
                        model.setThemeLookOverride(nil)
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    private func customizeLookCard(theme: OmniVoiceTheme) -> some View {
        OmniGlassCard(theme: theme, cornerRadius: 14, strong: false, padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Customize Look & Palette", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .fontDesign(theme.look.headerFontDesign)

                HStack {
                    Text("Appearance")
                        .font(.callout)
                    Spacer()
                    Picker("Appearance", selection: Binding(
                        get: { model.preferences.appearanceMode },
                        set: { model.setAppearanceMode($0) }
                    )) {
                        ForEach(AppAppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 240)
                }

                Divider().opacity(0.35)

                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Visual Look")
                            .font(.callout)
                        Text("Mix any structural look with any of the \(OmniVoiceTheme.builtIn.count) color palettes.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Visual Look", selection: Binding<ThemeLook?>(
                        get: { model.preferences.themeLookOverride },
                        set: { model.setThemeLookOverride($0) }
                    )) {
                        Text("Auto (From Palette)").tag(ThemeLook?.none)
                        ForEach(ThemeLook.allCases, id: \.self) { look in
                            Text(look.displayName).tag(Optional(look))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }

                Divider().opacity(0.35)

                HStack(spacing: 12) {
                    Text("Color Palette")
                        .font(.callout)
                    Spacer()
                    Picker("Color Palette", selection: Binding(
                        get: { model.preferences.themeID },
                        set: { model.setThemeID($0) }
                    )) {
                        ForEach(OmniVoiceTheme.builtIn, id: \.id) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                        Text("Custom").tag(OmniVoiceThemeID.custom)
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)

                    ColorPicker(
                        "Custom Accent",
                        selection: Binding(
                            get: { Color(themeColor: model.preferences.customAccentColor) },
                            set: { model.setCustomAccentColor(ThemeColor(color: $0)) }
                        )
                    )
                    .labelsHidden()
                    .help("Pick a custom accent color")
                }

                Divider().opacity(0.35)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Waveform Style")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Waveform", selection: Binding(
                            get: { model.preferences.waveformMode },
                            set: { model.setWaveformMode($0) }
                        )) {
                            ForEach(WaveformMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Commit Trail")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Commit Trail", selection: Binding(
                            get: { model.preferences.commitAnimationMode },
                            set: { model.setCommitAnimationMode($0) }
                        )) {
                            ForEach(CommitAnimationMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Drawer Side")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Drawer Side", selection: Binding(
                            get: { model.preferences.engineFrameSide },
                            set: { model.setEngineFrameSide($0) }
                        )) {
                            ForEach(EngineFrameSide.allCases, id: \.self) { side in
                                Text(side.displayName).tag(side)
                            }
                        }
                        .labelsHidden()
                    }
                }

                Divider().opacity(0.35)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Listening HUD Glass Opacity")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text(model.preferences.captionGlassOpacity <= 0.10
                             ? "Crystal Clear (\(Int((model.preferences.captionGlassOpacity * 100).rounded()))%)"
                             : "\(Int((model.preferences.captionGlassOpacity * 100).rounded()))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
                        Text("Clear")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Slider(
                            value: Binding(
                                get: { model.preferences.captionGlassOpacity },
                                set: { model.setCaptionGlassOpacity($0) }
                            ),
                            in: 0...1
                        )
                        Text("Frosted")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct SignatureLookRolodex: View {
    let looks: [OmniVoiceTheme]
    let activeTheme: OmniVoiceTheme
    let appliedLook: ThemeLook
    let focusedIndex: Int
    let onBrowseLook: (ThemeLook) -> Void
    let onCommitLookNow: (ThemeLook) -> Void
    let onHoverLook: (ThemeLook?) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var wheelPosition: Double = 0
    @State private var dragBasePosition: Double?
    @State private var didInitializeWheel = false
    @State private var snapTask: Task<Void, Never>?

    var body: some View {
        let activeAccent = Color(themeColor: activeTheme.resolvedPalette(for: colorScheme).accentText)
        let count = max(looks.count, 1)
        let currentIndex = normalizedIndex(Int(wheelPosition.rounded()), count: count)

        VStack(spacing: 8) {
            HStack(spacing: 6) {
                rolodexNavButton(systemImage: "chevron.left", accent: activeAccent) {
                    stepWheel(by: -1)
                }

                // Smooth 120fps 3D curved Rolodex deck — continuous wheelPosition + GPU-cached cards
                ZStack {
                    ForEach(Array(looks.enumerated()), id: \.element.look) { index, lookTheme in
                        let visualDelta = circularDelta(from: wheelPosition, to: Double(index), count: count)
                        let distance = abs(visualDelta)

                        if distance <= 3.25 {
                            let xOffset = visualDelta * 86.0 - (visualDelta * distance * 5.0)
                            let yOffset = distance * 3.5
                            let scale = max(0.72, 1.0 - distance * 0.115)
                            let yawDegrees = -visualDelta * 26.0
                            let opacity = max(0.0, 1.0 - distance * 0.27)
                            let isFront = index == currentIndex
                            let isApplied = lookTheme.look == appliedLook

                            SignatureLookRolodexCard(
                                sampleTheme: lookTheme,
                                activeAccent: activeAccent,
                                isFront: isFront,
                                isApplied: isApplied,
                                onSelect: {
                                    jumpAndCommit(to: index)
                                },
                                onHoverChange: { hovering in
                                    onHoverLook(hovering ? lookTheme.look : nil)
                                }
                            )
                            .frame(width: 174, height: 92)
                            .drawingGroup()
                            .scaleEffect(scale)
                            .rotation3DEffect(
                                .degrees(yawDegrees),
                                axis: (x: 0, y: 1, z: 0),
                                perspective: 0.62
                            )
                            .offset(x: xOffset, y: yOffset)
                            .opacity(opacity)
                            .zIndex(100.0 - distance * 10.0)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 102)
                .clipped()
                .background {
                    RolodexScrollWheelCapture(
                        onContinuousScroll: { deltaCards in
                            applyContinuousScroll(deltaCards: deltaCards)
                        },
                        onDiscreteStep: { steps in
                            stepWheel(by: steps)
                        },
                        onScrollGestureEnded: {
                            snapWheelToNearest()
                        }
                    )
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { value in
                            snapTask?.cancel()
                            if dragBasePosition == nil {
                                dragBasePosition = wheelPosition
                            }
                            if let base = dragBasePosition {
                                wheelPosition = base - Double(value.translation.width) / 92.0
                                notifyBrowsedIndexIfChanged()
                            }
                        }
                        .onEnded { value in
                            let base = dragBasePosition ?? wheelPosition
                            dragBasePosition = nil
                            let predicted = base - Double(value.predictedEndTranslation.width) / 92.0
                            let target = predicted.rounded()
                            withAnimation(.interpolatingSpring(stiffness: 240, damping: 24)) {
                                wheelPosition = target
                            }
                            notifyBrowsedIndex(for: Int(target))
                        }
                )

                rolodexNavButton(systemImage: "chevron.right", accent: activeAccent) {
                    stepWheel(by: 1)
                }
            }

            // Compact Rolodex index-tab rail for instant 1-click jumps
            HStack(spacing: 5) {
                ForEach(Array(looks.enumerated()), id: \.element.look) { index, lookTheme in
                    let isFocused = index == currentIndex
                    let swatchColor = Color(themeColor: lookTheme.accentColor)
                    Button {
                        jumpAndCommit(to: index)
                    } label: {
                        Capsule(style: .continuous)
                            .fill(isFocused ? activeAccent : swatchColor.opacity(0.45))
                            .frame(width: isFocused ? 22 : 7, height: 5)
                            .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isFocused)
                    }
                    .buttonStyle(.plain)
                    .help("\(lookTheme.look.displayName) — \(lookTheme.look.tagline)")
                    .onHover { hovering in
                        onHoverLook(hovering ? lookTheme.look : nil)
                    }
                }
            }
        }
        .onAppear {
            if !didInitializeWheel {
                wheelPosition = Double(focusedIndex)
                didInitializeWheel = true
            }
        }
        .onChange(of: focusedIndex) { _, newIndex in
            let currentNormalized = normalizedIndex(Int(wheelPosition.rounded()), count: count)
            guard currentNormalized != newIndex else { return }
            let delta = circularDelta(from: wheelPosition, to: Double(newIndex), count: count)
            withAnimation(.interpolatingSpring(stiffness: 240, damping: 25)) {
                wheelPosition += delta
            }
        }
        .onDisappear {
            snapTask?.cancel()
            snapTask = nil
        }
    }

    private func applyContinuousScroll(deltaCards: Double) {
        snapTask?.cancel()
        wheelPosition += deltaCards
        notifyBrowsedIndexIfChanged()
        // Auto-snap shortly after scroll input pauses
        snapTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(110))
            guard !Task.isCancelled else { return }
            snapWheelToNearest()
        }
    }

    private func snapWheelToNearest() {
        snapTask?.cancel()
        let target = wheelPosition.rounded()
        withAnimation(.interpolatingSpring(stiffness: 260, damping: 25)) {
            wheelPosition = target
        }
        notifyBrowsedIndex(for: Int(target))
    }

    private func stepWheel(by delta: Int) {
        guard !looks.isEmpty else { return }
        snapTask?.cancel()
        let target = wheelPosition.rounded() + Double(delta)
        withAnimation(.interpolatingSpring(stiffness: 280, damping: 26)) {
            wheelPosition = target
        }
        notifyBrowsedIndex(for: Int(target))
    }

    private func jumpAndCommit(to targetIndex: Int) {
        guard !looks.isEmpty else { return }
        snapTask?.cancel()
        let delta = circularDelta(from: wheelPosition, to: Double(targetIndex), count: looks.count)
        let target = (wheelPosition + delta).rounded()
        withAnimation(.interpolatingSpring(stiffness: 250, damping: 25)) {
            wheelPosition = target
        }
        let idx = normalizedIndex(Int(target), count: looks.count)
        onCommitLookNow(looks[idx].look)
    }

    private func notifyBrowsedIndexIfChanged() {
        notifyBrowsedIndex(for: Int(wheelPosition.rounded()))
    }

    private func notifyBrowsedIndex(for rawIndex: Int) {
        guard !looks.isEmpty else { return }
        let idx = normalizedIndex(rawIndex, count: looks.count)
        onBrowseLook(looks[idx].look)
    }

    private func normalizedIndex(_ raw: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let mod = raw % count
        return mod >= 0 ? mod : mod + count
    }

    private func circularDelta(from current: Double, to target: Double, count: Int) -> Double {
        guard count > 0 else { return 0 }
        let period = Double(count)
        var diff = (target - current).truncatingRemainder(dividingBy: period)
        if diff > period / 2.0 { diff -= period }
        if diff < -period / 2.0 { diff += period }
        return diff
    }

    @ViewBuilder
    private func rolodexNavButton(systemImage: String, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.primary.opacity(0.85))
                .frame(width: 24, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(accent.opacity(0.24), lineWidth: 0.75)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct SignatureLookRolodexCard: View {
    let sampleTheme: OmniVoiceTheme
    let activeAccent: Color
    let isFront: Bool
    let isApplied: Bool
    let onSelect: () -> Void
    let onHoverChange: (Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        let cardRadius = sampleTheme.look.cardRadius(forRequested: 12)
        let cardShape = RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
        let sampleAccent = Color(themeColor: sampleTheme.accentColor)
        let sampleSecondary = Color(themeColor: sampleTheme.secondaryAccentColor)
        let innerRadius = sampleTheme.look.cardRadius(forRequested: 7)

        Button(action: onSelect) {
            ZStack {
                miniatureBackdrop(accent: sampleAccent, secondary: sampleSecondary)

                VStack(alignment: .leading, spacing: 5) {
                    // Index tab header strip (Rolodex card top edge)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(sampleAccent)
                            .frame(width: 6, height: 6)

                        Text(sampleTheme.look.displayName)
                            .font(.system(size: 11, weight: .bold, design: sampleTheme.look.headerFontDesign))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        Spacer(minLength: 2)

                        if isApplied {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(activeAccent)
                        } else {
                            RoundedRectangle(cornerRadius: min(5, max(1.5, sampleTheme.look.pillRadius)), style: .continuous)
                                .fill(sampleAccent.opacity(0.24))
                                .frame(width: 18, height: 8)
                                .overlay {
                                    RoundedRectangle(cornerRadius: min(5, max(1.5, sampleTheme.look.pillRadius)), style: .continuous)
                                        .stroke(sampleAccent.opacity(0.65), lineWidth: 0.65)
                                }
                        }
                    }

                    // Pure-SwiftUI miniature card surface preview (zero AppKit views so 3D spin is 120fps)
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach([0.42, 0.88, 1.0, 0.64, 0.34], id: \.self) { h in
                            RoundedRectangle(
                                cornerRadius: (sampleTheme.look == .cyberTerminal || sampleTheme.look == .blueprintGrid) ? 0.5 : 1.75,
                                style: .continuous
                            )
                            .fill(
                                LinearGradient(
                                    colors: [sampleAccent, sampleSecondary],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(width: 3.5, height: CGFloat(14 * h))
                        }

                        Spacer()

                        Text("Aa")
                            .font(.system(size: 12, weight: .bold, design: sampleTheme.look.headerFontDesign))
                            .foregroundStyle(.primary.opacity(0.85))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: innerRadius, style: .continuous)
                            .fill(miniatureCardFill(accent: sampleAccent))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: innerRadius, style: .continuous)
                            .stroke(
                                miniatureCardStroke(accent: sampleAccent, secondary: sampleSecondary),
                                lineWidth: sampleTheme.look == .brutalistInk ? 1.5 : 0.85
                            )
                    }
                }
                .padding(8)
            }
            .clipShape(cardShape)
            .overlay {
                cardShape.stroke(
                    isFront
                        ? (isApplied ? activeAccent : sampleAccent)
                        : (isHovered ? sampleAccent.opacity(0.75) : sampleAccent.opacity(0.32)),
                    lineWidth: isFront ? 1.85 : 0.9
                )
            }
            .shadow(
                color: (isFront ? (isApplied ? activeAccent : sampleAccent) : Color.black).opacity(isFront ? 0.28 : 0.20),
                radius: isFront ? 10 : 4,
                x: 0,
                y: isFront ? 4 : 2
            )
        }
        .buttonStyle(.plain)
        .help("\(sampleTheme.look.displayName) — \(sampleTheme.look.tagline)")
        .onHover { hovering in
            isHovered = hovering
            onHoverChange(hovering)
        }
    }

    @ViewBuilder
    private func miniatureBackdrop(accent: Color, secondary: Color) -> some View {
        let tint = Color(themeColor: sampleTheme.surfaceTint)
        switch sampleTheme.look {
        case .liquidGlass:
            LinearGradient(
                colors: [
                    tint.opacity(colorScheme == .dark ? 0.82 : 0.22),
                    accent.opacity(colorScheme == .dark ? 0.30 : 0.20),
                    secondary.opacity(colorScheme == .dark ? 0.28 : 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .crystalPrism:
            LinearGradient(
                colors: [
                    Color(red: 0.26, green: 0.84, blue: 1.0).opacity(colorScheme == .dark ? 0.38 : 0.24),
                    accent.opacity(colorScheme == .dark ? 0.42 : 0.26),
                    Color(red: 0.98, green: 0.48, blue: 0.88).opacity(colorScheme == .dark ? 0.34 : 0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            OmniVoiceWindowBackground(theme: sampleTheme, colorScheme: colorScheme)
        }
    }

    private func miniatureCardFill(accent: Color) -> Color {
        switch sampleTheme.look {
        case .liquidGlass, .crystalPrism:
            colorScheme == .dark ? Color.white.opacity(0.11) : Color.white.opacity(0.68)
        case .studioPro:
            colorScheme == .dark ? Color(red: 0.11, green: 0.125, blue: 0.155) : Color(red: 0.98, green: 0.99, blue: 1.0)
        case .cyberTerminal:
            colorScheme == .dark ? Color(red: 0.025, green: 0.055, blue: 0.042) : Color(red: 0.94, green: 0.97, blue: 0.95)
        case .editorialPaper:
            colorScheme == .dark ? Color(red: 0.15, green: 0.13, blue: 0.11) : Color(red: 0.99, green: 0.975, blue: 0.945)
        case .softClay:
            colorScheme == .dark ? Color(red: 0.15, green: 0.135, blue: 0.19) : Color(red: 0.97, green: 0.96, blue: 0.99)
        case .brutalistInk:
            colorScheme == .dark ? Color(red: 0.06, green: 0.06, blue: 0.06) : Color.white
        case .blueprintGrid:
            colorScheme == .dark ? Color(red: 0.05, green: 0.15, blue: 0.26) : Color(red: 0.93, green: 0.965, blue: 1.0)
        case .retroSynth:
            colorScheme == .dark ? Color(red: 0.11, green: 0.045, blue: 0.20) : Color(red: 0.98, green: 0.945, blue: 1.0)
        case .zenWashi:
            colorScheme == .dark ? Color(red: 0.12, green: 0.135, blue: 0.11) : Color(red: 0.97, green: 0.968, blue: 0.94)
        }
    }

    private func miniatureCardStroke(accent: Color, secondary: Color) -> LinearGradient {
        switch sampleTheme.look {
        case .crystalPrism:
            LinearGradient(
                colors: [Color(red: 0.4, green: 0.92, blue: 1.0), accent, Color(red: 0.98, green: 0.54, blue: 0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .retroSynth:
            LinearGradient(colors: [accent, secondary], startPoint: .leading, endPoint: .trailing)
        case .brutalistInk:
            LinearGradient(colors: [accent, accent], startPoint: .leading, endPoint: .trailing)
        default:
            LinearGradient(
                colors: [accent.opacity(0.45), secondary.opacity(0.25)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

/// Captures mouse scroll wheel & trackpad gestures while the pointer is over the
/// Rolodex so scrolling smoothly spins the drum (including trackpad momentum)
/// instead of scrolling the parent Settings page.
private struct RolodexScrollWheelCapture: NSViewRepresentable {
    let onContinuousScroll: (Double) -> Void
    let onDiscreteStep: (Int) -> Void
    let onScrollGestureEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onContinuousScroll: onContinuousScroll,
            onDiscreteStep: onDiscreteStep,
            onScrollGestureEnded: onScrollGestureEnded
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onContinuousScroll = onContinuousScroll
        context.coordinator.onDiscreteStep = onDiscreteStep
        context.coordinator.onScrollGestureEnded = onScrollGestureEnded
        context.coordinator.attach(to: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator {
        var onContinuousScroll: (Double) -> Void
        var onDiscreteStep: (Int) -> Void
        var onScrollGestureEnded: () -> Void
        private weak var targetView: NSView?
        nonisolated(unsafe) private var monitor: Any?

        init(
            onContinuousScroll: @escaping (Double) -> Void,
            onDiscreteStep: @escaping (Int) -> Void,
            onScrollGestureEnded: @escaping () -> Void
        ) {
            self.onContinuousScroll = onContinuousScroll
            self.onDiscreteStep = onDiscreteStep
            self.onScrollGestureEnded = onScrollGestureEnded
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        func attach(to view: NSView) {
            targetView = view
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                let consumed = MainActor.assumeIsolated {
                    guard let self else { return false }
                    return self.handleScroll(event)
                }
                return consumed ? nil : event
            }
        }

        func detach() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            targetView = nil
        }

        /// Returns `true` if the scroll event was consumed by the Rolodex.
        private func handleScroll(_ event: NSEvent) -> Bool {
            guard let view = targetView,
                  let window = view.window,
                  event.window === window else {
                return false
            }

            let localPoint = view.convert(event.locationInWindow, from: nil)
            guard view.bounds.contains(localPoint) else {
                return false
            }

            if event.momentumPhase == .ended || event.momentumPhase == .cancelled {
                onScrollGestureEnded()
                return true
            }
            if (event.phase == .ended || event.phase == .cancelled) && event.momentumPhase.isEmpty {
                onScrollGestureEnded()
                return true
            }

            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            let primaryDelta = abs(dx) > abs(dy) ? dx : dy
            guard abs(primaryDelta) > 0.01 else { return true }

            if event.hasPreciseScrollingDeltas {
                // Smooth continuous trackpad/Magic Mouse motion (~44pt per card)
                onContinuousScroll(Double(-primaryDelta) / 44.0)
            } else {
                // Zero-cooldown discrete mouse scroll wheel tick
                let steps = primaryDelta < 0 ? 1 : -1
                onDiscreteStep(steps)
            }

            return true
        }
    }
}
