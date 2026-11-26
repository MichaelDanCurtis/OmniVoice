import EventKit
import Foundation
import OmniVoiceCore

/// Reads the user's active macOS Calendar event (when authorized) to enrich
/// Meeting Co-Pilot with the real meeting title, attendees, and agenda notes.
@MainActor
final class MeetingCalendarService {
    private let eventStore = EKEventStore()

    var isAuthorized: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            return status == .fullAccess
        }
        return status.rawValue == 3
    }

    func requestAccess() async -> Bool {
        if isAuthorized { return true }
        if #available(macOS 14.0, *) {
            return (try? await eventStore.requestFullAccessToEvents()) ?? false
        } else {
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    /// Returns the calendar event happening right now (or starting within 15 minutes),
    /// or `nil` if Calendar access is not granted or no meeting is scheduled.
    func currentMeetingContext(at now: Date = Date()) -> MeetingCalendarContext? {
        guard isAuthorized else { return nil }

        let windowStart = now.addingTimeInterval(-15 * 60)
        let windowEnd = now.addingTimeInterval(15 * 60)
        let predicate = eventStore.predicateForEvents(withStart: windowStart, end: windowEnd, calendars: nil)
        let events = eventStore.events(matching: predicate)
            .filter { !$0.isAllDay }
            .filter { event in
                guard let start = event.startDate, let end = event.endDate else { return false }
                return end > now.addingTimeInterval(-5 * 60) && start < now.addingTimeInterval(15 * 60)
            }

        guard let best = events.sorted(by: { lhs, rhs in
            let lActive = (lhs.startDate ?? .distantFuture) <= now && (lhs.endDate ?? .distantPast) >= now
            let rActive = (rhs.startDate ?? .distantFuture) <= now && (rhs.endDate ?? .distantPast) >= now
            if lActive != rActive { return lActive }
            return abs((lhs.startDate ?? now).timeIntervalSince(now)) < abs((rhs.startDate ?? now).timeIntervalSince(now))
        }).first else {
            return nil
        }

        let title = (best.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        let attendees: [String] = (best.attendees ?? []).compactMap { participant in
            if let name = participant.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                return name
            }
            let raw = participant.url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
            return raw.isEmpty ? nil : raw
        }

        let notes = best.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        return MeetingCalendarContext(
            title: title,
            attendees: attendees,
            notes: notes?.isEmpty == true ? nil : notes,
            startDate: best.startDate,
            endDate: best.endDate
        )
    }

    /// Returns a non-all-day calendar meeting starting within the next `withinMinutes` minutes
    /// so Co-Pilot can pop a Pre-Meeting Brief right before the call begins.
    func upcomingMeetingSoon(withinMinutes: Double = 3.0, at now: Date = Date()) -> MeetingCalendarContext? {
        guard isAuthorized else { return nil }

        let windowEnd = now.addingTimeInterval(withinMinutes * 60)
        let predicate = eventStore.predicateForEvents(withStart: now, end: windowEnd, calendars: nil)
        let upcoming = eventStore.events(matching: predicate)
            .filter { !$0.isAllDay }
            .filter { event in
                guard let start = event.startDate else { return false }
                let delta = start.timeIntervalSince(now)
                return delta >= -30 && delta <= (withinMinutes * 60)
            }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }

        guard let next = upcoming.first else { return nil }
        let title = (next.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        let attendees: [String] = (next.attendees ?? []).compactMap { participant in
            if let name = participant.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                return name
            }
            let raw = participant.url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
            return raw.isEmpty ? nil : raw
        }
        let notes = next.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        return MeetingCalendarContext(
            title: title,
            attendees: attendees,
            notes: notes?.isEmpty == true ? nil : notes,
            startDate: next.startDate,
            endDate: next.endDate
        )
    }
}
