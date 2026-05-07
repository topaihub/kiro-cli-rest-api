# kiro-cli-rest-api

将 [kiro-cli](https://github.com/anthropics/kiro-cli) 的能力通过 REST API 暴露出来的轻量级桥接服务。基于 Zig 0.16.0 实现，单二进制，零外部依赖。

## 快速开始

### 1. 下载

从 [Releases](https://github.com/topaihub/kiro-cli-rest-api/releases) 页面下载对应平台的可执行文件：

| 平台 | 文件 |
|------|------|
| Linux x86_64 | `kiro-cli-rest-api-linux-x86_64` |
| Linux ARM64 | `kiro-cli-rest-api-linux-aarch64` |
| macOS Apple Silicon | `kiro-cli-rest-api-macos-aarch64` |
| macOS Intel | `kiro-cli-rest-api-macos-x86_64` |
| Windows x86_64 | `kiro-cli-rest-api-windows-x86_64.exe` |

下载后赋予执行权限（Linux/macOS）：

```bash
chmod +x kiro-cli-rest-api-linux-x86_64
```

### 2. 运行

前置条件：`kiro-cli` 已安装并可执行。

```bash
./kiro-cli-rest-api-linux-x86_64 --port 8080 --kiro-cli kiro-cli --workspace-dir .
```

### 3. 验证

```bash
curl http://127.0.0.1:8080/healthz
# {"status":"ok"}

curl http://127.0.0.1:8080/models
# 返回可用模型列表

curl -X POST http://127.0.0.1:8080/prompt \
  -H 'content-type: application/json' \
  -d '{"prompt":"hello","model":"claude-sonnet-4.6","cwd":"."}'
# {"backend":"chat","model":"claude-sonnet-4.6","session_id":null,"content":"> Hello!"}
```

### 从源码构建

```bash
# 需要 Zig 0.16.0
git clone https://github.com/topaihub/kiro-cli-rest-api.git
cd kiro-cli-rest-api
zig build
```

编译产物在 `zig-out/bin/kiro-cli-rest-api`。

## 启动参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--host` | 127.0.0.1 | 监听地址 |
| `--port` | 8080 | 监听端口 |
| `--kiro-cli` | kiro-cli | kiro-cli 可执行文件路径 |
| `--workspace-dir` | . | 工作目录 |
| `--default-model` | claude-sonnet-4 | 默认模型 |

## API

### GET /healthz

健康检查。

### GET /models

动态获取可用模型列表。

### POST /prompt

发送提示词，获取 AI 响应。

```json
{
  "prompt": "帮我总结这个目录的代码结构",
  "model": "claude-sonnet-4.6",
  "cwd": "."
}
```

`model` 设为 `auto` 时走 ACP 通道。

### POST /sessions

创建 ACP session（多轮对话）。

### POST /sessions/{id}/prompt

在已有 session 中继续对话。

### DELETE /sessions/{id}

删除 session。

## 架构

```
┌─────────────┐     HTTP      ┌──────────────────┐    subprocess    ┌──────────┐
│  你的应用    │  ──────────▶  │ kiro-cli-rest-api │  ────────────▶  │ kiro-cli │
│             │  ◀──────────  │   (Zig binary)    │  ◀────────────  │          │
└─────────────┘    JSON       └──────────────────┘     stdout       └──────────┘
```

双通道：
- **Chat** — 显式指定模型，单轮对话，走 `kiro-cli chat`
- **ACP** — `model=auto`，支持多轮 session，走 `kiro-cli acp`

## 项目结构

```
src/
  main.zig         — 入口，CLI 参数解析
  compat.zig       — 全局 IO 管理
  process.zig      — 子进程执行封装
  server.zig       — TCP + HTTP server
  router.zig       — 路由分发
  handlers.zig     — 端点逻辑
  backends.zig     — Chat 后端执行
  store.zig        — 内存 session 存储
  acp/             — ACP JSON-RPC 传输
```

## 发布新版本

```bash
zig build release -- patch   # 0.1.0 → 0.1.1
zig build release -- minor   # 0.1.0 → 0.2.0
zig build release -- major   # 0.1.0 → 1.0.0
```

推送 tag 后 GitHub Actions 自动构建多平台二进制并创建 Release。

## 文档

- [项目介绍与使用场景](docs/introduction.md)
- [Zig 0.16 踩坑指南](docs/zig-0.16-pitfalls.md)
- [从 nullclaw 学习与借鉴](docs/lessons-from-nullclaw.md)
- [WSL 运行指南](docs/wsl-run-guide.md)
- [LLM 交接手册](docs/llm-handoff-runbook.md)

## License

MIT
