import EventKit
import Foundation
import OmniVoiceCore

/// Exports Meeting Wrap-Ups directly into Apple Notes and Apple Reminders.
@MainActor
enum MeetingExportService {
    enum ExportError: LocalizedError {
        case appleScriptFailed(String)
        case remindersDenied
        case noActionItems
        case noRemindersList

        var errorDescription: String? {
            switch self {
            case .appleScriptFailed(let detail):
                "Apple Notes export failed: \(detail)"
            case .remindersDenied:
                "Reminders permission denied — enable it in System Settings → Privacy → Reminders."
            case .noActionItems:
                "No action items or promises to push to Reminders."
            case .noRemindersList:
                "No default Reminders list is configured."
            }
        }
    }

    static func exportToAppleNotes(_ summary: MeetingWrapUpSummary) -> Result<String, Error> {
        let htmlBody = buildNotesHTML(for: summary)
        let escapedBody = escapeForAppleScript(htmlBody)
        let scriptSource = """
        tell application "Notes"
            make new note at folder "Notes" with properties {body:"\(escapedBody)"}
        end tell
        """
        var errorDict: NSDictionary?
        let script = NSAppleScript(source: scriptSource)
        _ = script?.executeAndReturnError(&errorDict)
        if let errorDict {
            // Fallback to default account/folder if "Notes" folder name differs by locale
            let fallbackSource = """
            tell application "Notes"
                make new note with properties {body:"\(escapedBody)"}
            end tell
            """
            var fallbackError: NSDictionary?
            _ = NSAppleScript(source: fallbackSource)?.executeAndReturnError(&fallbackError)
            if let fallbackError {
                let message = (fallbackError[NSAppleScript.errorBriefMessage] as? String)
                    ?? (errorDict[NSAppleScript.errorBriefMessage] as? String)
                    ?? "Unknown error"
                return .failure(ExportError.appleScriptFailed(message))
            }
        }
        return .success("Saved to Notes")
    }

    static func exportActionItemsToReminders(_ summary: MeetingWrapUpSummary) async -> Result<Int, Error> {
        var seen = Set<String>()
        let allItems = (summary.myPromises + summary.actionItems).filter { item in
            let key = item.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !key.isEmpty && seen.insert(key).inserted
        }
        guard !allItems.isEmpty else {
            return .failure(ExportError.noActionItems)
        }

        let store = EKEventStore()
        let granted: Bool
        if #available(macOS 14.0, *) {
            granted = (try? await store.requestFullAccessToReminders()) ?? false
        } else {
            granted = await withCheckedContinuation { continuation in
                store.requestAccess(to: .reminder) { ok, _ in
                    continuation.resume(returning: ok)
                }
            }
        }
        guard granted else {
            return .failure(ExportError.remindersDenied)
        }
        guard let calendar = store.defaultCalendarForNewReminders() else {
            return .failure(ExportError.noRemindersList)
        }

        var createdCount = 0
        for item in allItems {
            let reminder = EKReminder(eventStore: store)
            reminder.calendar = calendar
            reminder.title = item
            reminder.notes = "From OmniSpeak meeting: \(summary.title)"
            do {
                try store.save(reminder, commit: false)
                createdCount += 1
            } catch {
                continue
            }
        }
        do {
            try store.commit()
            return .success(createdCount)
        } catch {
            return .failure(error)
        }
    }

    private static func buildNotesHTML(for summary: MeetingWrapUpSummary) -> String {
        var html = "<h1>\(escapeHTML(summary.title))</h1>"
        html += "<p>\(escapeHTML(summary.executiveSummary))</p>"

        if !summary.decisions.isEmpty {
            html += "<h2>Decisions</h2><ul>"
            for item in summary.decisions {
                html += "<li>\(escapeHTML(item))</li>"
            }
            html += "</ul>"
        }

        if !summary.myPromises.isEmpty {
            html += "<h2>My Promises</h2><ul>"
            for item in summary.myPromises {
                html += "<li>\(escapeHTML(item))</li>"
            }
            html += "</ul>"
        }

        if !summary.actionItems.isEmpty {
            html += "<h2>Action Items</h2><ul>"
            for item in summary.actionItems {
                html += "<li>\(escapeHTML(item))</li>"
            }
            html += "</ul>"
        }

        if !summary.followUpDraft.isEmpty {
            let formatted = escapeHTML(summary.followUpDraft).replacingOccurrences(of: "\n", with: "<br>")
            html += "<h2>Follow-Up Draft</h2><p>\(formatted)</p>"
        }
        return html
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeForAppleScript(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
