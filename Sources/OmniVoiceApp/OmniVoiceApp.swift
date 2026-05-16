import AppKit
import SwiftUI
import OmniVoiceCore

@main
struct OmniVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("OmniVoice", id: "control-panel") {
            SettingsView(
                model: model,
                showTestCaption: {
                    appDelegate.showOverlay(
                        text: model.lastTestResult == "No test run yet" ? "OmniVoice is running" : model.lastTestResult,
                        styleName: model.preferences.style.displayName
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

        MenuBarExtra("OmniVoice", systemImage: "waveform") {
            MenuBarControlsView(
                model: model,
                showTestCaption: {
                    appDelegate.showOverlay(
                        text: model.lastTestResult == "No test run yet" ? "OmniVoice is running" : model.lastTestResult,
                        styleName: model.preferences.style.displayName
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
            SettingsView(
                model: model,
                showTestCaption: {
                    appDelegate.showOverlay(
                        text: model.lastTestResult == "No test run yet" ? "OmniVoice is running" : model.lastTestResult,
                        styleName: model.preferences.style.displayName
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
                await model.refreshEngineStatus()
            }
        }
    }
}
