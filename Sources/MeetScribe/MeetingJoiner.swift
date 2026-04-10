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
