#!/usr/bin/env node

const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const { exec } = require('node:child_process');

const ROOT = __dirname;
const ENV_PATH = path.join(ROOT, '.env');
const HTML_PATH = path.join(ROOT, 'control-panel.html');
const PORT = Number(process.env.CONTROL_PANEL_PORT || 3333);

function parseEnv(text) {
  const out = {};
  for (const rawLine of text.split('\n')) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const idx = line.indexOf('=');
    if (idx === -1) continue;
    out[line.slice(0, idx)] = line.slice(idx + 1);
  }
  return out;
}

function serializeEnv(previousText, updates) {
  const lines = previousText.split('\n');
  const seen = new Set();
  const updated = lines.map((line) => {
    const idx = line.indexOf('=');
    if (idx <= 0 || line.trim().startsWith('#')) return line;
    const key = line.slice(0, idx);
    if (Object.prototype.hasOwnProperty.call(updates, key)) {
      seen.add(key);
      return `${key}=${updates[key]}`;
    }
    return line;
  });
  for (const [key, value] of Object.entries(updates)) {
    if (!seen.has(key)) updated.push(`${key}=${value}`);
  }
  return `${updated.join('\n').replace(/\n+$/g, '')}\n`;
}

function run(cmd) {
  return new Promise((resolve, reject) => {
    exec(cmd, { cwd: ROOT }, (err, stdout, stderr) => {
      if (err) return reject(new Error(stderr || err.message));
      resolve(stdout);
    });
  });
}

async function handleApi(req, res) {
  if (req.url === '/api/config' && req.method === 'GET') {
    const envText = fs.readFileSync(ENV_PATH, 'utf8');
    const env = parseEnv(envText);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(
      JSON.stringify(
        {
          quality: env.LOCAL_RECORDING_QUALITY || '1080p',
          recordingsHostDir: env.LOCAL_RECORDINGS_HOST_DIR || './recordings',
          recordingsContainerDir: env.LOCAL_RECORDINGS_DIR || '/recordings',
          botBearerToken: env.MEETING_BOT_BEARER_TOKEN || 'local-dev-token',
        },
        null,
        2
      )
    );
    return;
  }

  if (req.url === '/api/config' && req.method === 'POST') {
    let body = '';
    req.on('data', (chunk) => (body += chunk));
    req.on('end', async () => {
      try {
        const payload = JSON.parse(body || '{}');
        const quality = payload.quality === '720p' ? '720p' : '1080p';
        const recordingsHostDir = (payload.recordingsHostDir || './recordings').trim();
        const recordingsContainerDir = (payload.recordingsContainerDir || '/recordings').trim();
        const botBearerToken = (payload.botBearerToken || 'local-dev-token').trim();
        if (!recordingsHostDir) throw new Error('Recordings host directory is required');
        if (!recordingsContainerDir.startsWith('/')) throw new Error('Container dir must be absolute');

        const envText = fs.readFileSync(ENV_PATH, 'utf8');
        const nextEnv = serializeEnv(envText, {
          LOCAL_RECORDING_QUALITY: quality,
          LOCAL_RECORDINGS_HOST_DIR: recordingsHostDir,
          LOCAL_RECORDINGS_DIR: recordingsContainerDir,
          MEETING_BOT_BEARER_TOKEN: botBearerToken,
        });
        fs.writeFileSync(ENV_PATH, nextEnv);
        await run('docker compose up -d --build meeting-bot');

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: true }));
      } catch (error) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: false, error: String(error.message || error) }));
      }
    });
    return;
  }

  if (req.url === '/api/join' && req.method === 'POST') {
    let body = '';
    req.on('data', (chunk) => (body += chunk));
    req.on('end', async () => {
      try {
        const payload = JSON.parse(body || '{}');
        const link = (payload.link || '').trim();
        if (!/^https?:\/\//i.test(link)) throw new Error('Please provide a full meeting URL');
        const envText = fs.readFileSync(ENV_PATH, 'utf8');
        const env = parseEnv(envText);
        const token = env.MEETING_BOT_BEARER_TOKEN || 'local-dev-token';
        const cmd = `MEETING_BOT_BEARER_TOKEN=${JSON.stringify(token)} ./join-meeting ${JSON.stringify(link)}`;
        const output = await run(cmd);
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: true, output }));
      } catch (error) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: false, error: String(error.message || error) }));
      }
    });
    return;
  }

  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ ok: false, error: 'Not found' }));
}

const server = http.createServer(async (req, res) => {
  if (req.url?.startsWith('/api/')) return handleApi(req, res);
  if (req.url === '/' || req.url === '/index.html') {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(fs.readFileSync(HTML_PATH, 'utf8'));
    return;
  }
  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('Not found');
});

server.listen(PORT, () => {
  console.log(`Control panel running at http://localhost:${PORT}`);
});
