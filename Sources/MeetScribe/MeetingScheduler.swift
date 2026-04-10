import EventKit
import Foundation

final class MeetingScheduler {
    private var timer: DispatchSourceTimer?
    private let store = EKEventStore()

    func start() {
        scheduleNext()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func scheduleNext() {
        Task { [weak self] in
            guard let self else { return }

            let granted = await Permissions.requestCalendarIfNeeded()
            guard granted else { return }

            let now = Date()
            let end = now.addingTimeInterval(24 * 60 * 60)
            let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
            let events = store.events(matching: predicate)
                .compactMap { event -> ScheduledMeetingRequest? in
                    guard let meetingURL = Self.meetingURL(for: event) else { return nil }
                    let meetingName = event.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let resolvedName = (meetingName?.isEmpty == false ? meetingName! : meetingURL.host ?? "Scheduled Meeting")
                    return ScheduledMeetingRequest(
                        startDate: event.startDate,
                        request: MeetingRequest(
                            meetingURL: meetingURL,
                            meetingName: resolvedName,
                            scheduledStartDate: event.startDate,
                            source: .scheduled
                        )
                    )
                }
                .sorted { $0.startDate < $1.startDate }

            guard let next = events.first else { return }

            let fireDate = next.startDate.addingTimeInterval(-120)
            let interval = max(1, fireDate.timeIntervalSinceNow)

            timer?.cancel()
            let newTimer = DispatchSource.makeTimerSource(queue: .main)
            newTimer.schedule(deadline: .now() + interval)
            newTimer.setEventHandler {
                NotificationCenter.default.post(name: .joinMeeting, object: next.request)
                self.scheduleNext()
            }
            newTimer.resume()
            timer = newTimer
        }
    }

    private static func meetingURL(for event: EKEvent) -> URL? {
        let sources: [String?] = [
            event.url?.absoluteString,
            event.location,
            event.notes
        ]

        for source in sources {
            guard let source else { continue }
            if let url = MeetingLinkParser.extractMeetingURL(from: source) {
                return url
            }
        }

        return nil
    }
}

extension Notification.Name {
    static let joinMeeting = Notification.Name("joinMeeting")
    static let captureStopped = Notification.Name("captureStopped")
}

private struct ScheduledMeetingRequest {
    let startDate: Date
    let request: MeetingRequest
}
