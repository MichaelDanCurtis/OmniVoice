import AppKit
import Observation
import OmniVoiceCore
import SwiftUI

struct CommandModeLogEntry: Identifiable, Equatable {
    let id: String
    let icon: String
    let title: String
    let detail: String
    let isError: Bool
    let timestamp: Date

    init(
        id: String = UUID().uuidString,
        icon: String,
        title: String,
        detail: String,
        isError: Bool = false,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.icon = icon
        self.title = title
        self.detail = detail
        self.isError = isError
        self.timestamp = timestamp
    }
}

@MainActor
@Observable
final class CommandModeOverlayState {
    var isActive = false
    var isExecuting = false
    var isMicOpen = false
    var isMicMuted = false
    var isHearingSpeech = false
    var inputLevel: Float = 0
    var mcpStatusLabel = "Built-in macOS Driver"
    var isMCPConnected = false
    var showInstallHint = false
    var corner: CommandModeCorner = .bottomLeft
    var entries: [CommandModeLogEntry] = []
    var theme: OmniVoiceTheme = .defaultTheme
    var appearanceMode: AppAppearanceMode = .system
}

@MainActor
final class CommandModeOverlayWindow {
    private static let panelSize = CGSize(width: 368, height: 266)

    private var panel: NSPanel?
    let state = CommandModeOverlayState()
    var onReconnectMCP: (() -> Void)?
    var onToggleMute: (() -> Void)?
    var onCycleCorner: (() -> Void)?
    var onExitCommandMode: (() -> Void)?
    var onOpenCuaDocs: (() -> Void)?

    func show(
        corner: CommandModeCorner,
        theme: OmniVoiceTheme,
        appearanceMode: AppAppearanceMode
    ) {
        state.isActive = true
        state.corner = corner
        state.theme = theme
        state.appearanceMode = appearanceMode
        ensurePanel()
        repositionPanel()
        panel?.alphaValue = 0
        panel?.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel?.animator().alphaValue = 1
        }
    }

    func updateCorner(_ corner: CommandModeCorner, theme: OmniVoiceTheme, appearanceMode: AppAppearanceMode) {
        state.corner = corner
        state.theme = theme
        state.appearanceMode = appearanceMode
        repositionPanel()
    }

    func updateNativeDriverState(ready: Bool, toolCount: Int) {
        state.isMCPConnected = ready
        state.showInstallHint = !ready
        state.mcpStatusLabel = ready
            ? "Built-in macOS Driver · \(toolCount) tools"
            : "Accessibility permission needed"
    }

    func setExecuting(_ running: Bool) {
        state.isExecuting = running
    }

    func updateMicState(isOpen: Bool, isMuted: Bool, isHearingSpeech: Bool, level: Float) {
        state.isMicOpen = isOpen
        state.isMicMuted = isMuted
        state.isHearingSpeech = isHearingSpeech
        state.inputLevel = level
    }

    func appendLog(_ entry: CommandModeLogEntry) {
        withAnimation(.easeOut(duration: 0.18)) {
            state.entries.insert(entry, at: 0)
            if state.entries.count > 12 {
                state.entries.removeLast(state.entries.count - 12)
            }
        }
    }

    func hide() {
        state.isActive = false
        state.isExecuting = false
        panel?.orderOut(nil)
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let created = NSPanel(
            contentRect: CGRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        created.isFloatingPanel = true
        created.becomesKeyOnlyIfNeeded = true
        created.hidesOnDeactivate = false
        created.isOpaque = false
        created.backgroundColor = .clear
        created.hasShadow = false
        created.level = .floating
        created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        created.contentView = NSHostingView(
            rootView: CommandModeOverlayView(
                state: state,
                onReconnect: { [weak self] in self?.onReconnectMCP?() },
                onToggleMute: { [weak self] in self?.onToggleMute?() },
                onCycleCorner: { [weak self] in self?.onCycleCorner?() },
                onExit: { [weak self] in self?.onExitCommandMode?() },
                onOpenDocs: { [weak self] in self?.onOpenCuaDocs?() }
            )
        )
        panel = created
    }

    private func repositionPanel() {
        guard let panel else { return }
        let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let inset: CGFloat = 18
        let x: CGFloat
        let y: CGFloat
        switch state.corner {
        case .bottomLeft:
            x = screen.minX + inset
            y = screen.minY + inset
        case .topLeft:
            x = screen.minX + inset
            y = screen.maxY - Self.panelSize.height - inset
        case .topRight:
            x = screen.maxX - Self.panelSize.width - inset
            y = screen.maxY - Self.panelSize.height - inset
        case .bottomRight:
            x = screen.maxX - Self.panelSize.width - inset
            y = screen.minY + inset
        }
        panel.setFrame(CGRect(origin: CGPoint(x: x, y: y), size: Self.panelSize), display: true)
    }
}

