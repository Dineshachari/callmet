const fs = require('node:fs');

const quality = (process.env.LOCAL_RECORDING_QUALITY || '1080p').toLowerCase();
const qualityProfiles = {
  '720p': { videoBitsPerSecond: 1800000, audioBitsPerSecond: 96000 },
  '1080p': { videoBitsPerSecond: 3500000, audioBitsPerSecond: 128000 },
};
const selectedProfile = qualityProfiles[quality] || qualityProfiles['1080p'];

const botPath = '/usr/src/app/dist/bots/GoogleMeetBot.js';
let s = fs.readFileSync(botPath, 'utf8');

// Keep the Google Meet join path snappier and more tolerant of UI changes.
s = s.replaceAll('waitFor({ timeout: 30000 })', 'waitFor({ timeout: 8000 })');
s = s.replace(/await this\.page\.waitForTimeout\(10000\);/g, 'await this.page.waitForTimeout(3000);');
s = s.replaceAll('await this.page.waitForTimeout(3000);', 'await this.page.waitForTimeout(1200);');
s = s.replace(
  "await this.page.getByRole('button', { name: 'Continue without microphone and camera' }).waitFor({ timeout: 8000 });",
  "await this.page.getByRole('button', { name: /Continue without microphone and camera/i }).waitFor({ timeout: 1500 });"
);
s = s.replace(
  "await this.page.getByRole('button', { name: 'Continue without microphone and camera' }).click();",
  "await this.page.getByRole('button', { name: /Continue without microphone and camera/i }).click({ timeout: 1500 });"
);
s = s.replace("}, this._logger, 1, 15000);", "}, this._logger, 1, 1500);");
s = s.replace(
  /await retryActionWithWait\(\n      'Waiting for the input field',\n      async \(\) => await this\.page\.waitForSelector\('input\[type="text"\]\[aria-label="Your name"\]', \{ timeout: 10000 \}\),\n      this\._logger,\n      3,\n      15000,/,
  `await retryActionWithWait(
      'Waiting for the input field',
      async () => {
        const selectors = [
          'input[type="text"][aria-label="Your name"]',
          'input[type="text"]',
          'input[aria-label*="name" i]',
          'input[placeholder*="name" i]',
        ];

        for (const selector of selectors) {
          try {
            await this.page.waitForSelector(selector, { timeout: 4000 });
            return;
          } catch (_) {
            // Try the next likely selector.
          }
        }

        throw new Error('Unable to find the name input');
      },
      this._logger,
      2,
      5000,`
);
s = s.replace(
  /await retryActionWithWait\(\n      'Clicking the "Ask to join" button',/,
  `await retryActionWithWait(
      'Clicking the "Ask to join" button',`
);
s = s.replace(
  /,\n      this\._logger,\n      3,\n      15000,\n      async \(\) => \{/,
  ',\n      this._logger,\n      2,\n      5000,\n      async () => {'
);
s = s.replace(
  "const button = await this.page.locator('button', { hasText: new RegExp(text.toLocaleLowerCase(), 'i') }).first();",
  `const roleButton = this.page.getByRole('button', { name: new RegExp(text, 'i') }).first();
                    const fallbackButton = this.page.locator('[role="button"]', { hasText: new RegExp(text, 'i') }).first();
                    const button = (await roleButton.count()) > 0 ? roleButton : fallbackButton;`
);
s = s.replace(
  "'button[aria-label=\"People\"]'",
  "'button[aria-label=\"People\"],button[aria-label^=\"People\"],button[aria-label*=\"participant\" i],button[aria-label*=\"people\" i],button[aria-label*=\"show everyone\" i]'"
);
s = s.replace(
  "'button[aria-label=\"Leave call\"]'",
  "'button[aria-label=\"Leave call\"],button[aria-label*=\"leave call\" i],button[aria-label*=\"end call\" i],button[data-tooltip*=\"Leave call\" i],button[data-tooltip*=\"End call\" i]'"
);
s = s.replaceAll("], { timeout: 5000 });", "], { timeout: 1500 });");
s = s.replace('                }, 20000);', '                }, 3000);');
s = s.replaceAll('{ timeout: 15000 }', '{ timeout: 4000 }');
s = s.replace(
  "if (typeof contributors === 'undefined') {\n                                    detectionFailures++;",
  `if (typeof contributors === 'undefined') {
                                    const bodyText = (document.body?.innerText || '').toLowerCase();
                                    if (bodyText.includes('has left the meeting') ||
                                        bodyText.includes("you're the only one here") ||
                                        bodyText.includes('you are the only one here')) {
                                        console.log('Detected lone participant state from Meet body text. Ending meeting.');
                                        loneTestDetectionActive = false;
                                        stopTheRecording();
                                        return;
                                    }
                                    detectionFailures++;`
);
s = s.replace('const maxDetectionFailures = 10;', 'const maxDetectionFailures = 4;');
s = s.replace(
  '                        }, 5000);\n                    }\n                    retryWithBackoff();',
  '                        }, 2000);\n                    }\n                    retryWithBackoff();'
);
s = s.replace(
  "if (detectionFailures >= maxDetectionFailures) {\n                                        console.log('Persistent detection failures:', { bodyText: `${document.body.innerText?.toString()}` });\n                                        loneTestDetectionActive = false;\n                                    }",
  "if (detectionFailures >= maxDetectionFailures) {\n                                        console.log('Persistent detection failures:', { bodyText: `${document.body.innerText?.toString()}` });\n                                        // Keep detection alive: UI labels can change mid-call and we still want to catch leave states.\n                                        detectionFailures = 0;\n                                    }"
);
s = s.replace(
  `// Fallback: Check for text that indicates we're in the call
                                            const bodyText = document.body.innerText;
                                            if (bodyText.includes('You have joined the call') ||
                                                bodyText.includes('other person in the call') ||
                                                bodyText.includes('people in the call')) {
                                                return true;
                                            }
                                            // Fallback: Check for Leave call button which indicates we're in a call
                                            const leaveCallButton = document.querySelector('button[aria-label="Leave call"]');
                                            if (leaveCallButton) {
                                                // If we have Leave call button AND no lobby mode text, we're likely in the call
                                                const hasLobbyText = bodyText.includes('Asking to join') ||
                                                    bodyText.includes('You\\'re the only one here');
                                                if (!hasLobbyText) {
                                                    return true;
                                                }
                                            }
                                            return false;`,
  `// Fallback: Check for text that indicates we're in the call
                                            const bodyText = (document.body?.innerText || '').toLowerCase();
                                            if (bodyText.includes('you have joined the call') ||
                                                bodyText.includes('other person in the call') ||
                                                bodyText.includes('people in the call') ||
                                                bodyText.includes('meeting tools') ||
                                                bodyText.includes('chat with everyone') ||
                                                bodyText.includes('press down arrow to open the hover tray')) {
                                                return true;
                                            }
                                            // Fallback: Check for modern leave/end-call controls that indicate we're in-call.
                                            const leaveCallButton = document.querySelector('button[aria-label*="leave call" i],button[aria-label*="end call" i],button[data-tooltip*="Leave call" i],button[data-tooltip*="End call" i]');
                                            if (leaveCallButton) {
                                                const hasLobbyText = bodyText.includes('asking to join') ||
                                                    bodyText.includes('ask to join') ||
                                                    bodyText.includes("you're the only one here");
                                                if (!hasLobbyText) {
                                                    return true;
                                                }
                                            }
                                            return false;`
);
s = s.replace(
  `const stream = await navigator.mediaDevices.getDisplayMedia({
                    video: true,`,
  `const stream = await navigator.mediaDevices.getDisplayMedia({
                    // Keep the source feed dimensions native to avoid viewport/framing crops.
                    video: true,`
);
s = s.replace(
  `// Check if we actually got audio tracks
                const audioTracks = stream.getAudioTracks();`,
  `const videoTrack = stream.getVideoTracks()[0];
                if (videoTrack) {
                    const videoSettings = videoTrack.getSettings();
                    console.log('Captured display track settings:', {
                        width: videoSettings.width,
                        height: videoSettings.height,
                        frameRate: videoSettings.frameRate,
                        displaySurface: videoSettings.displaySurface,
                    });
                }
                // Check if we actually got audio tracks
                const audioTracks = stream.getAudioTracks();
                if (audioTracks.length > 1) {
                    console.log('Multiple audio tracks detected in stream:', audioTracks.map((t) => t.label));
                }`
);
s = s.replace(
  'const mediaRecorder = new MediaRecorder(stream, { ...options });',
  `const mediaRecorder = new MediaRecorder(stream, {
                    ...options,
                    videoBitsPerSecond: ${selectedProfile.videoBitsPerSecond},
                    audioBitsPerSecond: ${selectedProfile.audioBitsPerSecond},
                });`
);
fs.writeFileSync(botPath, s);

const uploaderPath = '/usr/src/app/dist/middleware/disk-uploader.js';
let u = fs.readFileSync(uploaderPath, 'utf8');
const uploaderStart = u.indexOf('    async uploadRecordingToRemoteStorage(options) {');
const uploaderEnd = u.indexOf('}\nexports.default = DiskUploader;', uploaderStart);
if (uploaderStart === -1 || uploaderEnd === -1) {
  throw new Error('Unable to patch disk uploader for local recordings');
}
const uploaderReplacement = `    async uploadRecordingToRemoteStorage(options) {
        try {
            if (typeof options?.forceUpload === 'boolean') {
                this.forceUpload = options.forceUpload;
            }
            if (!await this.tempFileExists()) {
                throw new Error(\`Unable to access the temp recording file on disk: \${this._userId} \${this._botId}\`);
            }
            const goodToGo = await this.finalizeDiskWriting();
            if (this.forceUpload) {
                this._logger.info('Force upload is enabled. Ignoring disk writing check results...', { goodToGo });
            }
            else if (!goodToGo) {
                throw new Error(\`Unable to finalise the temp recording file: \${this._userId} \${this._botId}\`);
            }
            const localRecordingDir = process.env.LOCAL_RECORDINGS_DIR;
            if (localRecordingDir) {
                const filePath = DiskUploader.getFilePath(this._userId, this._tempFileId, this.fileExtension);
                const safeName = \`\${this._namePrefix} \${(0, datetime_1.getTimeString)(this._timezone, this._logger)}\${this.fileExtension}\`.replace(/[<>:"/\\\\|?*\\x00-\\x1F]/g, '_');
                const archiveDir = path_1.default.join(localRecordingDir, this._userId);
                await fs_1.promises.mkdir(archiveDir, { recursive: true });
                const archivePath = path_1.default.join(archiveDir, safeName);
                await fs_1.promises.copyFile(filePath, archivePath);
                this._logger.info(\`Recording saved to local storage: \${archivePath}\`, this._userId, this._teamId);
                await this.deleteTempFileAsync();
                return true;
            }
            let uploadResult = false;
            if (config_1.default.uploaderType === 'screenapp') {
                uploadResult = await this.uploadRecordingToScreenApp();
            }
            else if (config_1.default.uploaderType === 's3') {
                uploadResult = await this.uploadRecordingToObjectStorage();
            }
            else {
                throw new Error(\`Unsupported UPLOADER_TYPE configuration: \${config_1.default.uploaderType}\`);
            }
            await this.deleteTempFileAsync();
            if (uploadResult) {
                try {
                    const payload = {
                        recordingId: this.lastRecordingId ?? this._tempFileId,
                        meetingLink: this._meetingLink,
                        status: 'completed',
                        blobUrl: this.lastUploadedBlobUrl,
                        timestamp: new Date().toISOString(),
                        metadata: {
                            userId: this._userId,
                            teamId: this._teamId,
                            botId: this._botId,
                            contentType: this.contentType,
                            uploaderType: config_1.default.uploaderType,
                        },
                    };
                    await (0, notificationService_1.notifyRecordingCompleted)(payload, this._logger);
                }
                catch (notifyErr) {
                    this._logger.warn('Recording completed notification failed', notifyErr);
                }
            }
            return uploadResult;
        }
        catch (err) {
            this._logger.info('Unable to upload recording to server...', { error: err, userId: this._userId, teamId: this._teamId });
            return false;
        }
    }`;
u = u.slice(0, uploaderStart) + uploaderReplacement + u.slice(uploaderEnd);
fs.writeFileSync(uploaderPath, u);
