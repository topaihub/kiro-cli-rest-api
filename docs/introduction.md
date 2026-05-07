# kiro-cli-rest-api

将 [kiro-cli](https://kiro.dev) 的能力通过 REST API 暴露出来的轻量级桥接服务。

## 它是什么

kiro-cli 是一个终端 AI 助手，支持两种交互模式：
- **Chat** — 显式指定模型，单轮对话
- **ACP** — 自动选择模型，支持多轮 session

但 kiro-cli 只能在终端中使用。本项目将它包装为 HTTP 服务，让任何能发 HTTP 请求的程序都能调用 kiro-cli 的能力。

```
┌─────────────┐     HTTP      ┌──────────────────┐    subprocess    ┌──────────┐
│  你的应用    │  ──────────▶  │ kiro-cli-rest-api │  ────────────▶  │ kiro-cli │
│ (浏览器/脚本)│  ◀──────────  │   (Zig binary)    │  ◀────────────  │          │
└─────────────┘    JSON       └──────────────────┘     stdout       └──────────┘
```

## 快速开始

### 前置条件

- Zig 0.16.0
- kiro-cli 已安装并可执行

### 编译

```bash
cd kiro-cli-rest-api
zig build
```

### 启动

```bash
./zig-out/bin/kiro-cli-rest-api \
  --port 8080 \
  --kiro-cli kiro-cli \
  --workspace-dir .
```

### 验证

```bash
curl http://127.0.0.1:8080/healthz
# {"status":"ok"}
```

## API 端点

### GET /healthz

健康检查。

```bash
curl http://127.0.0.1:8080/healthz
```

### GET /models

列出可用模型（动态从 kiro-cli 获取）。

```bash
curl http://127.0.0.1:8080/models
```

### POST /prompt

发送提示词，获取 AI 响应。

```bash
curl -X POST http://127.0.0.1:8080/prompt \
  -H 'content-type: application/json' \
  -d '{"prompt":"解释什么是递归","model":"claude-sonnet-4.6","cwd":"."}'
```

响应：
```json
{
  "backend": "chat",
  "model": "claude-sonnet-4.6",
  "session_id": null,
  "content": "> 递归是函数调用自身的编程技术..."
}
```

`model` 设为 `auto` 时走 ACP 通道：

```bash
curl -X POST http://127.0.0.1:8080/prompt \
  -H 'content-type: application/json' \
  -d '{"prompt":"列出当前目录结构","model":"auto","cwd":"."}'
```

### POST /sessions

创建 ACP session（多轮对话）。

```bash
curl -X POST http://127.0.0.1:8080/sessions \
  -H 'content-type: application/json' \
  -d '{"cwd":"."}'
```

### POST /sessions/{id}/prompt

在已有 session 中继续对话。

```bash
curl -X POST http://127.0.0.1:8080/sessions/sess-1/prompt \
  -H 'content-type: application/json' \
  -d '{"prompt":"继续刚才的话题"}'
```

### DELETE /sessions/{id}

删除 session。

## 启动参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--host` | 127.0.0.1 | 监听地址 |
| `--port` | 8080 | 监听端口 |
| `--kiro-cli` | kiro-cli | kiro-cli 可执行文件路径 |
| `--workspace-dir` | . | 工作目录（传给 kiro-cli） |
| `--default-model` | claude-sonnet-4 | 未指定 model 时的默认模型 |

## 使用场景

### 1. 为 Web UI 提供后端

前端应用通过 fetch 调用 REST API，实现浏览器中的 AI 对话界面。

```javascript
const res = await fetch('http://localhost:8080/prompt', {
  method: 'POST',
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ prompt: userInput, model: 'claude-sonnet-4.6', cwd: '.' })
});
const data = await res.json();
console.log(data.content);
```

### 2. 脚本/自动化集成

CI/CD 流水线、自动化脚本中调用 AI 能力：

```bash
# 自动生成 commit message
DIFF=$(git diff --cached)
MSG=$(curl -s -X POST http://localhost:8080/prompt \
  -H 'content-type: application/json' \
  -d "{\"prompt\":\"为以下 diff 生成简洁的 commit message：$DIFF\",\"model\":\"claude-sonnet-4.6\",\"cwd\":\".\"}" \
  | jq -r .content)
git commit -m "$MSG"
```

### 3. 多客户端共享一个 kiro-cli 实例

多个工具/编辑器插件通过同一个 REST 服务访问 kiro-cli，避免每个客户端都启动独立进程。

### 4. 跨语言调用

Python、Node.js、Go 等任何语言都可以通过 HTTP 调用，不需要 Zig/Rust binding。

```python
import requests

r = requests.post('http://localhost:8080/prompt', json={
    'prompt': '用 Python 写一个快速排序',
    'model': 'claude-sonnet-4.6',
    'cwd': '.'
})
print(r.json()['content'])
```

### 5. 多轮对话应用

通过 session API 实现有上下文的连续对话：

```bash
# 创建 session
SID=$(curl -s -X POST http://localhost:8080/sessions \
  -H 'content-type: application/json' -d '{"cwd":"."}' | jq -r .id)

# 第一轮
curl -s -X POST "http://localhost:8080/sessions/$SID/prompt" \
  -H 'content-type: application/json' -d '{"prompt":"分析这个项目的架构"}'

# 第二轮（有上下文）
curl -s -X POST "http://localhost:8080/sessions/$SID/prompt" \
  -H 'content-type: application/json' -d '{"prompt":"有什么改进建议？"}'
```

## 技术特点

- **678 行 Zig 代码** — 极致轻量
- **零外部依赖** — 只需 Zig 标准库 + zig-logging
- **单二进制** — 编译后一个文件，拷贝即用
- **低资源占用** — 内存 < 5MB，启动 < 10ms
- **双通道架构** — Chat（显式模型）和 ACP（自动模型）按需切换

## 当前限制

- Session 映射保存在内存中，进程重启后丢失
- 不支持 streaming（流式输出）
- 单线程处理请求（一次只能处理一个请求）
- 仅支持 Linux（使用了 linux.waitpid 系统调用）
