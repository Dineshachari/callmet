# Meeting Bot Local Storage

This bundle runs the ScreenApp meeting bot in a lean local-first mode.
By default it writes recordings directly into `./recordings/` with no MinIO sidecars.

## Start

```bash
docker compose up -d
```

## Open

- Meeting bot: `http://localhost:3000`
## Verify

```bash
docker compose logs -f meeting-bot
find ./recordings -type f
```

## Optional Cloud-Compatible Mode (MinIO)

If you need to validate S3-compatible uploads locally:

```bash
mkdir -p data/minio
docker compose -f docker-compose.yml -f docker-compose.cloud-compat.yml up -d
```

This enables:

- MinIO API: `http://localhost:9000`
- MinIO console: `http://localhost:9001`

## Join A Meeting

This helper strips extra text around a pasted link, detects the platform, and sends the request to the correct local API route.

```bash
chmod +x join-meeting join-meeting.js

MEETING_BOT_BEARER_TOKEN=local-dev-token ./join-meeting "Join us here: https://meet.google.com/abc-defg-hij thanks!"
MEETING_BOT_BEARER_TOKEN=local-dev-token ./join-meeting "Zoom link: https://us06web.zoom.us/j/123456789?pwd=abc"
MEETING_BOT_BEARER_TOKEN=local-dev-token ./join-meeting "Teams: https://teams.microsoft.com/l/meetup-join/..."
```

Supported platforms:

- Google Meet
- Zoom
- Microsoft Teams

WhatsApp video links are detected, but this bot does not support them yet.

## Local Control Panel

This repo includes a local UI to:

- switch quality profile (`720p` / `1080p`)
- change recordings host destination path
- set bearer token
- submit meeting links directly to join

Run it with:

```bash
node control-panel.js
```

Then open:

- `http://localhost:3333`

Config changes update `.env` and rebuild/restart `meeting-bot`.

## Native macOS App (SwiftUI)

If you prefer a native app instead of a browser UI:

```bash
cd mac-app
swift run
```

The app provides:

- quality selection (`720p` / `1080p`)
- recording destination configuration
- bearer token configuration
- direct join by meeting link
- in-app logs and restart controls
