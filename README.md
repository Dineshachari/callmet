# MeetScribe

Source: [github.com/Dineshachari/callmet](https://github.com/Dineshachari/callmet) (repo name **callmet**).

**MeetScribe** is a native **macOS** menu bar app that **auto-detects upcoming meetings** from Calendar, **joins** Google Meet (and similar links) in a dedicated **WKWebView** window, and **records** that window with **ScreenCaptureKit** while mixing in **microphone** audio. Output is a **`.mov`** file (H.264 + AAC) under a user-chosen folder, plus optional hooks for post-processing.

## What it does (runtime flow)

1. **`MeetingScheduler`** reads **EventKit** for the next ~24 hours, finds conference URLs in event URL / location / notes via **`MeetingLinkParser`**, and posts a **`joinMeeting`** notification **two minutes** before start.
2. **`AppDelegate`** listens for **`joinMeeting`** and **`MeetingRequest`** and forwards to **`MeetingController`**.
3. **`MeetingController.startRecording`** checks **`Permissions`**, starts **`KeepAwake`**, then **`MeetingJoiner`** loads the meet URL in **`WebViewPool`**, injects **`join_meet.js`** or **`join_zoom.js`** (bundled resources) to drive the join UI and optionally waits until Meet reports “joined”.
4. **`WebViewPool`** exposes the hosting **`NSWindow`**’s ID as a **`CGWindowID`**. **`ScreenCaptureSession`** builds an **`SCContentFilter`** for that window, starts an **`SCStream`** at 1280×720 / 24 fps with **system audio** from the capture stream.
5. **`AudioMixer`** captures the **microphone** and forwards PCM as **`CMSampleBuffer`**s.
6. **`SegmentWriter`** (**`AVAssetWriter`**) muxes **video** (from screen samples), **system audio**, and **mic** into one **`.mov`**.
7. On stop, **`MeetingSessionLogger`** writes session metadata; **`TranscriptionService`** records paths for a future Whisper (or similar) step (currently a placeholder when not in Low Power / thermal stress).

Manual joins use the menu **“Join Meeting Link…”**, which builds a **`MeetingRequest`** the same way.

## How the code is organized

| File / type | Role |
|-------------|------|
| **`MeetScribeApp.swift`** | SwiftUI `@main` entry; **`AppDelegate`** builds the status item menu, starts/stops **`MeetingScheduler`**, handles permissions UI, wiring **`NotificationCenter`** for **`joinMeeting`**, **`captureStarted`**, **`captureStopped`**, and recording indicator timers. |
| **`MeetingController.swift`** | Orchestrates one active session: calls **`MeetingJoiner`**, starts **`SegmentWriter`**, **`AudioMixer`**, **`ScreenCaptureSession`**, tracks **`isRecording`**, and on stop finishes the writer and schedules transcription. |
| **`MeetingJoiner.swift`** | Creates/uses **`WebViewPool`**, loads URL, injects join script with **`__MEETSCRIBE_BOT_NAME__`** replaced from **`BotSettingsStore`**, polls Meet state for auth / denied / timeout, returns **`CGWindowID`**. |
| **`WebViewPool.swift`** | Holds borderless **`NSWindow`** + **`WKWebView`** (desktop UA, media autoplay), **`load`**, **`run(script:)`**, **`windowID`** for ScreenCaptureKit. |
| **`ScreenCaptureSession.swift`** | **`SCShareableContent`** lookup by window ID, **`SCStream`** with video + capture audio callbacks → **`onVideo`** / **`onAudio`**. |
| **`SegmentWriter.swift`** | **`AVAssetWriter`** pipeline: H.264 video, stereo AAC system audio, mono AAC mic; appends **`CMSampleBuffer`**s on a serial queue. |
| **`AudioMixer.swift`** | Microphone capture → **`onBuffer`** for the writer’s mic input. |
| **`MeetingScheduler.swift`** | **`EKEventStore`**, **`predicateForEvents`**, **`MeetingLinkParser`** on event fields, timer to fire **`joinMeeting`** 2 min before start, then reschedules. |
| **`MeetingLinkParser.swift`** | Extracts Meet / Zoom / Teams URLs from pasted or calendar text (used by UI and scheduler). |
| **`MeetingRequest.swift`** | Value type: URL, display name, optional start, source **scheduled** vs **manual**. |
| **`Permissions.swift`** | Calendar, microphone, screen recording snapshots, requests, diagnostics strings, “relaunch likely” heuristics for TCC. |
| **`OutputFolderStore.swift`** | Persists chosen recordings directory. |
| **`BotSettingsStore.swift`** | Persists bot display name for injected JS. |
| **`KeepAwake.swift`** | Prevents display sleep during recording. |
| **`MeetingSessionLogger.swift`** | Writes a sidecar log for the session after recording. |
| **`TranscriptionService.swift`** | Stores recording (and log) paths in **`UserDefaults`** for deferred transcription; **placeholder** async task for Whisper-class processing. |
| **`Package.swift`** | SwiftPM executable target **MeetScribe**, macOS 14+, processed **Resources/Assets**. |

Unit tests (e.g. **`MeetingLinkParserTests`**) live under **`Tests/MeetScribeTests/`**.

## Requirements

- **macOS 14+**
- **Xcode** (or Swift 5.10+) for local builds
- **Google Chrome** is *not* required for this pipeline; the bot uses **WebKit** inside the app.
- **Privacy**: Calendar, Microphone, and **Screen Recording** must be granted for scheduled joins and capture.

## Building

**Swift Package Manager**

```bash
swift build
swift run MeetScribe
```

**Xcode**

1. Open **`MeetScribe.xcodeproj`**.
2. Run the **MeetScribe** scheme on **My Mac**.

For distribution as an **`.app`**, use your existing archive / notarization flow; **`AppDelegate`** registers a login item via **`SMAppService`** when the bundle is an app.

## License

Add a **`LICENSE`** file when you publish; none is asserted here by default.

## Contributing

Issues and pull requests are welcome. For bugs, include **macOS version**, **MeetScribe build**, and whether the failure is join, permissions, or capture-related.
