# MeetScribe

**MeetScribe** is a native **macOS** menu bar app that records **Google Meet** sessions using a **headless Chrome** instance controlled from Swift via the **Chrome DevTools Protocol (CDP)**. The meeting tab is captured in the browser with **`getDisplayMedia`**; **WebM** chunks stream over a **local WebSocket** to the app, which pipes them to **ffmpeg** for recording.

## Highlights

- **SwiftUI** interface with a dark, minimal “ethereal” visual style (menu bar popover + optional dashboard window).
- **No ScreenCaptureKit** for this path: capture is browser-driven (`getDisplayMedia`) rather than system screen APIs.
- **Persistent Chrome profile** under Application Support so you can sign in to Google once (via a helper that opens visible Chrome with the same profile) and reuse sessions for headless recording.
- **Pipeline stages** surfaced in the UI: launch Chrome → CDP → join meeting → inject capture script → wait for stream → record.
- **Optional automation** for testing: environment variables can trigger self-tests or auto-join flows and log to `/tmp/meetscribe-selftest.log`.

## Requirements

- **macOS** (project targets Apple Silicon builds; use Xcode on a Mac).
- **Google Chrome** installed (the app resolves the standard Chrome bundle path).

## Building

1. Open **`MeetScribe.xcodeproj`** in Xcode.
2. Select the **MeetScribe** scheme and your Mac as the run destination.
3. **Product → Run** (⌘R).

Release archives and notarization are not documented here; follow your usual macOS distribution process if you ship outside the App Store.

## Architecture (summary)

| Layer | Role |
|--------|------|
| **Swift** | Launches Chrome with remote debugging, connects CDP WebSocket, injects JS, receives binary chunks. |
| **Chrome** | Loads the Meet URL; injected script starts tab capture and sends WebM over localhost. |
| **ffmpeg** | Reads WebM from stdin and muxes/writes the output file (bundled or supplied per your Xcode setup). |

## Repository layout (Swift sources)

Core types include `MeetScribeApp` (menu bar + dashboard host), `MeetScribeEngine` (state and coordinator wiring), `RecordingPipelineCoordinator`, `HeadlessChromeController`, `LocalWebSocketServer`, `FFmpegWriter`, and SwiftUI views such as `MenuBarView`, `DashboardWindowView`, and `SettingsDetailView`.

## License

Specify your license in a `LICENSE` file when you publish; none is bundled in this README by default.

## Contributing

Issues and pull requests are welcome. For bugs, include macOS version, Chrome version, and steps to reproduce.
