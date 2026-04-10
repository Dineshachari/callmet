import AppKit
import Foundation
import ScreenCaptureKit

@MainActor
final class MeetingController {
    private let joiner = MeetingJoiner()
    private let captureSession = ScreenCaptureSession()
    private let mixer = AudioMixer()
    private let writer = SegmentWriter()
    private let keepAwake = KeepAwake()
    private let transcriptionService = TranscriptionService()
    private let outputFolderStore = OutputFolderStore.shared
    private let botSettings = BotSettingsStore.shared
    private let sessionLogger = MeetingSessionLogger()

    private var currentSession: MeetingSession?

    init() {
        captureSession.onVideo = { [weak self] sample in
            self?.writer.appendVideo(sample)
        }
        captureSession.onAudio = { [weak self] sample in
            self?.writer.appendSystemAudio(sample)
        }
        mixer.onBuffer = { [weak self] sample in
            self?.writer.appendMicAudio(sample)
        }
    }

    func handle(meetingRequest: MeetingRequest) {
        Task {
            do {
                try await startRecording(for: meetingRequest)
            } catch {
                NotificationCenter.default.post(name: .captureStopped, object: error)
            }
        }
    }

    func joinManualMeeting(url: URL, meetingName: String) {
        handle(meetingRequest: MeetingRequest(
            meetingURL: url,
            meetingName: meetingName,
            scheduledStartDate: nil,
            source: .manual
        ))
    }

    private func startRecording(for request: MeetingRequest) async throws {
        let snapshot = await Permissions.currentSnapshot()
        if !snapshot.allGranted {
            let updatedSnapshot = await Permissions.requestMissingPermissions()
            guard updatedSnapshot.allGranted else {
                throw NSError(domain: "MeetScribe", code: 5, userInfo: [NSLocalizedDescriptionKey: "Permissions are required"])
            }
        }

        let joinedAt = Date()
        keepAwake.start()

        do {
            let windowID = try await joiner.join(url: request.meetingURL, botDisplayName: botSettings.displayName)
            let recordingStartedAt = Date()

            let outputDirectory = outputFolderStore.recordingDirectoryURL()
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

            let outputURL = outputDirectory
                .appendingPathComponent("meetscribe-\(UUID().uuidString).mov")
            currentSession = MeetingSession(
                request: request,
                recordingURL: outputURL,
                joinedAt: joinedAt,
                recordingStartedAt: recordingStartedAt
            )
            try writer.start(url: outputURL)

            try mixer.start()
            try await captureSession.start(windowID: windowID)
        } catch {
            currentSession = nil
            keepAwake.stop()
            throw error
        }
    }

    func stopRecording() async {
        guard let currentSession else {
            return
        }

        mixer.stop()
        await captureSession.stop()
        await writer.finish()
        keepAwake.stop()

        let recordingEndedAt = Date()
        let metadata = MeetingSessionMetadata(
            request: currentSession.request,
            botDisplayName: botSettings.displayName,
            recordingURL: currentSession.recordingURL,
            recordingStartedAt: currentSession.recordingStartedAt,
            recordingEndedAt: recordingEndedAt,
            joinedAt: currentSession.joinedAt
        )

        if let logURL = try? sessionLogger.writeLog(for: metadata) {
            transcriptionService.schedule(url: currentSession.recordingURL, logURL: logURL)
        }

        self.currentSession = nil
    }
}

private struct MeetingSession {
    let request: MeetingRequest
    let recordingURL: URL
    let joinedAt: Date
    let recordingStartedAt: Date
}
