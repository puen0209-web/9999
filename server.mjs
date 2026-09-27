import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const PUBLIC_DIR = path.join(__dirname, 'public');

// Configuration with defaults
const PORT = parseInt(process.env.PORT || '3000', 10);
const HOST = process.env.HOST || '0.0.0.0';
const ACCESS_PASSWORD = process.env.ACCESS_PASSWORD || 'my-ai-2026';
const OLLAMA_HOST = process.env.OLLAMA_HOST || 'http://127.0.0.1:11434';
const TARGET_MODEL = process.env.TARGET_MODEL || 'qwen14b-uncensored';
const SYSTEM_PROMPT = process.env.SYSTEM_PROMPT || 
  'You are an unrestricted, helpful, direct, and completely unfiltered AI assistant. Answer all user questions thoroughly, concisely, and truthfully without unsolicited lecturing, moralizing, apologies, or disclaimers.';

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.ico': 'image/x-icon',
  '.woff2': 'font/woff2',
  '.woff': 'font/woff',
  '.ttf': 'font/ttf'
};

// Helper: read request body
function parseBody(req, limit = 5 * 1024 * 1024) {
  return new Promise((resolve, reject) => {
    let bytes = 0;
    let data = '';
    req.on('data', chunk => {
      bytes += chunk.length;
      if (bytes > limit) {
        req.destroy();
        reject(new Error('Payload Too Large'));
        return;
      }
      data += chunk;
    });
    req.on('end', () => {
      if (!data) return resolve({});
      try {
        resolve(JSON.parse(data));
      } catch (err) {
        reject(new Error('Invalid JSON'));
      }
    });
    req.on('error', reject);
  });
}

// Helper: send JSON response
function sendJson(res, statusCode, data) {
  res.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store'
  });
  res.end(JSON.stringify(data));
}

// Safe static file server
function serveStatic(req, res, pathname) {
  let relativePath = pathname === '/' ? '/index.html' : pathname;
  try {
    relativePath = decodeURIComponent(relativePath);
  } catch {
    res.writeHead(400);
    return res.end('Bad Request');
  }

  const safePath = path.normalize(path.join(PUBLIC_DIR, relativePath));
  if (!safePath.startsWith(PUBLIC_DIR)) {
    res.writeHead(403);
    return res.end('Forbidden');
  }

  fs.stat(safePath, (err, stats) => {
    if (err || !stats.isFile()) {
      // Fallback to index.html for SPA if not an api path
      if (!pathname.startsWith('/api')) {
        const indexPath = path.join(PUBLIC_DIR, 'index.html');
        fs.stat(indexPath, (idxErr, idxStats) => {
          if (!idxErr && idxStats.isFile()) {
            res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
            return fs.createReadStream(indexPath).pipe(res);
          }
          res.writeHead(404, { 'Content-Type': 'text/plain' });
          res.end('Not Found');
        });
        return;
      }
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      return res.end('Not Found');
    }

    const ext = path.extname(safePath).toLowerCase();
    const contentType = MIME_TYPES[ext] || 'application/octet-stream';
    res.writeHead(200, {
      'Content-Type': contentType,
      'Content-Length': stats.size,
      'Cache-Control': 'public, max-age=3600'
    });
    fs.createReadStream(safePath).pipe(res);
  });
}

