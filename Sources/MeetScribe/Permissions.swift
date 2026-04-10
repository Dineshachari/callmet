import AVFoundation
import EventKit
import CoreGraphics
import AppKit
import ScreenCaptureKit

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

enum Permissions {
    static func currentSnapshot() async -> PermissionSnapshot {
        PermissionSnapshot(
            calendarGranted: isCalendarGranted(),
            microphoneGranted: isMicrophoneGranted(),
            screenRecordingGranted: await isScreenRecordingGranted()
        )
    }

    static func isScreenRecordingGranted() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            return false
        }
    }

    static func requestScreenRecordingIfNeeded() async -> Bool {
        if await isScreenRecordingGranted() {
            return true
        }
        return CGRequestScreenCaptureAccess()
    }

    static func isMicrophoneGranted() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static func requestMicrophoneIfNeeded() async -> Bool {
        if isMicrophoneGranted() {
            return true
        }

        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    static func isCalendarGranted() -> Bool {
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
        case .authorized:
            return true
        case .denied, .restricted, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    static func requestCalendarIfNeeded() async -> Bool {
        let store = EKEventStore()

        if isCalendarGranted() {
            return true
        }

        if #available(macOS 14.0, *) {
            do {
                return try await store.requestFullAccessToEvents()
            } catch {
                return false
            }
        }

        return await withCheckedContinuation { continuation in
            store.requestAccess(to: .event) { granted, _ in
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

        return await currentSnapshot()
    }
}

extension PermissionSnapshot {
    func summaryLines() -> [String] {
        [
            "Calendar: \(calendarGranted ? "Granted" : "Needs Access")",
            "Microphone: \(microphoneGranted ? "Granted" : "Needs Access")",
            "Screen Recording: \(screenRecordingGranted ? "Granted" : "Needs Access")"
        ]
    }
}

extension Permissions {
    static func requestAllPermissions() async -> PermissionStatus {
        let snapshot = await requestMissingPermissions()
        return snapshot.allGranted ? .granted : .denied
    }
}
