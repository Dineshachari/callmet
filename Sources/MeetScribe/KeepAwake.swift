import AppKit
import Foundation
import IOKit.pwr_mgt

final class KeepAwake {
    private var activity: NSObjectProtocol?
    private var assertionID: IOPMAssertionID = 0

    func start(reason: String = "MeetScribe recording") {
        if activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
                reason: reason
            )
        }

        if assertionID == 0 {
            IOPMAssertionCreateWithName(
                kIOPMAssertionTypeNoIdleSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason as CFString,
                &assertionID
            )
        }

        warnIfLidCloseWillKill()
    }

    func stop() {
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
        activity = nil

        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
    }

    private func warnIfLidCloseWillKill() {
        let hasExternalDisplay = NSScreen.screens.count > 1
        guard !hasExternalDisplay else { return }

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Keep lid open"
            alert.informativeText = "On MacBook Air, closing the lid can stop recording even with KeepAwake. Use an external display if you want to run with the lid closed."
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    deinit {
        stop()
    }
}
