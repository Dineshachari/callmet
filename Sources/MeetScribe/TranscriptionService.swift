import Foundation
import OSLog

final class TranscriptionService {
    private let logger = Logger(subsystem: "com.dinesh.meetscribe", category: "transcription")

    func schedule(url: URL, logURL: URL? = nil) {
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else {
            logger.info("Low Power Mode enabled. Deferring Whisper transcription.")
            UserDefaults.standard.set(url.path, forKey: "pendingTranscribe")
            return
        }

        guard ProcessInfo.processInfo.thermalState != .critical,
              ProcessInfo.processInfo.thermalState != .serious else {
            logger.warning("Mac is thermally throttled. Deferring Whisper transcription.")
            UserDefaults.standard.set(url.path, forKey: "pendingTranscribe")
            return
        }

        UserDefaults.standard.set(url.path, forKey: "pendingTranscribe")
        if let logURL {
            UserDefaults.standard.set(logURL.path, forKey: "pendingTranscribeLog")
        }

        Task.detached(priority: .utility) {
            // Placeholder for Whisper transcription handoff on macOS.
            // The real implementation can load the saved URL and run Whisper here.
            _ = url
        }
    }
}
