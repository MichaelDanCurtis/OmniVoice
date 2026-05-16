import AppKit
import SwiftUI
import OmniVoiceCore

@main
struct OmniVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("OmniVoice", id: "control-panel") {
            controlPanelContent
            .task {
                appDelegate.attach(model: model)
                await model.refreshEngineStatus()
            }
        }

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
                        appDelegate.hideOverlay()
                    }
                },
                requestAccessibilityPermission: {
                    appDelegate.requestAccessibilityPermission()
                }
            )
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
        HStack(spacing: 0) {
            if model.activeTheme.engineFrameSide == .left {
                EngineFrameView(theme: model.activeTheme, side: .left)
                settingsContent
            } else {
                settingsContent
                EngineFrameView(theme: model.activeTheme, side: .right)
            }
        }
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
            }
        )
    }

    private func showTestCaption() {
        appDelegate.showOverlay(
            text: model.lastTestResult == "No test run yet" ? "OmniVoice is running" : model.lastTestResult,
            styleName: model.preferences.style.displayName,
            theme: model.activeTheme
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            appDelegate.hideOverlay()
        }
    }
}
