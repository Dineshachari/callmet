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

    var allGranted: Bool {
        calendarGranted && microphoneGranted && screenRecordingGranted
    }
}

struct PermissionDiagnostics {
    let calendarStatus: String
    let microphoneStatus: String
    let screenRecordingPreflightGranted: Bool
}

enum Permissions {
    private static var calendarGrantedOverride = false

    static func currentSnapshot() async -> PermissionSnapshot {
        let snapshot = PermissionSnapshot(
            calendarGranted: isCalendarGranted(),
            microphoneGranted: isMicrophoneGranted(),
            screenRecordingGranted: isScreenRecordingGranted()
        )
        AppTrace.log(
            "permissions.snapshot calendar=\(snapshot.calendarGranted) calendarStatus=\(calendarAuthorizationStatusDescription()) mic=\(snapshot.microphoneGranted) micStatus=\(microphoneAuthorizationStatusDescription()) screen=\(snapshot.screenRecordingGranted)"
        )
        return snapshot
    }

    static func isScreenRecordingGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
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
        AppTrace.log("permissions.screen requestResult=\(granted)")
        return granted
    }

    static func isMicrophoneGranted() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
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
                AppTrace.log("permissions.microphone requestResult=\(granted)")
                continuation.resume(returning: granted)
            }
        }
    }

    static func isCalendarGranted() -> Bool {
        if calendarGrantedOverride {
            return true
        }

        if #available(macOS 14.0, *) {
            let status = EKEventStore.authorizationStatus(for: .event)
            switch status {
            case .authorized, .fullAccess:
                return true
            case .denied, .restricted, .notDetermined, .writeOnly:
                return false
            @unknown default:
                return false
            }
        }

        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .authorized, .fullAccess:
            return true
        case .denied, .restricted, .notDetermined, .writeOnly:
            return false
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
}

extension PermissionSnapshot {
    func summaryLines() -> [String] {
        return [
            "Calendar: \(calendarGranted ? "Granted" : "Needs Access")",
            "Microphone: \(microphoneGranted ? "Granted" : "Needs Access")",
            "Screen Recording: \(screenRecordingGranted ? "Granted" : "Needs Access")"
        ]
    }
}

extension Permissions {
    static func effectiveSnapshotForDiagnostics() -> PermissionSnapshot {
        PermissionSnapshot(
            calendarGranted: isCalendarGranted(),
            microphoneGranted: isMicrophoneGranted(),
            screenRecordingGranted: isScreenRecordingGranted()
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
        var lines = [
            "Effective Calendar: \(effective.calendarGranted ? "granted" : "notGranted")",
            "Effective Microphone: \(effective.microphoneGranted ? "granted" : "notGranted")",
            "Effective Screen Recording: \(effective.screenRecordingGranted ? "granted" : "notGranted")",
            "Calendar status: \(d.calendarStatus)",
            "Microphone status: \(d.microphoneStatus)",
            "Screen Recording preflight: \(d.screenRecordingPreflightGranted ? "granted" : "notGranted")"
        ]

        if d.calendarStatus == "denied" || d.calendarStatus == "restricted" || d.calendarStatus == "writeOnly" {
            lines.append("Calendar: enable in System Settings > Privacy & Security > Calendars.")
        } else if d.calendarStatus == "notDetermined" {
            lines.append("Calendar: notDetermined means macOS should still be able to show a prompt.")
        }

        if d.microphoneStatus == "denied" || d.microphoneStatus == "restricted" {
            lines.append("Microphone: enable in System Settings > Privacy & Security > Microphone.")
        } else if d.microphoneStatus == "notDetermined" {
            lines.append("Microphone: notDetermined means macOS should still be able to show a prompt.")
        }

        if !d.screenRecordingPreflightGranted {
            lines.append("Screen Recording: enable in Privacy & Security > Screen Recording, then fully quit and reopen MeetScribe.")
        }

        return lines
    }
}
