import AppKit
import CoreGraphics
import Foundation
import OmniVoiceCore
import ScreenCaptureKit

/// Captures a compact JPEG snapshot of the main display for Screen-Aware Meeting
/// Co-Pilot answers. Automatically excludes OmniSpeak's own stealth panels.
enum MeetingScreenCaptureHelper {
    static func captureMainDisplayAttachment() async -> AIChatAttachment? {
        guard #available(macOS 14.0, *) else { return nil }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return nil }

            let ownBundleID = Bundle.main.bundleIdentifier
            let excludedApps = content.applications.filter { app in
                guard let ownBundleID else { return false }
                return app.bundleIdentifier == ownBundleID
            }
            let filter = SCContentFilter(display: display, excludingApplications: excludedApps, exceptingWindows: [])

            let config = SCStreamConfiguration()
            let maxWidth = 1280
            let scale = min(1.0, Double(maxWidth) / Double(max(display.width, 1)))
            config.width = max(320, Int((Double(display.width) * scale).rounded()))
            config.height = max(200, Int((Double(display.height) * scale).rounded()))
            config.showsCursor = false

            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let rep = NSBitmapImageRep(cgImage: cgImage)
            guard let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.72]) else {
                return nil
            }
            let dataURL = "data:image/jpeg;base64,\(jpegData.base64EncodedString())"
            return AIChatAttachment(
                kind: .image,
                title: "Active Screen",
                text: "Live screen snapshot during meeting",
                mimeType: "image/jpeg",
                dataURL: dataURL
            )
        } catch {
            return nil
        }
    }
}
