import AppKit
import OmniVoiceCore

@MainActor
struct DictationCommandExecutor {
    enum ExecutionError: LocalizedError {
        case applicationNotFound(String)

        var errorDescription: String? {
            switch self {
            case .applicationNotFound(let name):
                "Could not find \(name)."
            }
        }
    }

    func execute(_ command: DictationCommand) throws {
        switch command.action {
        case .openApplication(let name):
            try openApplication(named: name)
        case .showCommandPalette, .undoLastDictation:
            break
        }
    }

    private func openApplication(named name: String) throws {
        guard let url = Self.applicationURL(named: name) else {
            throw ExecutionError.applicationNotFound(name)
        }

        guard NSWorkspace.shared.open(url) else {
            throw ExecutionError.applicationNotFound(name)
        }
    }

    private static func applicationURL(named name: String) -> URL? {
        let normalized = normalizedName(name)
        if let bundleID = knownBundleIDs[normalized],
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url
        }

        let fileManager = FileManager.default
        for candidate in pathCandidates(for: name) where fileManager.fileExists(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }

        return nil
    }

    private static func pathCandidates(for name: String) -> [String] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmed.hasSuffix(".app") ? String(trimmed.dropLast(4)) : trimmed
        return [
            "/Applications/\(displayName).app",
            "/System/Applications/\(displayName).app",
            "/Applications/Utilities/\(displayName).app",
            "/System/Applications/Utilities/\(displayName).app",
        ]
    }

    private static func normalizedName(_ name: String) -> String {
        var normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasSuffix(".app") {
            normalized = String(normalized.dropLast(4))
        }
        if normalized.hasSuffix(" app") {
            normalized = String(normalized.dropLast(4))
        }
        return normalized
    }

    private static let knownBundleIDs: [String: String] = [
        "arc": "company.thebrowser.Browser",
        "calendar": "com.apple.iCal",
        "claude": "com.anthropic.claudefordesktop",
        "claude desktop": "com.anthropic.claudefordesktop",
        "codex": "com.openai.codex",
        "chrome": "com.google.Chrome",
        "facetime": "com.apple.FaceTime",
        "finder": "com.apple.finder",
        "google chrome": "com.google.Chrome",
        "mail": "com.apple.mail",
        "messages": "com.apple.MobileSMS",
        "notes": "com.apple.Notes",
        "safari": "com.apple.Safari",
        "slack": "com.tinyspeck.slackmacgap",
        "system settings": "com.apple.systempreferences",
        "terminal": "com.apple.Terminal",
        "textedit": "com.apple.TextEdit",
        "visual studio code": "com.microsoft.VSCode",
        "vs code": "com.microsoft.VSCode",
        "xcode": "com.apple.dt.Xcode",
    ]
}
