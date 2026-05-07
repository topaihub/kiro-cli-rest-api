# LLM Handoff Runbook

本文档不是功能介绍，而是给下一位大模型直接接手调试和修复用的运行手册。

适用场景：

- 用户已经把项目放进 WSL
- 用户已经安装好 `kiro-cli`
- 运行时出现错误，需要大模型继续修

---

## 1. 目标

本项目的目标是把 Kiro CLI 按 AWS 原文里的双通道架构封装成 REST API：

- 显式模型 -> `kiro-cli chat`
- `model=auto` -> `kiro-cli acp`
- `/sessions` -> ACP 会话

当前实现已经完成了：

- Chat 子进程调用
- ACP 子进程调用
- Session store
- REST API 路由
- 基本日志

当前最可能出问题的地方不是 HTTP 层，而是：

1. `kiro-cli chat` 真实参数与假设不一致
2. `kiro-cli acp` 的 JSON-RPC 消息结构与当前解析逻辑不一致
3. `session/update` / `session/request_permission` 字段名不一致

---

## 2. 先看哪些文件

下一位大模型先读这些文件，不要先猜：

- [src/handlers.zig](E:\vscode\kiro-cli-dev\kiro-cli-rest-api\src\handlers.zig)
- [src/backends.zig](E:\vscode\kiro-cli-dev\kiro-cli-rest-api\src\backends.zig)
- [src/acp/transport.zig](E:\vscode\kiro-cli-dev\kiro-cli-rest-api\src\acp\transport.zig)
- [src/acp/client.zig](E:\vscode\kiro-cli-dev\kiro-cli-rest-api\src\acp\client.zig)
- [src/store.zig](E:\vscode\kiro-cli-dev\kiro-cli-rest-api\src\store.zig)
- [README.md](E:\vscode\kiro-cli-dev\kiro-cli-rest-api\README.md)
- [docs/wsl-run-guide.md](E:\vscode\kiro-cli-dev\kiro-cli-rest-api\docs\wsl-run-guide.md)

如果需要回到需求基线，再看：

- [openspec/changes/add-kiro-dual-channel-rest-api/design.md](E:\vscode\kiro-cli-dev\kiro-cli-rest-api\openspec\changes\add-kiro-dual-channel-rest-api\design.md)
- [openspec/changes/add-kiro-dual-channel-rest-api/tasks.md](E:\vscode\kiro-cli-dev\kiro-cli-rest-api\openspec\changes\add-kiro-dual-channel-rest-api\tasks.md)
- [openspec/changes/add-kiro-dual-channel-rest-api/traceability.md](E:\vscode\kiro-cli-dev\kiro-cli-rest-api\openspec\changes\add-kiro-dual-channel-rest-api\traceability.md)

---

## 3. 在 WSL 里应该先执行什么

### 3.1 验证 CLI 能力

先单独验证 Kiro CLI，不要先怪 Zig：

```bash
kiro-cli --help
kiro-cli chat --help
kiro-cli acp --help
```

必须记录真实输出，尤其是：

- `chat` 是否支持 `--model`
- `chat` 是否支持 `--no-interactive`
- `acp` 是否存在

### 3.2 构建项目

```bash
zig build
zig build test
```

### 3.3 启动服务

```bash
zig build run -- --host 127.0.0.1 --port 8080 --kiro-cli kiro-cli --workspace-dir .
```

---

## 4. 应该按什么顺序验证接口

### Step 1: 健康检查

```bash
curl http://127.0.0.1:8080/healthz
```

预期：

```json
{"status":"ok"}
```

### Step 2: 验证 Chat 通道

```bash
curl -X POST http://127.0.0.1:8080/prompt \
  -H 'content-type: application/json' \
  -d '{"prompt":"hello","model":"claude-sonnet-4","cwd":"."}'
```

如果这里失败，优先检查：

- [src/backends.zig](E:\vscode\kiro-cli-dev\kiro-cli-rest-api\src\backends.zig)

重点看：

- `argv` 是否符合真实 `kiro-cli chat`
- stdout/stderr 是否有真实报错
- 输出清洗是否把正文误删了

### Step 3: 验证 ACP 单次调用

