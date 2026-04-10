import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published var quality: String = "1080p"
    @Published var hostDir: String = "./recordings"
    @Published var containerDir: String = "/recordings"
    @Published var bearerToken: String = "local-dev-token"
    @Published var meetingLink: String = ""
    @Published var busy: Bool = false
    @Published var status: String = "Ready."
    @Published var logs: String = ""

    private let envFile = ".env"
    private var projectRoot: URL {
        // Package runs from mac-app/, so parent is repo root.
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath).deletingLastPathComponent()
    }

    init() {
        Task {
            await loadEnv()
        }
    }

    func loadEnv() async {
        do {
            let envURL = projectRoot.appendingPathComponent(envFile)
            let text = try String(contentsOf: envURL, encoding: .utf8)
            let map = parseEnv(text)
            quality = (map["LOCAL_RECORDING_QUALITY"] == "720p") ? "720p" : "1080p"
            hostDir = map["LOCAL_RECORDINGS_HOST_DIR"] ?? "./recordings"
            containerDir = map["LOCAL_RECORDINGS_DIR"] ?? "/recordings"
            bearerToken = map["MEETING_BOT_BEARER_TOKEN"] ?? "local-dev-token"
            status = "Loaded environment."
        } catch {
            status = "Unable to load .env: \(error.localizedDescription)"
        }
    }

    func saveConfigAndRestart() async {
        await runBusy("Saving config and rebuilding bot...") { [self] in
            let envURL = self.projectRoot.appendingPathComponent(self.envFile)
            let current = (try? String(contentsOf: envURL, encoding: .utf8)) ?? ""
            let updated = self.upsertEnv(in: current, updates: [
                "LOCAL_RECORDING_QUALITY": self.quality,
                "LOCAL_RECORDINGS_HOST_DIR": self.hostDir,
                "LOCAL_RECORDINGS_DIR": self.containerDir,
                "MEETING_BOT_BEARER_TOKEN": self.bearerToken
            ])
            try updated.write(to: envURL, atomically: true, encoding: .utf8)

            let output = try await self.runShell(
                command: "docker compose up -d --build meeting-bot",
                workingDirectory: self.projectRoot
            )
            self.appendLogs(output)
            self.status = "Config saved and bot restarted."
        }
    }

    func joinMeeting() async {
        await runBusy("Submitting join request...") { [self] in
            let trimmed = self.meetingLink.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else {
                throw AppError("Please enter a full meeting URL.")
            }
            let safeToken = self.shellEscape(self.bearerToken)
            let safeLink = self.shellEscape(trimmed)
            let cmd = "MEETING_BOT_BEARER_TOKEN=\(safeToken) ./join-meeting \(safeLink)"
            let output = try await self.runShell(command: cmd, workingDirectory: self.projectRoot)
            self.appendLogs(output)
            self.status = "Join request sent."
        }
    }

    func refreshLogs() async {
        await runBusy("Refreshing logs...") { [self] in
            let output = try await self.runShell(
                command: "docker compose logs --no-color --tail=120 meeting-bot",
                workingDirectory: self.projectRoot
            )
            self.logs = output
            self.status = "Logs refreshed."
        }
    }

    // MARK: - Helpers

    private func runBusy(_ message: String, operation: @escaping () async throws -> Void) async {
        busy = true
        status = message
        do {
            try await operation()
        } catch {
            status = "Failed: \(error.localizedDescription)"
            appendLogs("ERROR: \(error.localizedDescription)\n")
        }
        busy = false
    }

    private func appendLogs(_ text: String) {
        if logs.isEmpty {
            logs = text
        } else {
            logs += "\n\(text)"
        }
    }

    private func parseEnv(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let idx = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<idx])
            let value = String(line[line.index(after: idx)...])
            out[key] = value
        }
        return out
    }

    private func upsertEnv(in source: String, updates: [String: String]) -> String {
        var seen = Set<String>()
        var lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for i in lines.indices {
            let line = lines[i]
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("#") { continue }
            guard let idx = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<idx])
            if let newValue = updates[key] {
                lines[i] = "\(key)=\(newValue)"
                seen.insert(key)
            }
        }
        for (k, v) in updates where !seen.contains(k) {
            lines.append("\(k)=\(v)")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
    }

    private func shellEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(escaped)'"
    }

    private func runShell(command: String, workingDirectory: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            process.currentDirectoryURL = workingDirectory

            let out = Pipe()
            let err = Pipe()
            process.standardOutput = out
            process.standardError = err

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            process.terminationHandler = { proc in
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                let errData = err.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: outData, encoding: .utf8) ?? ""
                let stderr = String(data: errData, encoding: .utf8) ?? ""
                let combined = "\(stdout)\(stderr)"
                if proc.terminationStatus == 0 {
                    continuation.resume(returning: combined)
                } else {
                    continuation.resume(throwing: AppError(combined.isEmpty ? "Command failed." : combined))
                }
            }
        }
    }
}

private struct AppError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
