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
    private var isStartingRecording = false
    var isRecording: Bool { currentSession != nil }

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
        if isStartingRecording || currentSession != nil {
            AppTrace.log("meeting.handle ignored reason=busy source=\(meetingRequest.source == .scheduled ? "scheduled" : "manual") name=\(meetingRequest.meetingName)")
            return
        }
        isStartingRecording = true
        AppTrace.log("meeting.handle source=\(meetingRequest.source == .scheduled ? "scheduled" : "manual") name=\(meetingRequest.meetingName)")
        Task {
            defer { isStartingRecording = false }
            do {
                try await startRecording(for: meetingRequest)
            } catch {
                AppTrace.log("meeting.startRecording failed error=\(error.localizedDescription)")
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
        AppTrace.log("meeting.startRecording begin url=\(request.meetingURL.absoluteString) name=\(request.meetingName)")
        let snapshot = await Permissions.currentSnapshot()
        AppTrace.log("meeting.startRecording snapshot calendar=\(snapshot.calendarGranted) mic=\(snapshot.microphoneGranted) screen=\(snapshot.screenRecordingGranted)")

        if !snapshot.calendarGranted || !snapshot.microphoneGranted {
            let updatedSnapshot = await Permissions.requestMissingPermissions()
            if !updatedSnapshot.calendarGranted || !updatedSnapshot.microphoneGranted {
                AppTrace.log("meeting.permissionsMissing calendar=\(updatedSnapshot.calendarGranted) mic=\(updatedSnapshot.microphoneGranted) screen=\(updatedSnapshot.screenRecordingGranted)")
                throw NSError(domain: "MeetScribe", code: 5, userInfo: [NSLocalizedDescriptionKey: "Calendar and Microphone permissions are required"])
            }
        }

        if !snapshot.screenRecordingGranted {
            AppTrace.log("meeting.screenRecording preflightFalse – will attempt capture anyway (ad-hoc signing can cause stale reads)")
        }

        let joinedAt = Date()
        keepAwake.start()
        AppTrace.log("meeting.keepAwake started")

        do {
            AppTrace.log("meeting.joiner.begin")
            let windowID = try await joiner.join(url: request.meetingURL, botDisplayName: botSettings.displayName)
            AppTrace.log("meeting.joiner.success windowID=\(windowID)")
            let recordingStartedAt = Date()

            let outputDirectory = outputFolderStore.recordingDirectoryURL()
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

            let outputURL = outputDirectory
                .appendingPathComponent("meetscribe-\(UUID().uuidString).mov")

            AppTrace.log("meeting.writer.start output=\(outputURL.path)")
            try writer.start(url: outputURL)
            AppTrace.log("meeting.writer.started")

            AppTrace.log("meeting.mixer.start")
            try mixer.start()
            AppTrace.log("meeting.mixer.started")

            AppTrace.log("meeting.captureSession.start windowID=\(windowID)")
            try await captureSession.start(windowID: windowID)
            AppTrace.log("meeting.captureSession.started")

            currentSession = MeetingSession(
                request: request,
                recordingURL: outputURL,
                joinedAt: joinedAt,
                recordingStartedAt: recordingStartedAt
            )
            NotificationCenter.default.post(name: Notification.Name("captureStarted"), object: nil)
            AppTrace.log("meeting.captureStarted output=\(outputURL.path)")
        } catch {
            currentSession = nil
            keepAwake.stop()
            AppTrace.log("meeting.recordingPipeline failed error=\(error.localizedDescription)")
            throw error
        }
    }

    func stopRecording() async {
        guard let currentSession else {
            AppTrace.log("meeting.stopRecording ignored noActiveSession")
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
        NotificationCenter.default.post(name: .captureStopped, object: nil)
        AppTrace.log("meeting.captureStopped output=\(currentSession.recordingURL.path)")
    }
}

private struct MeetingSession {
    let request: MeetingRequest
    let recordingURL: URL
    let joinedAt: Date
    let recordingStartedAt: Date
}
