#!/usr/bin/env node

const { stdin, argv, env, exit } = require('node:process');

const BOT_BASE_URL = (env.MEETING_BOT_URL || 'http://localhost:3000').replace(/\/+$/, '');
const BEARER_TOKEN = env.MEETING_BOT_BEARER_TOKEN || 'local-dev-token';
const NAME = env.MEETING_BOT_NAME || 'Meeting Notetaker';
const TEAM_ID = env.MEETING_BOT_TEAM_ID || 'local';
const USER_ID = env.MEETING_BOT_USER_ID || 'local-user';
const BOT_ID = env.MEETING_BOT_BOT_ID || `bot-${Date.now()}-${Math.random().toString(16).slice(2, 8)}`;
const TIMEZONE = env.MEETING_BOT_TIMEZONE || 'UTC';

function readAllInput() {
  const args = argv.slice(2).join(' ').trim();
  if (args) return Promise.resolve(args);

  return new Promise((resolve) => {
    let data = '';
    stdin.setEncoding('utf8');
    stdin.on('data', (chunk) => {
      data += chunk;
    });
    stdin.on('end', () => resolve(data.trim()));
  });
}

function cleanCandidate(candidate) {
  return candidate
    .trim()
    .replace(/^[(<\[]+/, '')
    .replace(/[)>.,;:!?\"\]\}]+$/g, '');
}

function detectPlatform(url) {
  const parsed = new URL(url);
  const host = parsed.hostname.toLowerCase();
  const path = parsed.pathname.toLowerCase();

  if (host === 'meet.google.com' || host.endsWith('.meet.google.com')) {
    return { platform: 'google', endpoint: '/google/join' };
  }

  if (host === 'zoom.us' || host.endsWith('.zoom.us') || host === 'zoom.com' || host.endsWith('.zoom.com')) {
    return { platform: 'zoom', endpoint: '/zoom/join' };
  }

  if (host === 'teams.microsoft.com' || host.endsWith('.teams.microsoft.com')) {
    return { platform: 'microsoft', endpoint: '/microsoft/join' };
  }

  if (host.includes('whatsapp.com') || host === 'wa.me' || path.includes('whatsapp')) {
    return { platform: 'whatsapp', unsupported: true };
  }

  return { platform: 'unknown', unsupported: true };
}

function extractSupportedUrl(text) {
  const candidates = [];
  const patterns = [
    /https?:\/\/[^\s<>"'`]+/gi,
    /\b(?:www\.)?meet\.google\.com\/[^\s<>"'`]+/gi,
    /\b(?:[\w-]+\.)?zoom\.us\/[^\s<>"'`]+/gi,
    /\bteams\.microsoft\.com\/[^\s<>"'`]+/gi,
    /\b(?:www\.)?(?:wa\.me|whatsapp\.com)\/[^\s<>"'`]+/gi,
  ];

  for (const pattern of patterns) {
    let match;
    while ((match = pattern.exec(text)) !== null) {
      let candidate = cleanCandidate(match[0]);
      if (!/^https?:\/\//i.test(candidate)) {
        candidate = `https://${candidate}`;
      }
      candidates.push(candidate);
    }
  }

  for (const candidate of candidates) {
    try {
      const { platform, unsupported } = detectPlatform(candidate);
      if (!unsupported && platform) {
        return { url: candidate, ...detectPlatform(candidate) };
      }
    } catch {
      // Ignore malformed candidates and keep searching.
    }
  }

  if (candidates.length > 0) {
    const candidate = candidates[0];
    try {
      return { url: candidate, ...detectPlatform(candidate) };
    } catch {
      return { url: candidate, platform: 'unknown', unsupported: true };
    }
  }

  return null;
}

async function main() {
  const input = await readAllInput();
  if (!input) {
    console.error('Usage: ./join-meeting.js "paste a meeting link or text"');
    exit(1);
  }

  const extracted = extractSupportedUrl(input);
  if (!extracted) {
    console.error('No meeting link found in the provided text.');
    exit(1);
  }

  if (extracted.unsupported) {
    console.error(`Unsupported meeting platform: ${extracted.platform}`);
    console.error(`Extracted link: ${extracted.url}`);
    console.error('Supported platforms: Google Meet, Zoom, Microsoft Teams.');
    exit(2);
  }

  const body = {
    bearerToken: BEARER_TOKEN,
    url: extracted.url,
    name: NAME,
    teamId: TEAM_ID,
    timezone: TIMEZONE,
    userId: USER_ID,
    botId: BOT_ID,
  };

  console.log(`Platform: ${extracted.platform}`);
  console.log(`Clean URL: ${extracted.url}`);
  console.log(`Endpoint: ${BOT_BASE_URL}${extracted.endpoint}`);

  let response;
  try {
    response = await fetch(`${BOT_BASE_URL}${extracted.endpoint}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    });
  } catch (error) {
    console.error(`Request failed: ${error instanceof Error ? error.message : String(error)}`);
    exit(1);
  }

  const text = await response.text();
  const contentType = response.headers.get('content-type') || '';

  if (!response.ok) {
    console.error(`Request failed with HTTP ${response.status}`);
    console.error(text);
    exit(1);
  }

  if (contentType.includes('application/json')) {
    try {
      console.log(JSON.stringify(JSON.parse(text), null, 2));
      return;
    } catch {
      // Fall through to plain text output.
    }
  }

  console.log(text);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  exit(1);
});
