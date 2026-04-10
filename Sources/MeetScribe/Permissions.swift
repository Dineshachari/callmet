import AVFoundation
import EventKit
import CoreGraphics
import AppKit
import OSLog
import Foundation

enum AppTrace {
    private static let logger = Logger(subsystem: "com.dinesh.meetscribe", category: "app")
    private static let queue = DispatchQueue(label: "com.dinesh.meetscribe.trace")
    private static let fileURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/Logs", isDirectory: true)
            .appendingPathComponent("MeetScribe", isDirectory: true)
            .appendingPathComponent("app.log", isDirectory: false)
    }()

    static func log(_ message: String) {
        logger.info("\(message, privacy: .public)")
        queue.async {
            let dir = fileURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if let handle = try? FileHandle(forWritingTo: fileURL) {
                    defer { try? handle.close() }
                    try? handle.seekToEnd()
                    try? handle.write(contentsOf: Data(line.utf8))
                }
            } else {
                try? line.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        }
    }

    static func logURL() -> URL { fileURL }
}

enum PermissionStatus {
    case granted
    case denied
    case unknown
}

struct PermissionSnapshot {
    let calendarGranted: Bool
    let microphoneGranted: Bool
    let screenRecordingGranted: Bool
    let screenRecordingLikelyEnabled: Bool

    var allGranted: Bool {
        calendarGranted && microphoneGranted && screenRecordingGranted
    }

    var screenRecordingOnlyBlocker: Bool {
        calendarGranted && microphoneGranted && !screenRecordingGranted
    }

    var screenRecordingRelaunchLikely: Bool {
        screenRecordingOnlyBlocker && screenRecordingLikelyEnabled
    }
}

struct PermissionDiagnostics {
    let calendarStatus: String
    let microphoneStatus: String
    let screenRecordingPreflightGranted: Bool
}