private struct CommandModeOverlayView: View {
    @Bindable var state: CommandModeOverlayState
    let onReconnect: () -> Void
    let onToggleMute: () -> Void
    let onCycleCorner: () -> Void
    let onExit: () -> Void
    let onOpenDocs: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ResolvedThemePalette { state.theme.resolvedPalette(for: colorScheme) }
    private var accent: Color { Color(themeColor: palette.accentGraphic) }
    private var secondary: Color { Color(themeColor: palette.secondaryAccentGraphic) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(state.isMicMuted ? Color.secondary : (state.isHearingSpeech ? Color.green : (state.isMCPConnected ? Color.cyan : Color.orange)))
                    .frame(width: 8, height: 8)
                    .shadow(color: (state.isHearingSpeech ? Color.green : Color.cyan).opacity(state.isMicMuted ? 0 : 0.85), radius: 5)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("COMMAND MODE")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(accent)
                        if state.isExecuting {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
                    Text(
                        state.isMicMuted
                            ? "Mic muted · click mic to resume"
                            : (state.isHearingSpeech ? "Hearing command…" : "Hands-free mic open · \(state.mcpStatusLabel)")
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer()

                Button {
                    onToggleMute()
                } label: {
                    Image(systemName: state.isMicMuted ? "mic.slash.fill" : "mic.fill")
                        .foregroundStyle(state.isMicMuted ? Color.orange : accent)
                }
                .help(state.isMicMuted ? "Unmute hands-free mic" : "Mute hands-free mic")

                Button {
                    onCycleCorner()
                } label: {
                    Image(systemName: "rectangle.inset.bottomleft.filled")
                }
                .help("Move window corner (\(state.corner.displayName))")

                Button {
                    onExit()
                } label: {
                    Image(systemName: "xmark")
                }
                .help("Exit Command Mode (or say “exit command mode”)")
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)

            // Live hands-free mic meter bar
            if !state.isMicMuted {
                let normalized = min(max(Double(state.inputLevel) * 28.0, 0.04), 1.0)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [state.isHearingSpeech ? Color.green : accent, secondary],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(8, proxy.size.width * normalized))
                            .animation(.easeOut(duration: 0.08), value: normalized)
                    }
                }
                .frame(height: 3.5)
            }

            if state.showInstallHint {
                HStack(spacing: 8) {
                    Text("Grant Accessibility access for native UI control:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Settings") {
                        onOpenDocs()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
                .padding(8)
                .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if state.entries.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Speak any desktop action to run natively on macOS.")
                        .font(.caption)
                        .foregroundStyle(.primary.opacity(0.9))
                    Text("Try “open Safari”, “scroll down”, “click Send”, or “exit command mode”.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(state.entries) { entry in
                            HStack(alignment: .top, spacing: 7) {
                                Image(systemName: entry.icon)
                                    .font(.caption)
                                    .foregroundStyle(entry.isError ? Color.red : accent)
                                    .frame(width: 14)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.title)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                    if !entry.detail.isEmpty {
                                        Text(entry.detail)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(14)
        .frame(width: 352, height: 250, alignment: .topLeading)
        .modifier(CommandModeGlassSurface(accent: accent, secondary: secondary))
        .padding(8)
        .preferredColorScheme(state.appearanceMode.colorScheme)
    }
}

private struct CommandModeGlassSurface: ViewModifier {
    let accent: Color
    let secondary: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        content
            .background {
                ZStack {
                    shape
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.32), accent.opacity(0.42), secondary.opacity(0.28)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2.0
                        )
                        .blur(radius: 2.6)

                    shape
                        .fill(.ultraThinMaterial)
                        .opacity(0.86)

                    shape
                        .fill(Color.black.opacity(0.68))

                    shape
                        .strokeBorder(
                            LinearGradient(
                                colors: [accent.opacity(0.55), Color.white.opacity(0.28), secondary.opacity(0.35)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.0
                        )
                }
                .shadow(color: Color.black.opacity(0.36), radius: 10, x: 0, y: 4)
            }
    }
}
