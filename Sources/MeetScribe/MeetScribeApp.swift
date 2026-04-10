import AppKit
import ServiceManagement
import SwiftUI

@main
struct MeetScribeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let scheduler = MeetingScheduler()
    private let controller = MeetingController()
    private let outputFolderStore = OutputFolderStore.shared
    private let botSettings = BotSettingsStore.shared
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var monitoringItem: NSMenuItem?
    private var stopRecordingItem: NSMenuItem?
    private var joinItem: NSMenuItem?
    private var botNameItem: NSMenuItem?
    private var botNameStatusItem: NSMenuItem?
    private var outputFolderItem: NSMenuItem?
    private var permissionsItem: NSMenuItem?
    private var screenRecordingSettingsItem: NSMenuItem?
    private var permissionDiagnosticsItem: NSMenuItem?
    private var observers: [NSObjectProtocol] = []
    private var isMonitoring = false
    private let didShowPermissionOnboardingKey = "com.dinesh.meetscribe.didShowPermissionOnboarding"
    private var recordingStartedAt: Date?
    private var recordingPulseVisible = true
    private var recordingIndicatorTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "MeetScribe"
        statusItem?.menu = makeMenu()

        startMonitoring()
        wireNotifications()
        wireLifecycleNotifications()
        registerLoginItemIfPossible()
        presentPermissionSetupIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        scheduler.stop()
        stopRecordingIndicatorUpdates()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    @objc private func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        scheduler.start()
        updateMenuState()
    }

    @objc private func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        scheduler.stop()
        updateMenuState()
    }

    @objc private func stopRecording() {
        Task { @MainActor in
            await controller.stopRecording()
        }
    }

    @objc private func openOutputFolder() {
        NSWorkspace.shared.open(outputFolderStore.recordingDirectoryURL())
    }

    @objc private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Output Folder"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = outputFolderStore.recordingDirectoryURL()

        guard panel.runModal() == .OK, let folderURL = panel.url else {
            return
        }

        outputFolderStore.selectedFolderURL = folderURL
        updateMenuState()
    }

    @objc private func joinMeetingLink() {
        let result = promptForMeetingLink()
        guard let result else {
            AppTrace.log("ui.joinMeetingLink cancelledOrInvalidInput")
            return
        }
        AppTrace.log("ui.joinMeetingLink submit url=\(result.url.absoluteString) name=\(result.meetingName)")
        Task { @MainActor in
            AppTrace.log("ui.joinMeetingLink dispatchToController")
            controller.joinManualMeeting(url: result.url, meetingName: result.meetingName)
        }
    }

    @objc private func setBotDisplayName() {
        let current = botSettings.displayName
        let result = promptForSingleValue(
            title: "Bot Display Name",
            message: "Choose the name that meeting apps should show for MeetScribe.",
            placeholder: "MeetScribe",
            defaultValue: current
        )

        guard let result else { return }
        botSettings.displayName = result
        updateMenuState()
    }

    @objc private func grantPermissions() {
        Task { @MainActor in
            await requestPermissionsAndMaybeShowAlert()
        }
    }

    @objc private func openScreenRecordingSystemSettings() {
        Permissions.openScreenRecordingPrivacyPane()
    }

    @objc private func showPermissionDiagnostics() {
        let bundle = Bundle.main
        let version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "?"
        let build = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "?"
        let bundleID = bundle.bundleIdentifier ?? "?"
        let executable = bundle.executableURL?.path ?? "?"

        let lines = Permissions.diagnosticsLines()
        let alert = NSAlert()
        alert.messageText = "Permission Diagnostics"
        alert.informativeText = """
        Version: \(version) (\(build))
        Bundle ID: \(bundleID)
        Executable: \(executable)

        \(lines.joined(separator: "\n"))
        """
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func wireNotifications() {
        let observer = NotificationCenter.default.addObserver(
            forName: .joinMeeting,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let meetingRequest = note.object as? MeetingRequest else { return }
            Task { @MainActor [weak self] in
                self?.controller.handle(meetingRequest: meetingRequest)
            }
        }
        observers.append(observer)

        let captureStartedObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("captureStarted"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.startRecordingIndicatorUpdates()
        }
        observers.append(captureStartedObserver)

        let captureObserver = NotificationCenter.default.addObserver(
            forName: .captureStopped,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.controller.stopRecording()
                self?.stopRecordingIndicatorUpdates()
                self?.updateMenuState()
            }
        }
        observers.append(captureObserver)
    }

    private func wireLifecycleNotifications() {
        let activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                _ = await Permissions.currentSnapshot()
                try? await Task.sleep(nanoseconds: 900_000_000)
                _ = await Permissions.currentSnapshot()
            }
        }
        observers.append(activeObserver)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let monitoring = NSMenuItem(title: "Start Monitoring", action: #selector(startMonitoring), keyEquivalent: "")
        monitoring.target = self
        menu.addItem(monitoring)
        monitoringItem = monitoring

        menu.addItem(.separator())

        let stopRecording = NSMenuItem(title: "Stop Recording", action: #selector(stopRecording), keyEquivalent: "")
        stopRecording.target = self
        menu.addItem(stopRecording)
        stopRecordingItem = stopRecording

        let join = NSMenuItem(title: "Join Meeting Link…", action: #selector(joinMeetingLink), keyEquivalent: "")
        join.target = self
        menu.addItem(join)
        joinItem = join

        let choose = NSMenuItem(title: "Choose Output Folder…", action: #selector(chooseOutputFolder), keyEquivalent: "")
        choose.target = self
        menu.addItem(choose)

        let folderStatus = NSMenuItem(title: "Output Folder: \(outputFolderStore.displayName())", action: nil, keyEquivalent: "")
        folderStatus.isEnabled = false
        menu.addItem(folderStatus)
        outputFolderItem = folderStatus

        let folder = NSMenuItem(title: "Open Output Folder", action: #selector(openOutputFolder), keyEquivalent: "")
        folder.target = self
        menu.addItem(folder)

        menu.addItem(.separator())

        let botName = NSMenuItem(title: "Bot Display Name…", action: #selector(setBotDisplayName), keyEquivalent: "")
        botName.target = self
        menu.addItem(botName)
        botNameItem = botName

        let botNameStatus = NSMenuItem(title: "Bot Name: \(botSettings.displayName)", action: nil, keyEquivalent: "")
        botNameStatus.isEnabled = false
        menu.addItem(botNameStatus)
        botNameStatusItem = botNameStatus

        let permissions = NSMenuItem(title: "Grant Permissions…", action: #selector(grantPermissions), keyEquivalent: "")
        permissions.target = self
        menu.addItem(permissions)
        permissionsItem = permissions

        let screenRecSettings = NSMenuItem(
            title: "Open Screen Recording Settings…",
            action: #selector(openScreenRecordingSystemSettings),
            keyEquivalent: ""
        )
        screenRecSettings.target = self
        menu.addItem(screenRecSettings)
        screenRecordingSettingsItem = screenRecSettings

        let diagnostics = NSMenuItem(
            title: "Permission Diagnostics…",
            action: #selector(showPermissionDiagnostics),
            keyEquivalent: ""
        )
        diagnostics.target = self
        menu.addItem(diagnostics)
        permissionDiagnosticsItem = diagnostics

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit MeetScribe", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        self.menu = menu
        updateMenuState()
        return menu
    }

    private func updateMenuState() {
        monitoringItem?.title = isMonitoring ? "Stop Monitoring" : "Start Monitoring"
        monitoringItem?.action = isMonitoring ? #selector(stopMonitoring) : #selector(startMonitoring)
        stopRecordingItem?.isEnabled = controller.isRecording
        joinItem?.isEnabled = true
        botNameItem?.isEnabled = true
        permissionsItem?.isEnabled = true
        screenRecordingSettingsItem?.isEnabled = true
        permissionDiagnosticsItem?.isEnabled = true
        statusItem?.button?.title = statusBarTitle()
        outputFolderItem?.title = "Output Folder: \(outputFolderStore.displayName())"
        botNameStatusItem?.title = "Bot Name: \(botSettings.displayName)"
    }

    private func startRecordingIndicatorUpdates() {
        if recordingStartedAt == nil {
            recordingStartedAt = Date()
        }
        recordingPulseVisible = true
        recordingIndicatorTimer?.invalidate()
        recordingIndicatorTimer = Timer.scheduledTimer(withTimeInterval: 0.85, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.recordingPulseVisible.toggle()
            self.updateMenuState()
        }
        if let recordingIndicatorTimer {
            RunLoop.main.add(recordingIndicatorTimer, forMode: .common)
        }
        updateMenuState()
    }

    private func stopRecordingIndicatorUpdates() {
        recordingIndicatorTimer?.invalidate()
        recordingIndicatorTimer = nil
        recordingStartedAt = nil
        recordingPulseVisible = true
    }

    private func statusBarTitle() -> String {
        if controller.isRecording {
            if recordingStartedAt == nil {
                recordingStartedAt = Date()
            }
            let dot = recordingPulseVisible ? "🔴" : "⚪"
            return "MeetScribe \(dot) \(recordingElapsedString())"
        }
        return isMonitoring ? "MeetScribe ●" : "MeetScribe ○"
    }

    private func recordingElapsedString() -> String {
        guard let recordingStartedAt else { return "00:00" }
        let elapsed = Int(Date().timeIntervalSince(recordingStartedAt))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func registerLoginItemIfPossible() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        _ = try? SMAppService.mainApp.register()
    }

    private func presentPermissionSetupIfNeeded() {
        Task { @MainActor in
            var snapshot = await Permissions.currentSnapshot()
            guard !snapshot.allGranted else {
                return
            }
            try? await Task.sleep(nanoseconds: 750_000_000)
            snapshot = await Permissions.currentSnapshot()

            let didShowOnboarding = UserDefaults.standard.bool(forKey: didShowPermissionOnboardingKey)
            if !didShowOnboarding {
                UserDefaults.standard.set(true, forKey: didShowPermissionOnboardingKey)
                await presentPermissionSetupBox(snapshot: snapshot)
                return
            }

            // After first run, avoid re-showing broad permission onboarding on every launch.
            // Only auto-present when there is still a promptable TCC state.
            let diagnostics = Permissions.diagnostics()
            let effective = Permissions.effectiveSnapshotForDiagnostics()
            let hasPromptableState = (!effective.calendarGranted && diagnostics.calendarStatus == "notDetermined")
                || (!effective.microphoneGranted && diagnostics.microphoneStatus == "notDetermined")
            if hasPromptableState {
                await presentPermissionSetupBox(snapshot: snapshot)
            }
        }
    }

    private func requestPermissionsAndMaybeShowAlert() async {
        let snapshot = await Permissions.stabilizedSnapshotForUI()
        if snapshot.allGranted {
            showPermissionsAlreadyGrantedBox()
            return
        }
        await presentPermissionSetupBox(snapshot: snapshot)
    }

    private func presentPermissionSetupBox(snapshot: PermissionSnapshot) async {
        // Always refresh right before rendering to avoid stale launch-time values.
        let liveSnapshot = await Permissions.stabilizedSnapshotForUI()
        if liveSnapshot.allGranted {
            showPermissionsAlreadyGrantedBox()
            return
        }

        let alert = NSAlert()
        alert.messageText = "MeetScribe needs permissions"
        if liveSnapshot.screenRecordingRelaunchLikely {
            alert.informativeText = "Calendar and Microphone are granted. Screen Recording is still not active for this running process. If MeetScribe is enabled in System Settings, fully quit and reopen."
            alert.addButton(withTitle: "Quit and Reopen")
            alert.addButton(withTitle: "Later")
        } else {
            alert.informativeText = "Grant access to Calendar, Microphone, and Screen Recording so MeetScribe can auto-join and record meetings."
            alert.addButton(withTitle: "Grant Permissions")
            alert.addButton(withTitle: "Later")
        }
        alert.accessoryView = makePermissionAccessoryView(snapshot: liveSnapshot)

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return
        }

        if liveSnapshot.screenRecordingRelaunchLikely {
            NSApp.terminate(nil)
            return
        }

        let after = await Permissions.requestMissingPermissions()
        showPermissionResultBox(snapshot: after)
    }

    private func showPermissionsAlreadyGrantedBox() {
        let alert = NSAlert()
        alert.messageText = "Permissions already granted"
        alert.informativeText = "Calendar, Microphone, and Screen Recording are already active for MeetScribe."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showPermissionResultBox(snapshot: PermissionSnapshot) {
        let alert = NSAlert()
        if snapshot.allGranted {
            alert.messageText = "Permissions granted"
            alert.informativeText = "MeetScribe now has Calendar, Microphone, and Screen Recording access."
        } else if snapshot.screenRecordingRelaunchLikely {
            alert.messageText = "Relaunch required for Screen Recording"
            alert.informativeText = "Calendar and Microphone are granted. Screen Recording appears enabled but is not active for this run. Fully quit and reopen MeetScribe."
        } else if snapshot.screenRecordingOnlyBlocker {
            alert.messageText = "Screen Recording still needs access"
            alert.informativeText = """
            macOS did not grant Screen Recording from the in-app request.
            We opened System Settings to Screen Recording. Enable MeetScribe there,
            then fully quit and reopen the app.
            """
        } else {
            alert.messageText = "Some permissions are still missing"
            alert.informativeText = """
            Open System Settings > Privacy & Security if macOS did not show a prompt.
            Then use Permission Diagnostics in the menu to verify exact raw states.
            """
        }
        alert.addButton(withTitle: "OK")
        alert.accessoryView = makePermissionAccessoryView(snapshot: snapshot)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func makePermissionAccessoryView(snapshot: PermissionSnapshot) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6

        for line in snapshot.summaryLines() {
            let label = NSTextField(labelWithString: line)
            label.font = .systemFont(ofSize: NSFont.systemFontSize)
            stack.addArrangedSubview(label)
        }

        stack.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 80))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private func promptForMeetingLink() -> (url: URL, meetingName: String)? {
        let alert = NSAlert()
        alert.messageText = "Join Meeting Link"
        alert.informativeText = "Paste the meeting link and an optional display name for the log."
        alert.addButton(withTitle: "Join")
        alert.addButton(withTitle: "Cancel")

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8

        let linkLabel = NSTextField(labelWithString: "Meeting link")
        let linkField = NSTextField(string: "")
        linkField.placeholderString = "https://meet.google.com/..."

        let nameLabel = NSTextField(labelWithString: "Meeting name")
        let nameField = NSTextField(string: "")
        nameField.placeholderString = "Optional"

        [linkLabel, linkField, nameLabel, nameField].forEach {
            if let field = $0 as? NSTextField, field.isEditable {
                field.translatesAutoresizingMaskIntoConstraints = false
            }
            stack.addArrangedSubview($0)
        }

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 120))
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        alert.accessoryView = container
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let rawLink = linkField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawLink.isEmpty else {
            AppTrace.log("ui.joinMeetingLink emptyURLField")
            return nil
        }

        let resolvedURL = MeetingLinkParser.extractMeetingURL(from: rawLink)
            ?? URL(string: rawLink)
            ?? URL(string: "https://\(rawLink)")

        guard let url = resolvedURL else {
            AppTrace.log("ui.joinMeetingLink invalidURL raw=\(rawLink)")
            let errorAlert = NSAlert()
            errorAlert.messageText = "Invalid meeting link"
            errorAlert.informativeText = "Paste a valid Google Meet, Zoom, or Teams link."
            errorAlert.runModal()
            return nil
        }

        let meetingName = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = meetingName.isEmpty ? (url.host ?? "Manual Meeting") : meetingName
        return (url: url, meetingName: resolvedName)
    }

    private func promptForSingleValue(title: String, message: String, placeholder: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(string: defaultValue)
        field.placeholderString = placeholder
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 32))
        container.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            field.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            field.topAnchor.constraint(equalTo: container.topAnchor),
            field.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        alert.accessoryView = container

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
