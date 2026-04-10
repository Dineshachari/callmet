import AppKit
import ObjectiveC
import WebKit

@MainActor
final class WebViewPool {
    private(set) var window: NSWindow?
    private(set) var webView: WKWebView?

    func makeBotWindow() -> WKWebView {
        if let webView {
            return webView
        }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.mediaTypesRequiringUserActionForPlayback = []

        let prefs = WKWebpagePreferences()
        prefs.preferredContentMode = .desktop
        config.defaultWebpagePreferences = prefs

        let createdWebView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 1280, height: 720),
            configuration: config
        )
        createdWebView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Safari/605.1.15"
        createdWebView.navigationDelegate = createdWebView.coordinator

        let createdWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        createdWindow.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        createdWindow.isOpaque = false
        createdWindow.backgroundColor = .clear
        createdWindow.contentView = createdWebView
        createdWindow.isReleasedWhenClosed = false
        createdWindow.orderFrontRegardless()

        self.webView = createdWebView
        self.window = createdWindow

        injectMediaMock()
        return createdWebView
    }

    var windowID: CGWindowID? {
        guard let window, window.windowNumber > 0 else {
            return nil
        }
        return CGWindowID(window.windowNumber)
    }

    func load(_ url: URL) async throws {
        if webView == nil {
            _ = makeBotWindow()
        }
        guard let webView else { return }
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await webView.loadAsync(URLRequest(url: url))
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                throw NSError(domain: "MeetScribe", code: 6, userInfo: [NSLocalizedDescriptionKey: "Page load timed out after 30 seconds"])
            }
            try await group.next()
            group.cancelAll()
        }
    }

    func run(script: String) async throws -> Any? {
        guard let webView else {
            return nil
        }
        return try await webView.evaluateJavaScriptAsync(script)
    }

    func revealForManualSignIn() {
        guard let window else { return }
        window.level = .normal
        window.alphaValue = 1.0
        window.setFrame(NSRect(x: 120, y: 120, width: 1280, height: 720), display: true)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func injectMediaMock() {
        guard let webView else { return }
        let script = """
        Object.defineProperty(navigator, 'mediaDevices', {
          value: {
            getUserMedia: () => Promise.resolve(new MediaStream()),
            enumerateDevices: () => Promise.resolve([])
          }
        });
        """
        let userScript = WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        webView.configuration.userContentController.addUserScript(userScript)
    }
}

private final class WebViewNavigationCoordinator: NSObject, WKNavigationDelegate {
    var continuation: CheckedContinuation<Void, Error>?
}

private enum WebViewContextKey {
    static var coordinator = 0
}

private extension WKWebView {
    var coordinator: WebViewNavigationCoordinator {
        if let existing = objc_getAssociatedObject(self, &WebViewContextKey.coordinator) as? WebViewNavigationCoordinator {
            return existing
        }
        let coordinator = WebViewNavigationCoordinator()
        objc_setAssociatedObject(self, &WebViewContextKey.coordinator, coordinator, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return coordinator
    }

    func loadAsync(_ request: URLRequest) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let coordinator = self.coordinator
            coordinator.continuation = continuation
            self.navigationDelegate = coordinator
            _ = self.load(request)
        }
    }

    func evaluateJavaScriptAsync(_ script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: value)
                }
            }
        }
    }
}

extension WebViewNavigationCoordinator {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