```bash
curl -X POST http://127.0.0.1:8080/prompt \
  -H 'content-type: application/json' \
  -d '{"prompt":"请列出当前目录结构","model":"auto","cwd":"."}'
```

如果这里失败，优先检查：

- [src/acp/transport.zig](E:\vscode\kiro-cli-dev\kiro-cli-rest-api\src\acp\transport.zig)
- [src/acp/client.zig](E:\vscode\kiro-cli-dev\kiro-cli-rest-api\src\acp\client.zig)

重点看：

- `initialize`
- `session/new`
- `session/prompt`
- `session/update`
- `session/request_permission`

### Step 4: 验证 ACP Session

创建 session：

```bash
curl -X POST http://127.0.0.1:8080/sessions \
  -H 'content-type: application/json' \
  -d '{"cwd":"."}'
```

继续 session：

```bash
curl -X POST http://127.0.0.1:8080/sessions/sess-1/prompt \
  -H 'content-type: application/json' \
  -d '{"prompt":"继续"}'
```

如果这里失败，优先检查：

- REST session id 是否正确映射到 ACP session id
- `session/load` 是否真实可用

---

## 5. 当前代码里的关键假设

下一位大模型必须先确认这些假设，不要直接在错误实现上继续堆代码。

### Chat 假设

[src/backends.zig](E:\vscode\kiro-cli-dev\kiro-cli-rest-api\src\backends.zig) 目前假设：

```bash
kiro-cli chat --model <model> --no-interactive <prompt>
```

如果真实 CLI 不是这样：

- 先以真实 CLI 为准
- 再修改 Zig
- 不要反过来坚持当前实现

### ACP 假设

[src/acp/transport.zig](E:\vscode\kiro-cli-dev\kiro-cli-rest-api\src\acp\transport.zig) 目前假设：

1. `kiro-cli acp` 启动后使用 newline-delimited JSON-RPC
2. 可以发送：
   - `initialize`
   - `session/new`
   - `session/load`
   - `session/prompt`
3. 会收到通知：
   - `session/update`
   - `session/request_permission`
4. permission 应答方法为：
   - `session/respond_permission`

如果任何一项不符合真实输出，先修 transport，不要先改 handler。

---

## 6. 出问题时该怎么定位

### 场景 A：服务能启动，但 Chat 失败

优先做：

1. 在 WSL 里直接执行：

```bash
kiro-cli chat --model claude-sonnet-4 --no-interactive "hello"
```

2. 如果直接命令都失败，先修 CLI 参数假设
3. 如果直接命令成功，但 HTTP 失败，回看：
   - `src/backends.zig`

### 场景 B：`model=auto` 失败

优先做：

1. 在 WSL 里确认 `kiro-cli acp` 能启动
2. 把真实 stdout/stderr 打出来
3. 核对 `session/update` 消息结构
4. 核对 `session/request_permission` 消息结构

最可能需要改的文件：

- `src/acp/transport.zig`

### 场景 C：`/sessions` 创建成功，但继续会话失败

优先看：

- `session/load` 是否真实存在
- 返回的 ACP session id 是否真的可复用
- `SessionStore` 保存的映射是否正确

最可能需要改的文件：

- `src/acp/client.zig`
- `src/store.zig`
- `src/handlers.zig`

---

## 7. 建议的大模型修复顺序

如果下一位大模型接手，请按这个顺序修：

1. 先验证 `kiro-cli chat --help`
2. 修 Chat 参数和输出清洗
3. 再验证 `kiro-cli acp --help`
4. 抓 ACP 原始 JSON-RPC 消息
5. 修 `transport.zig`
6. 再修 `client.zig`
7. 最后再碰 `handlers.zig`

不要一上来就重写 REST 层。

---

## 8. 当前代码已经验证过什么

在当前 Windows 开发环境里，已经验证：

- `zig build` 通过
- `zig build test` 通过

没有在当前回合内验证的内容：

- WSL 里的真实 `kiro-cli chat`
- WSL 里的真实 `kiro-cli acp`
- 真实 ACP JSON-RPC 消息字段

所以如果用户反馈“WSL 能编译但运行失败”，默认优先怀疑的是：

- CLI 参数假设
- ACP 消息字段假设

而不是 Zig HTTP 服务本身。
