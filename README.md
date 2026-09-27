# ⚡ AI-WebUI - 生产级极轻量 Web AI 聊天应用

仿 ChatGPT / Claude 的全栈极简 Web 界面，专为 Linux VPS 及资源受限环境打造。与本地 Ollama 服务无缝集成，默认支持 `qwen14b-uncensored` 等开源大模型。

---

## 🎯 核心架构与特性

- 🚀 **极低常驻内存（< 50MB）**：采用原生 Node.js HTTP 单进程设计，零重型 npm 依赖包，启动常驻物理内存仅约 **15MB ~ 40MB**，绝不与 14B / 32B 大模型抢占关键系统内存。
- ⚡ **AbortController 级联中止**：前端点击“停止生成”或关闭网页时，后端通过 `AbortController` **毫秒级同步切断与 Ollama 的推理连接**，立即停止 VPS 的 CPU/GPU 计算，防止资源空耗。
- 🛡️ **公网防盗刷安全鉴权**：接口强制校验 `x-access-token` 请求头，未授权直接返回 `401 Unauthorized`，密码可通过环境变量随时自定义。
- 🔒 **模型参数与窗口锁定**：默认锁定 `options: { num_ctx: 8192, temperature: 0.7 }`，防止窗口回退导致长对话失忆；内置无限制 System Prompt 注入。
- 🎨 **ChatGPT 级暗黑主题**：基于 Tailwind CSS、Marked.js、Highlight.js 与 KaTeX，原生支持 Markdown 表格、引用、数学公式解析与代码块“一键复制”。
- 📱 **移动端全视口适配**：适配移动端视口（`100dvh`），键盘弹出不遮挡输入栏；多会话本地 `localStorage` 持久化，无需依赖数据库。

---

## 📁 目录结构

```text
ai-webui/
├── deploy-vps.sh           # 🚀 一键全自动生产部署脚本 (支持 Debian / Ubuntu)
├── ai-webui.service        # Systemd 开机自启服务配置 (含 MemoryMax=50M 隔离)
├── package.json            # 极简配置 (type: module)
├── server.mjs              # 后端单进程入口 (SSE 流式转发、鉴权、级联中止)
└── public/
    └── index.html          # 单页应用 (Tailwind CSS, Marked, Highlight.js, KaTeX)
```

---

## ⚡ 极简【一键全自动部署】（Linux VPS）

### 1. 将项目上传至 VPS
在本地终端或使用 SCP 将目录传至 VPS 的 `/root/ai-webui`：
```bash
scp -r ai-webui root@<你的VPS_IP>:/root/
```

### 2. 在 VPS 执行一键部署
```bash
cd /root/ai-webui
chmod +x deploy-vps.sh
bash deploy-vps.sh
```

> **该脚本自动完成**：Node.js 环境检测与自动补齐、目录权限配置、systemd 守护进程注册、开机自启、`curl -I` 端口健康探测与公网访问地址输出！

---

## 🛠️ 手动部署步骤

如果你希望手动配置：

### 1. 确保安装 Node.js (>= 18)
```bash
# Ubuntu / Debian
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs
```

### 2. 注册并启动 Systemd 服务
```bash
cp ai-webui.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now ai-webui
```

### 3. 验证服务运行
```bash
curl -I http://127.0.0.1:3000
```
返回 `HTTP/1.1 200 OK` 即表示部署成功！

---

## ⚙️ 环境变量配置说明

可在 `/etc/systemd/system/ai-webui.service` 中的 `Environment=` 修改以下参数：

| 环境变量 | 默认值 | 说明 |
| :--- | :--- | :--- |
| `PORT` | `3000` | Web 服务监听端口 |
| `HOST` | `0.0.0.0` | 监听地址（绑定 `0.0.0.0` 允许公网/局域网访问） |
| `ACCESS_PASSWORD`| `my-ai-2026` | 访问鉴权密码（请求头 `x-access-token`） |
| `OLLAMA_HOST` | `http://127.0.0.1:11434`| 本地 Ollama 服务接口地址 |
| `TARGET_MODEL` | `qwen14b-uncensored` | 默认调用的目标大模型 |

修改后执行生效：
```bash
sudo systemctl daemon-reload && sudo systemctl restart ai-webui
```

---

## 📋 常用运维命令

```bash
# 查看后台服务状态与内存占用
systemctl status ai-webui

# 查看实时推理与中止日志
journalctl -u ai-webui -f

# 重启 Web 服务
systemctl restart ai-webui

# 停止 Web 服务
systemctl stop ai-webui
```
