#!/usr/bin/env bash
# ==============================================================================
# AI-WebUI 一键全自动生产级部署脚本 (适用于 Debian / Ubuntu VPS)
# ==============================================================================
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}       🚀 AI-WebUI 极轻量级 WebAI 生产部署脚本         ${NC}"
echo -e "${BLUE}======================================================${NC}"

# 1. 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}[错误] 请使用 sudo 或 root 用户运行此脚本！${NC}"
  exit 1
fi

# 自动识别安装目录
if [ -f "$(pwd)/server.mjs" ]; then
  TARGET_DIR="$(pwd)"
elif [ -d "$HOME/ai-webui" ]; then
  TARGET_DIR="$HOME/ai-webui"
else
  TARGET_DIR="/root/ai-webui"
fi
PUBLIC_DIR="$TARGET_DIR/public"

# 2. 检查或安装 Node.js (>= 18)
echo -e "\n${YELLOW}[1/6] 检查 Node.js 运行环境...${NC}"
if ! command -v node &> /dev/null || [ $(node -v | cut -d'.' -f1 | tr -d 'v') -lt 18 ]; then
  echo -e "未检测到符合条件的 Node.js，正在自动安装 Node.js 22 LTS..."
  apt-get update -qq
  apt-get install -y -qq curl ca-certificates
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y -qq nodejs
fi
echo -e "${GREEN}✓ Node.js 版本: $(node -v)${NC}"

# 3. 检查 Ollama 服务连通性
echo -e "\n${YELLOW}[2/6] 检查本地 Ollama 服务...${NC}"
if curl -s http://127.0.0.1:11434/api/tags > /dev/null 2>&1; then
  echo -e "${GREEN}✓ Ollama 正在运行于 http://127.0.0.1:11434${NC}"
else
  echo -e "${YELLOW}[提示] 未检测到正在运行的 Ollama (127.0.0.1:11434)。如果尚未安装，可执行: curl -fsSL https://ollama.com/install.sh | sh${NC}"
fi

# 4. 创建部署目录
echo -e "\n${YELLOW}[3/6] 初始化工作目录: $TARGET_DIR ...${NC}"
mkdir -p "$PUBLIC_DIR"

# 5. 生成 package.json
cat << 'EOF' > "$TARGET_DIR/package.json"
{
  "name": "ai-webui",
  "version": "1.0.0",
  "description": "Production-grade ultra-lightweight Web AI chat application",
  "type": "module",
  "main": "server.mjs",
  "scripts": {
    "start": "node server.mjs"
  },
  "dependencies": {}
}
EOF

# 6. 生成 server.mjs
cat << 'EOF' > "$TARGET_DIR/server.mjs"
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const PUBLIC_DIR = path.join(__dirname, 'public');

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

function sendJson(res, statusCode, data) {
  res.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store'
  });
  res.end(JSON.stringify(data));
}

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

  if (method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, x-access-token',
      'Access-Control-Max-Age': '86400'
    });
    return res.end();
  }

  if (pathname.startsWith('/api/')) {
    const token = req.headers['x-access-token'];
    if (!token || token !== ACCESS_PASSWORD) {
      return sendJson(res, 401, {
        error: 'Unauthorized: Invalid or missing access token',
        code: 401
      });
    }

    if (pathname === '/api/verify' || pathname === '/api/auth-check') {
      return sendJson(res, 200, {
        authenticated: true,
        model: TARGET_MODEL
      });
    }

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

      const hasSystem = inputMessages.some(m => m.role === 'system');
      const messages = hasSystem
        ? inputMessages
        : [{ role: 'system', content: SYSTEM_PROMPT }, ...inputMessages];

      const ollamaPayload = {
        model: TARGET_MODEL,
        messages,
        stream: true,
        options: {
          num_ctx: 8192,
          temperature: 0.7
        }
      };

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

      res.writeHead(200, {
        'Content-Type': 'text/event-stream; charset=utf-8',
        'Cache-Control': 'no-cache, no-transform',
        'Connection': 'keep-alive',
        'X-Accel-Buffering': 'no',
        'Access-Control-Allow-Origin': '*'
      });
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
          buffer = lines.pop();

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

  serveStatic(req, res, pathname);
});

