import Foundation
import WebKit

final class MeetingJoiner {
    private let pool = WebViewPool()

    func join(url: URL, botDisplayName: String) async throws -> CGWindowID {
        _ = pool.makeBotWindow()
        try await pool.load(url)
        try await Task.sleep(nanoseconds: 3_000_000_000)

        let resourceName = url.host?.contains("zoom") == true ? "join_zoom" : "join_meet"
        if let path = Bundle.main.path(forResource: resourceName, ofType: "js"),
           let script = try? String(contentsOfFile: path) {
            let injected = script.replacingOccurrences(
                of: "__MEETSCRIBE_BOT_NAME__",
                with: Self.javascriptStringLiteral(botDisplayName)
            )
            _ = try await pool.run(script: injected)
        }

        guard let id = pool.windowID else {
            throw NSError(domain: "MeetScribe", code: 4, userInfo: [NSLocalizedDescriptionKey: "No window ID available"])
        }
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
