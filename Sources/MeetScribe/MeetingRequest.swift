import Foundation

enum MeetingRequestSource {
    case scheduled
    case manual
}

struct MeetingRequest {
    let meetingURL: URL
    let meetingName: String
    let scheduledStartDate: Date?
    let source: MeetingRequestSource
}