server.listen(PORT, HOST, () => {
  console.log(`[AI-WebUI] Server running at http://${HOST}:${PORT}`);
  console.log(`[AI-WebUI] Model: ${TARGET_MODEL}`);
  console.log(`[AI-WebUI] Ollama Host: ${OLLAMA_HOST}`);
  console.log(`[AI-WebUI] Memory RSS: ${(process.memoryUsage().rss / 1024 / 1024).toFixed(2)} MB`);
});

setInterval(() => {
  const rssMb = (process.memoryUsage().rss / 1024 / 1024).toFixed(2);
  if (parseFloat(rssMb) > 48 && global.gc) {
    global.gc();
  }
}, 60000);
EOF

# 7. 写入前端静态文件
cp "$(dirname "$0")/public/index.html" "$PUBLIC_DIR/index.html" 2>/dev/null || true
if [ ! -f "$PUBLIC_DIR/index.html" ]; then
  echo -e "${YELLOW}未检测到本地 index.html，正在从 GitHub 下载前端静态页面...${NC}"
  curl -fsSL https://raw.githubusercontent.com/puen0209-web/9999/main/public/index.html -o "$PUBLIC_DIR/index.html" || \
  wget -qO "$PUBLIC_DIR/index.html" https://raw.githubusercontent.com/puen0209-web/9999/main/public/index.html
fi

# 8. 配置 systemd 服务
echo -e "\n${YELLOW}[4/6] 配置 Systemd 守护服务...${NC}"
NODE_PATH=$(which node)
cat << EOF > /etc/systemd/system/ai-webui.service
[Unit]
Description=AI WebUI - Ultra Lightweight Web AI Chat Service
After=network.target ollama.service
Wants=ollama.service

[Service]
Type=simple
User=root
WorkingDirectory=$TARGET_DIR
ExecStart=$NODE_PATH --max-old-space-size=48 server.mjs
Restart=always
RestartSec=3
Environment=NODE_ENV=production
Environment=PORT=3000
Environment=HOST=0.0.0.0
Environment=ACCESS_PASSWORD=my-ai-2026
Environment=OLLAMA_HOST=http://127.0.0.1:11434
Environment=TARGET_MODEL=qwen14b-uncensored

# 内存硬约束保证
MemoryMax=50M
MemoryHigh=48M

[Install]
WantedBy=multi-user.target
EOF

# 9. 启动服务
echo -e "\n${YELLOW}[5/6] 重新加载并启动 ai-webui 服务...${NC}"
systemctl daemon-reload
systemctl enable ai-webui
systemctl restart ai-webui
sleep 2

# 10. 健康检查验证
echo -e "\n${YELLOW}[6/6] 验证服务端口与响应...${NC}"
if curl -s -I http://127.0.0.1:3000 | grep -q "200 OK"; then
  PUBLIC_IP=$(curl -s https://api.ipify.org || echo "YOUR_VPS_IP")
  echo -e "\n${GREEN}======================================================${NC}"
  echo -e "${GREEN}🎉 恭喜！AI-WebUI 生产服务已成功启动并就绪！${NC}"
  echo -e "${GREEN}======================================================${NC}"
  echo -e "🌐 本地访问地址: ${BLUE}http://127.0.0.1:3000${NC}"
  echo -e "🚀 公网访问地址: ${BLUE}http://${PUBLIC_IP}:3000${NC}"
  echo -e "🔑 访问授权密码: ${GREEN}my-ai-2026${NC}"
  echo -e "🤖 默认推理模型: ${GREEN}qwen14b-uncensored${NC}"
  echo -e "⚡ 常驻内存消耗: ${GREEN}< 50MB (极轻量级)${NC}"
  echo -e "\n常用管理命令:"
  echo -e "  查看服务状态: ${YELLOW}systemctl status ai-webui${NC}"
  echo -e "  查看运行日志: ${YELLOW}journalctl -u ai-webui -f${NC}"
  echo -e "  重启后台服务: ${YELLOW}systemctl restart ai-webui${NC}"
else
  echo -e "${RED}[错误] 服务未能成功响应 HTTP 200，请检查 journalctl -u ai-webui -n 30 日志。${NC}"
  exit 1
fi
