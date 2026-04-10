import Foundation
import WebKit

@MainActor
final class MeetingJoiner {
    private let pool = WebViewPool()

    func join(url: URL, botDisplayName: String) async throws -> CGWindowID {
        AppTrace.log("joiner.makeBotWindow")
        _ = pool.makeBotWindow()
        AppTrace.log("joiner.loadURL \(url.absoluteString)")
        try await pool.load(url)
        AppTrace.log("joiner.pageLoaded, waiting 3s for settle")
        try await Task.sleep(nanoseconds: 3_000_000_000)

        let resourceName = url.host?.contains("zoom") == true ? "join_zoom" : "join_meet"
        if let path = Bundle.main.path(forResource: resourceName, ofType: "js"),
           let script = try? String(contentsOfFile: path) {
            let injected = script.replacingOccurrences(
                of: "__MEETSCRIBE_BOT_NAME__",
                with: Self.javascriptStringLiteral(botDisplayName)
            )
            AppTrace.log("joiner.injectScript resource=\(resourceName).js")
            _ = try await pool.run(script: injected)
            AppTrace.log("joiner.scriptInjected")
            if resourceName == "join_meet" {
                try await waitForMeetJoinState()
            }
        } else {
            AppTrace.log("joiner.noScript resource=\(resourceName).js not found in bundle")
        }

        guard let id = pool.windowID else {
            AppTrace.log("joiner.noWindowID")
            throw NSError(domain: "MeetScribe", code: 4, userInfo: [NSLocalizedDescriptionKey: "No window ID available"])
        }
        AppTrace.log("joiner.windowID=\(id)")
        return id
    }

    private func waitForMeetJoinState() async throws {
        let stateScript = "(function(){return window.__MEETSCRIBE_GET_MEET_STATE ? window.__MEETSCRIBE_GET_MEET_STATE() : null;})()"
        var didRevealSignInWindow = false
        for attempt in 1...35 {
            let raw = try await pool.run(script: stateScript)
            let state = Self.meetStateDictionary(from: raw)
            let status = (state?["status"] as? String) ?? "unknown"
            let joined = (state?["joined"] as? Bool) ?? false
            let denied = (state?["denied"] as? Bool) ?? false
            let elapsed = (state?["elapsedMs"] as? Double) ?? 0
            let hint = (state?["hint"] as? String) ?? ""
            let lastAction = (state?["lastAction"] as? String) ?? ""
            let title = (state?["title"] as? String) ?? ""
            let url = (state?["url"] as? String) ?? ""
            let bodyProbe = (state?["bodyProbe"] as? String) ?? ""

            if attempt == 1 || attempt % 5 == 0 || joined || denied {
                AppTrace.log("joiner.meetState status=\(status) hint=\(hint) lastAction=\(lastAction) title=\(title) url=\(url) bodyProbe=\(bodyProbe) joined=\(joined) denied=\(denied) elapsedMs=\(Int(elapsed))")
            }

            if joined {
                return
            }
            if denied {
                pool.revealForManualSignIn()
                throw NSError(
                    domain: "MeetScribe",
                    code: 8,
                    userInfo: [NSLocalizedDescriptionKey: "Google Meet denied join access for this link"]
                )
            }
            if status == "auth-required" {
                if !didRevealSignInWindow {
                    didRevealSignInWindow = true
                    AppTrace.log("joiner.meetState auth-required; revealing bot window for manual sign-in")
                    pool.revealForManualSignIn()
                }
                try await Task.sleep(nanoseconds: 1_000_000_000)
                continue
            }
            if status == "browser-gate" {
                throw NSError(
                    domain: "MeetScribe",
                    code: 12,
                    userInfo: [NSLocalizedDescriptionKey: "Google Meet reported a browser compatibility gate"]
                )
            }
            if status == "invalid-link" {
                throw NSError(
                    domain: "MeetScribe",
                    code: 13,
                    userInfo: [NSLocalizedDescriptionKey: "Google Meet link appears invalid or unavailable"]
                )
            }
            if status == "timeout" || status == "timeout-waiting" {
                throw NSError(
                    domain: "MeetScribe",
                    code: 9,
                    userInfo: [NSLocalizedDescriptionKey: "Google Meet join timed out. Host approval may be required."]
                )
            }

            try await Task.sleep(nanoseconds: 1_000_000_000)
        }

        throw NSError(
            domain: "MeetScribe",
            code: 10,
            userInfo: [NSLocalizedDescriptionKey: "Unable to confirm Google Meet join state within timeout"]
        )
    }

    private static func meetStateDictionary(from value: Any?) -> [String: Any]? {
        if let dict = value as? [String: Any] {
            return dict
        }
        if let nsDict = value as? NSDictionary {
            var output: [String: Any] = [:]
            for (key, val) in nsDict {
                if let keyString = key as? String {
                    output[keyString] = val
                }
            }
            return output
        }
        return nil
    }

    var windowID: CGWindowID? {
        pool.windowID
    }

    private static func javascriptStringLiteral(_ string: String) -> String {
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }
}