enum Permissions {
    private static let calendarGrantedPersistedKey = "com.dinesh.meetscribe.calendarGrantedPersisted"
    private static let microphoneGrantedPersistedKey = "com.dinesh.meetscribe.microphoneGrantedPersisted"
    private static let screenRecordingConsentObservedAtKey = "com.dinesh.meetscribe.screenRecordingConsentObservedAt"
    private static var calendarGrantedOverride: Bool {
        get { UserDefaults.standard.bool(forKey: calendarGrantedPersistedKey) }
        set { UserDefaults.standard.set(newValue, forKey: calendarGrantedPersistedKey) }
    }
    private static var microphoneGrantedOverride: Bool {
        get { UserDefaults.standard.bool(forKey: microphoneGrantedPersistedKey) }
        set { UserDefaults.standard.set(newValue, forKey: microphoneGrantedPersistedKey) }
    }
    private static func markScreenRecordingConsentObserved() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: screenRecordingConsentObservedAtKey)
    }

    private static func hasRecentScreenRecordingConsentSignal() -> Bool {
        let value = UserDefaults.standard.double(forKey: screenRecordingConsentObservedAtKey)
        guard value > 0 else { return false }
        // Keep "relaunch likely" hint short-lived; avoid stale false positives across later runs.
        return (Date().timeIntervalSince1970 - value) <= 300
    }

    static func currentSnapshot() async -> PermissionSnapshot {
        let screenGranted = isScreenRecordingGranted()
        let snapshot = PermissionSnapshot(
            calendarGranted: isCalendarGranted(),
            microphoneGranted: isMicrophoneGranted(),
            screenRecordingGranted: screenGranted,
            screenRecordingLikelyEnabled: screenGranted || hasRecentScreenRecordingConsentSignal()
        )
        AppTrace.log(
            "permissions.snapshot calendar=\(snapshot.calendarGranted) calendarStatus=\(calendarAuthorizationStatusDescription()) mic=\(snapshot.microphoneGranted) micStatus=\(microphoneAuthorizationStatusDescription()) screen=\(snapshot.screenRecordingGranted)"
        )
        return snapshot
    }

    static func isScreenRecordingGranted() -> Bool {
        let granted = CGPreflightScreenCaptureAccess()
        if granted {
            markScreenRecordingConsentObserved()
        }
        return granted
    }

    static func openScreenRecordingPrivacyPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    static func requestScreenRecordingIfNeeded() async -> Bool {
        if isScreenRecordingGranted() {
            AppTrace.log("permissions.screen alreadyGranted")
            return true
        }
        let granted = CGRequestScreenCaptureAccess()
        if granted {
            // Persist successful consent to avoid regressing to "needs access" wording.
            // Actual capture still depends on preflight becoming true in a future launch.
            markScreenRecordingConsentObserved()
        } else if !isScreenRecordingGranted() {
            // macOS may not always show the prompt again; push users to the correct settings pane.
            await MainActor.run {
                openScreenRecordingPrivacyPane()
            }
            AppTrace.log("permissions.screen requestNoPromptOrDenied openedSettingsPane=true")
        }
        AppTrace.log("permissions.screen requestResult=\(granted)")
        return granted
    }

    static func isMicrophoneGranted() -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            microphoneGrantedOverride = true
            return true
        case .denied, .restricted:
            microphoneGrantedOverride = false
            return false
        case .notDetermined:
            // Mirror calendar handling for occasional stale post-consent reads.
            return microphoneGrantedOverride
        @unknown default:
            return false
        }
    }

    static func microphoneAuthorizationStatusDescription() -> String {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return "authorized"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .notDetermined:
            return "notDetermined"
        @unknown default:
            return "unknown"
        }
    }

    static func requestMicrophoneIfNeeded() async -> Bool {
        if isMicrophoneGranted() {
            AppTrace.log("permissions.microphone alreadyGranted")
            return true
        }

        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                let status = microphoneAuthorizationStatusDescription()
                AppTrace.log("permissions.microphone requestResult=\(granted) status=\(status)")
                if granted { microphoneGrantedOverride = true }
                continuation.resume(returning: granted || isMicrophoneGranted())
            }
        }
    }

    static func isCalendarGranted() -> Bool {
        if #available(macOS 14.0, *) {
            let status = EKEventStore.authorizationStatus(for: .event)
            switch status {
            case .authorized, .fullAccess:
                calendarGrantedOverride = true
                return true
            case .denied, .restricted, .writeOnly:
                calendarGrantedOverride = false
                return false
            case .notDetermined:
                // Some machines briefly keep reporting notDetermined after a YES callback.
                return calendarGrantedOverride
            @unknown default:
                return false
            }
        }

        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .authorized, .fullAccess:
            calendarGrantedOverride = true
            return true
        case .denied, .restricted, .writeOnly:
            calendarGrantedOverride = false
            return false
        case .notDetermined:
            return calendarGrantedOverride
        @unknown default:
            return false
        }
    }

    static func calendarAuthorizationStatusDescription() -> String {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .authorized:
            return "authorized"
        case .fullAccess:
            return "fullAccess"
        case .writeOnly:
            return "writeOnly"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .notDetermined:
            return "notDetermined"
        @unknown default:
            return "unknown"
        }
    }

    static func requestCalendarIfNeeded() async -> Bool {
        let store = EKEventStore()

        if isCalendarGranted() {
            AppTrace.log("permissions.calendar alreadyGranted status=\(calendarAuthorizationStatusDescription())")
            return true
        }

        if #available(macOS 14.0, *) {
            do {
                let granted = try await store.requestFullAccessToEvents()
                let status = calendarAuthorizationStatusDescription()
                AppTrace.log("permissions.calendar requestFullAccess result=\(granted) status=\(status)")
                // TCC status can lag briefly; trust successful callback for this launch.
                if granted { calendarGrantedOverride = true }
                return granted || isCalendarGranted()
            } catch {
                AppTrace.log("permissions.calendar requestFullAccess error=\(error.localizedDescription)")
                return false
            }
        }

        return await withCheckedContinuation { continuation in
            store.requestAccess(to: .event) { granted, _ in
                AppTrace.log("permissions.calendar requestAccess result=\(granted) status=\(calendarAuthorizationStatusDescription())")
                if granted { calendarGrantedOverride = true }
                continuation.resume(returning: granted)
            }
        }
    }

    @MainActor
    static func requestMissingPermissions() async -> PermissionSnapshot {
        NSApp.activate(ignoringOtherApps: true)

        _ = await requestCalendarIfNeeded()
        _ = await requestMicrophoneIfNeeded()
        _ = await requestScreenRecordingIfNeeded()

        var snapshot = await currentSnapshot()
        if !snapshot.allGranted {
            // Avoid stale reads right after TCC/UI transitions.
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            snapshot = await currentSnapshot()
            if !snapshot.screenRecordingGranted {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                snapshot = await currentSnapshot()
            }
        }
        return snapshot
    }

    static func stabilizedSnapshotForUI() async -> PermissionSnapshot {
        var snapshot = await currentSnapshot()
        // Screen preflight can momentarily flap right after focus/permission transitions.
        // Re-check before showing a relaunch-only path to avoid false negatives.
        if snapshot.screenRecordingOnlyBlocker && snapshot.screenRecordingLikelyEnabled {
            try? await Task.sleep(nanoseconds: 400_000_000)
            snapshot = await currentSnapshot()
            if snapshot.screenRecordingOnlyBlocker && snapshot.screenRecordingLikelyEnabled {
                try? await Task.sleep(nanoseconds: 700_000_000)
                snapshot = await currentSnapshot()
            }
        }
        return snapshot
    }
}

