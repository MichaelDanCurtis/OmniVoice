import AppKit
import SwiftUI
import OmniVoiceCore

@main
struct OmniVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @State private var isEngineFrameExpanded = false

    var body: some Scene {
        WindowGroup("OmniVoice", id: "control-panel") {
            controlPanelContent
            .task {
                appDelegate.attach(model: model)
                await model.refreshEngineStatus()
            }
        }

        Window("Conversation", id: "conversation-mode") {
            ConversationModeView(model: model)
                .preferredColorScheme(model.preferences.appearanceMode.colorScheme)
                .task {
                    appDelegate.attach(model: model)
                    await model.loadConversations()
                }
        }
        .defaultSize(width: 980, height: 680)

        MenuBarExtra("OmniVoice", systemImage: "waveform") {
            MenuBarControlsView(
                model: model,
                showTestCaption: {
                    appDelegate.showOverlay(
                        text: model.lastTestResult == "No test run yet" ? "OmniVoice is running" : model.lastTestResult,
                        styleName: model.preferences.style.displayName,
                        theme: model.activeTheme
                    )
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        appDelegate.commitOverlayAnimation()
                    }
                },
                requestAccessibilityPermission: {
                    appDelegate.requestAccessibilityPermission()
                }
            )
            .preferredColorScheme(model.preferences.appearanceMode.colorScheme)
            .task {
                appDelegate.attach(model: model)
                await model.refreshEngineStatus()
            }
        }

        Settings {
            settingsContent
            .task {
                await model.refreshEngineStatus()
            }
        }
    }

    private var controlPanelContent: some View {
        ZStack(alignment: model.activeTheme.engineFrameSide.stackAlignment) {
            settingsContent
                .frame(maxWidth: .infinity, alignment: model.activeTheme.engineFrameSide.settingsAlignment)

            EngineFrameView(
                model: model,
                side: model.activeTheme.engineFrameSide,
                isExpanded: $isEngineFrameExpanded,
                insertTranscript: { transcript in
                    Task {
                        await appDelegate.insertTextAtCurrentCursor(transcript.displayText)
                    }
                }
            )
        }
        .frame(width: controlPanelWidth)
        .background {
            ControlPanelWindowSizer(
                targetContentWidth: controlPanelWidth,
                anchor: .leading
            )
        }
        .preferredColorScheme(model.preferences.appearanceMode.colorScheme)
    }

    private var settingsContent: some View {
        SettingsView(
            model: model,
            showTestCaption: showTestCaption,
            requestAccessibilityPermission: {
                appDelegate.requestAccessibilityPermission()
            },
            refreshPermissions: {
                appDelegate.refreshPermissionStatus()
            },
            showConversationHistory: {
                isEngineFrameExpanded = true
            }
        )
        .preferredColorScheme(model.preferences.appearanceMode.colorScheme)
    }

    private var controlPanelWidth: CGFloat {
        SettingsView.preferredWidth
    }

    private func showTestCaption() {
        appDelegate.showOverlay(
            text: model.lastTestResult == "No test run yet" ? "OmniVoice is running" : model.lastTestResult,
            styleName: model.preferences.style.displayName,
            theme: model.activeTheme
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            appDelegate.commitOverlayAnimation()
        }
    }
}

private extension EngineFrameSide {
    var stackAlignment: Alignment {
        switch self {
        case .left:
            .leading
        case .right:
            .trailing
        }
    }

    var settingsAlignment: Alignment {
        switch self {
        case .left:
            .trailing
        case .right:
            .leading
        }
    }
}

private enum WindowWidthAnchor {
    case leading
    case trailing
}

private struct ControlPanelWindowSizer: NSViewRepresentable {
    let targetContentWidth: CGFloat
    let anchor: WindowWidthAnchor

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else {
                return
            }

            resize(window)
        }
    }

    private func resize(_ window: NSWindow) {
        let currentFrame = window.frame
        let currentContentRect = window.contentRect(forFrameRect: currentFrame)
        guard abs(currentContentRect.width - targetContentWidth) > 1 else {
            return
        }

        let desiredContentRect = NSRect(
            x: 0,
            y: 0,
            width: targetContentWidth,
            height: currentContentRect.height
        )
        let desiredFrameRect = window.frameRect(forContentRect: desiredContentRect)
        var nextFrame = currentFrame
        nextFrame.size.width = desiredFrameRect.width

        if anchor == .trailing {
            nextFrame.origin.x = currentFrame.maxX - desiredFrameRect.width
        }

        window.setFrame(nextFrame, display: true, animate: true)
    }
}
