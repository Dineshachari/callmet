import Foundation

struct MeetingSessionMetadata {
    let request: MeetingRequest
    let botDisplayName: String
    let recordingURL: URL
    let recordingStartedAt: Date
    let recordingEndedAt: Date
    let joinedAt: Date
}

final class MeetingSessionLogger {
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func writeLog(for metadata: MeetingSessionMetadata) throws -> URL {
        let logURL = metadata.recordingURL.deletingPathExtension().appendingPathExtension("txt")
        let duration = metadata.recordingEndedAt.timeIntervalSince(metadata.recordingStartedAt)
        let scheduledStart = metadata.request.scheduledStartDate.map { formatter.string(from: $0) } ?? "Not scheduled"

        let lines: [String] = [
            "MeetScribe Session Log",
            "Meeting name: \(metadata.request.meetingName)",
            "Meeting URL: \(metadata.request.meetingURL.absoluteString)",
            "Bot display name: \(metadata.botDisplayName)",
            "Meeting source: \(metadata.request.source == .scheduled ? "Scheduled" : "Manual")",
            "Scheduled meeting start: \(scheduledStart)",
            "Joined at: \(formatter.string(from: metadata.joinedAt))",
            "Recording started: \(formatter.string(from: metadata.recordingStartedAt))",
            "Recording ended: \(formatter.string(from: metadata.recordingEndedAt))",
            String(format: "Duration: %.2f seconds", duration),
            "Video codec: HEVC",
            "System audio codec: AAC",
            "Mic audio codec: AAC",
            "Tracks: Video, System Audio, Mic Audio",
            "Recording file: \(metadata.recordingURL.lastPathComponent)"
        ]

        try lines.joined(separator: "\n").appending("\n").write(to: logURL, atomically: true, encoding: .utf8)
        return logURL
    }
}