extension PermissionSnapshot {
    func summaryLines() -> [String] {
        let screenLine: String
        if screenRecordingGranted {
            screenLine = "Screen Recording: Granted"
        } else if screenRecordingRelaunchLikely {
            screenLine = "Screen Recording: Not active for this run (quit and reopen after enabling)"
        } else {
            screenLine = "Screen Recording: Needs Access"
        }

        return [
            "Calendar: \(calendarGranted ? "Granted" : "Needs Access")",
            "Microphone: \(microphoneGranted ? "Granted" : "Needs Access")",
            screenLine
        ]
    }
}

extension Permissions {
    static func effectiveSnapshotForDiagnostics() -> PermissionSnapshot {
        let screenGranted = isScreenRecordingGranted()
        return PermissionSnapshot(
            calendarGranted: isCalendarGranted(),
            microphoneGranted: isMicrophoneGranted(),
            screenRecordingGranted: screenGranted,
            screenRecordingLikelyEnabled: screenGranted || hasRecentScreenRecordingConsentSignal()
        )
    }

    static func requestAllPermissions() async -> PermissionStatus {
        let snapshot = await requestMissingPermissions()
        return snapshot.allGranted ? .granted : .denied
    }

    static func diagnostics() -> PermissionDiagnostics {
        PermissionDiagnostics(
            calendarStatus: calendarAuthorizationStatusDescription(),
            microphoneStatus: microphoneAuthorizationStatusDescription(),
            screenRecordingPreflightGranted: isScreenRecordingGranted()
        )
    }

    static func diagnosticsLines() -> [String] {
        let d = diagnostics()
        let effective = effectiveSnapshotForDiagnostics()
        let allEffectiveGranted = effective.calendarGranted && effective.microphoneGranted && effective.screenRecordingGranted

        var lines = [
            "Effective Calendar: \(effective.calendarGranted ? "granted" : "notGranted")",
            "Effective Microphone: \(effective.microphoneGranted ? "granted" : "notGranted")",
            "Effective Screen Recording: \(effective.screenRecordingGranted ? "granted" : "notGranted")"
        ]

        // Keep raw internals only when useful for debugging or when permissions are incomplete.
        if !allEffectiveGranted || d.calendarStatus != "authorized" || d.microphoneStatus != "authorized" || !d.screenRecordingPreflightGranted {
            lines.append("Calendar status: \(d.calendarStatus)")
            lines.append("Microphone status: \(d.microphoneStatus)")
            lines.append("Screen Recording preflight: \(d.screenRecordingPreflightGranted ? "granted" : "notGranted")")
            lines.append("Screen Recording recent consent signal: \(effective.screenRecordingLikelyEnabled ? "true" : "false")")
        }

        if !effective.calendarGranted && (d.calendarStatus == "denied" || d.calendarStatus == "restricted" || d.calendarStatus == "writeOnly") {
            lines.append("Calendar: enable in System Settings > Privacy & Security > Calendars.")
        } else if !effective.calendarGranted && d.calendarStatus == "notDetermined" {
            lines.append("Calendar: notDetermined means macOS should still be able to show a prompt.")
        }

        if !effective.microphoneGranted && (d.microphoneStatus == "denied" || d.microphoneStatus == "restricted") {
            lines.append("Microphone: enable in System Settings > Privacy & Security > Microphone.")
        } else if !effective.microphoneGranted && d.microphoneStatus == "notDetermined" {
            lines.append("Microphone: notDetermined means macOS should still be able to show a prompt.")
        }

        if !effective.screenRecordingGranted {
            lines.append("Screen Recording: enable in Privacy & Security > Screen Recording, then fully quit and reopen MeetScribe.")
        }

        return lines
    }
}
