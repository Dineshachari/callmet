import CoreMedia
import ScreenCaptureKit

final class ScreenCaptureSession: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    var onVideo: ((CMSampleBuffer) -> Void)?
    var onAudio: ((CMSampleBuffer) -> Void)?

    func start(windowID: CGWindowID) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        AppTrace.log("capture.windowSearch targetID=\(windowID) totalWindows=\(content.windows.count)")
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            let ids = content.windows.prefix(20).map { "\($0.windowID)" }.joined(separator: ",")
            AppTrace.log("capture.windowNotFound targetID=\(windowID) sampleIDs=[\(ids)]")
            throw NSError(domain: "MeetScribe", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to locate target window"])
        }
        AppTrace.log("capture.windowFound id=\(windowID) title=\(window.title ?? "nil")")

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = 1280
        config.height = 720
        config.minimumFrameInterval = CMTime(value: 1, timescale: 24)
        config.capturesAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global())
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global())
        self.stream = stream
        try await stream.startCapture()
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .screen:
            onVideo?(sampleBuffer)
        case .audio, .microphone:
            onAudio?(sampleBuffer)
        @unknown default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        AppTrace.log("capture.streamError error=\(error.localizedDescription)")
        NotificationCenter.default.post(name: .captureStopped, object: error)
    }
}