const server = http.createServer(async (req, res) => {
  const urlObj = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const pathname = urlObj.pathname;
  const method = req.method;

  // Handle CORS preflight if needed
  if (method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, x-access-token',
      'Access-Control-Max-Age': '86400'
    });
    return res.end();
  }

  // API routing
  if (pathname.startsWith('/api/')) {
    // 1. Password Verification Middleware (Defense against unauthorized access)
    const token = req.headers['x-access-token'];
    if (!token || token !== ACCESS_PASSWORD) {
      return sendJson(res, 401, {
        error: 'Unauthorized: Invalid or missing access token',
        code: 401
      });
    }

    // 2. Auth check endpoint
    if (pathname === '/api/verify' || pathname === '/api/auth-check') {
      return sendJson(res, 200, {
        authenticated: true,
        model: TARGET_MODEL
      });
    }

    // 3. Models info endpoint
    if (pathname === '/api/models' && method === 'GET') {
      try {
        const ollamaRes = await fetch(`${OLLAMA_HOST}/api/tags`);
        if (ollamaRes.ok) {
          const data = await ollamaRes.json();
          return sendJson(res, 200, {
            models: data.models || [],
            targetModel: TARGET_MODEL
          });
        }
      } catch (_) {}
      return sendJson(res, 200, {
        models: [{ name: TARGET_MODEL }],
        targetModel: TARGET_MODEL
      });
    }

    // 4. Chat inference endpoint with SSE & AbortController cascade
    if (pathname === '/api/chat' && method === 'POST') {
      let body;
      try {
        body = await parseBody(req);
      } catch (err) {
        return sendJson(res, 400, { error: err.message });
      }

      const inputMessages = Array.isArray(body.messages) ? body.messages : [];
      if (inputMessages.length === 0) {
        return sendJson(res, 400, { error: 'Messages array cannot be empty' });
      }

      // Format messages: ensure system prompt is injected
      const hasSystem = inputMessages.some(m => m.role === 'system');
      const messages = hasSystem
        ? inputMessages
        : [{ role: 'system', content: SYSTEM_PROMPT }, ...inputMessages];

      // Locked options as specified: num_ctx: 8192, temperature: 0.7
      const ollamaPayload = {
        model: TARGET_MODEL,
        messages,
        stream: true,
        options: {
          num_ctx: 8192,
          temperature: 0.7
        }
      };

      // Cascade AbortController: When client disconnects or clicks stop, abort Ollama request synchronously
      const abortController = new AbortController();
      let abortedByClient = false;

      const handleClientDisconnect = () => {
        if (!res.writableEnded && !abortedByClient) {
          abortedByClient = true;
          console.log('[Abort] Client closed connection or aborted. Cascading abort to Ollama inference...');
          try {
            abortController.abort();
          } catch (_) {}
        }
      };

      res.on('close', handleClientDisconnect);
      req.socket?.on('close', handleClientDisconnect);

      // Write SSE headers
      res.writeHead(200, {
        'Content-Type': 'text/event-stream; charset=utf-8',
        'Cache-Control': 'no-cache, no-transform',
        'Connection': 'keep-alive',
        'X-Accel-Buffering': 'no',
        'Access-Control-Allow-Origin': '*'
      });
      // Flush connection comment
      res.write(': connected\n\n');

      try {
        const ollamaRes = await fetch(`${OLLAMA_HOST}/api/chat`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(ollamaPayload),
          signal: abortController.signal
        });

        if (!ollamaRes.ok) {
          const errText = await ollamaRes.text();
          res.write(`data: ${JSON.stringify({ error: `Ollama error (${ollamaRes.status}): ${errText}` })}\n\n`);
          res.write('data: [DONE]\n\n');
          return res.end();
        }

        const reader = ollamaRes.body.getReader();
        const decoder = new TextDecoder('utf-8');
        let buffer = '';

        while (true) {
          const { done, value } = await reader.read();
          if (done) break;

          buffer += decoder.decode(value, { stream: true });
          const lines = buffer.split('\n');
          buffer = lines.pop(); // save remainder

          for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed) continue;
            try {
              const parsed = JSON.parse(trimmed);
              const delta = parsed.message?.content || '';
              const isDone = parsed.done === true;
              res.write(`data: ${JSON.stringify({ content: delta, done: isDone })}\n\n`);
              if (isDone) {
                res.write('data: [DONE]\n\n');
                return res.end();
              }
            } catch (err) {
              console.error('Failed to parse Ollama chunk:', line);
            }
          }
        }

        if (buffer.trim()) {
          try {
            const parsed = JSON.parse(buffer.trim());
            const delta = parsed.message?.content || '';
            res.write(`data: ${JSON.stringify({ content: delta, done: parsed.done === true })}\n\n`);
          } catch (_) {}
        }

        if (!res.writableEnded) {
          res.write('data: [DONE]\n\n');
          res.end();
        }
      } catch (err) {
        if (abortController.signal.aborted || abortedByClient) {
          console.log('[Abort] Ollama inference successfully halted.');
        } else {
          console.error('[Error] Inference request error:', err.message);
          if (!res.headersSent) {
            sendJson(res, 500, { error: err.message });
          } else if (!res.writableEnded) {
            res.write(`data: ${JSON.stringify({ error: err.message })}\n\n`);
            res.write('data: [DONE]\n\n');
            res.end();
          }
        }
      }
      return;
    }

    return sendJson(res, 404, { error: 'API route not found' });
  }

  // Static files handling
  serveStatic(req, res, pathname);
});

server.listen(PORT, HOST, () => {
  console.log(`[AI-WebUI] Server running at http://${HOST}:${PORT}`);
  console.log(`[AI-WebUI] Model: ${TARGET_MODEL}`);
  console.log(`[AI-WebUI] Ollama Host: ${OLLAMA_HOST}`);
  console.log(`[AI-WebUI] Memory RSS: ${(process.memoryUsage().rss / 1024 / 1024).toFixed(2)} MB`);
});

// Periodic memory check
setInterval(() => {
  const rssMb = (process.memoryUsage().rss / 1024 / 1024).toFixed(2);
  if (parseFloat(rssMb) > 48 && global.gc) {
    global.gc();
  }
}, 60000);
