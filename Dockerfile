FROM ghcr.io/screenappai/meeting-bot:sha-8b385c0

USER root

ARG LOCAL_RECORDING_QUALITY=1080p
ENV LOCAL_RECORDING_QUALITY=${LOCAL_RECORDING_QUALITY}

COPY patches/patch-meeting-bot.js /tmp/patch-meeting-bot.js
RUN node /tmp/patch-meeting-bot.js && rm -f /tmp/patch-meeting-bot.js

USER 1001:1001
