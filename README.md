# kiro-cli-rest-api

基于 Zig 实现的 Kiro CLI REST API 服务，按 AWS 原文里的“双通道架构”落地：

- 显式模型走 `kiro-cli chat`
- `model=auto` 和 `/sessions` 走 `kiro-cli acp`

项目集成了：

- 本地 `zig-logging` 运行日志
- 本地 `zig-release` 发布步骤

## Endpoints

- `GET /`
- `GET /healthz`
- `GET /models`
- `GET /sessions`
- `POST /sessions`
- `POST /sessions/{id}/prompt`
- `DELETE /sessions/{id}`
- `POST /prompt`

## 行为说明

### `POST /prompt`

- `model` 为显式模型时，走 Chat 通道
- `model` 为 `auto` 时，走 ACP 通道
- 若同时传 `session_id`，则按 ACP session 继续会话

示例：

```json
{
  "prompt": "帮我总结这个目录的代码结构",
  "model": "claude-sonnet-4.6",
  "cwd": "."
}
```

```json
{
  "prompt": "继续刚才的话题",
  "model": "auto",
  "session_id": "sess-1"
}
```

### `POST /sessions`

创建一个 ACP session，返回 REST session id。后续通过：

- `POST /sessions/{id}/prompt`
- `DELETE /sessions/{id}`

进行继续会话和删除本地映射。

## 项目结构

- `src/main.zig`: entrypoint and CLI args
- `src/server.zig`: TCP + HTTP server lifecycle
- `src/router.zig`: route dispatch
- `src/handlers.zig`: endpoint behavior
- `src/store.zig`: in-memory session store
- `src/backends.zig`: Chat backend execution
- `src/acp/transport.zig`: ACP 子进程与 JSON-RPC 传输
- `src/acp/client.zig`: ACP 高层调用
- `src/http_helpers.zig`: JSON response and body helpers
- `src/types.zig`: shared domain types

## 构建与测试

```bash
zig build
zig build test
```

## 运行

Windows 下如果默认 Zig cache 不可写，建议显式指定：

```powershell
$env:ZIG_GLOBAL_CACHE_DIR='E:\vscode\kiro-cli-dev\kiro-cli-rest-api\.zig-global-cache'
$env:ZIG_LOCAL_CACHE_DIR='E:\vscode\kiro-cli-dev\kiro-cli-rest-api\.zig-cache'
zig build run -- --port 8080 --kiro-cli kiro-cli --workspace-dir .
```

## WSL 运行

推荐把整个项目目录复制到 WSL 内运行，并确保：

- `kiro-cli` 已安装并可直接执行
- 当前目录对 `kiro-cli chat` 和 `kiro-cli acp` 都可用

示例：

```bash
cd ~/kiro-cli-rest-api
zig build run -- --port 8080 --kiro-cli kiro-cli --workspace-dir .
```

如果准备把项目交给下一个大模型在 WSL 中继续排障，先看：

- [docs/llm-handoff-runbook.md](E:\vscode\kiro-cli-dev\kiro-cli-rest-api\docs\llm-handoff-runbook.md)

## 发布

```bash
zig build release -- patch
zig build release -- minor
zig build release -- major
```

## 当前限制

- Session 映射当前只保存在内存里，进程重启后会丢失
- ACP 实现按文章行为做了 `initialize/session/new/session/load/session/prompt/session/update/session/request_permission` 的最小闭环，但仍应以你 WSL 环境中的真实 `kiro-cli` 输出继续验证
- Chat 输出清洗规则是按文章意图和通用 CLI 噪声收敛的，后续可以根据真实输出样本继续细化
