# WSL 运行说明

本文档面向已经在 WSL 中安装好 `kiro-cli` 的环境。

## 1. 前置条件

确认以下命令可用：

```bash
kiro-cli --help
kiro-cli chat --help
kiro-cli acp --help
zig version
```

## 2. 启动服务

进入项目目录后运行：

```bash
zig build run -- --port 8080 --kiro-cli kiro-cli --workspace-dir .
```

如果你想指定监听地址：

```bash
zig build run -- --host 127.0.0.1 --port 8080 --kiro-cli kiro-cli --workspace-dir .
```

## 3. 快速验证

### 健康检查

```bash
curl http://127.0.0.1:8080/healthz
```

### 显式模型走 Chat

```bash
curl -X POST http://127.0.0.1:8080/prompt \
  -H 'content-type: application/json' \
  -d '{"prompt":"hello","model":"claude-sonnet-4","cwd":"."}'
```

### `auto` 走 ACP

```bash
curl -X POST http://127.0.0.1:8080/prompt \
  -H 'content-type: application/json' \
  -d '{"prompt":"请列出当前目录结构","model":"auto","cwd":"."}'
```

### 创建 ACP Session

```bash
curl -X POST http://127.0.0.1:8080/sessions \
  -H 'content-type: application/json' \
  -d '{"cwd":"."}'
```

### 继续 ACP Session

将上一步返回的 `id` 代入：

```bash
curl -X POST http://127.0.0.1:8080/sessions/sess-1/prompt \
  -H 'content-type: application/json' \
  -d '{"prompt":"继续"}'
```

## 4. 当前实现说明

- 显式模型调用 `kiro-cli chat --model <model> --no-interactive <prompt>`
- `auto` 和 `/sessions` 通过 `kiro-cli acp` 调用 ACP
- 本地 session store 只保存 REST session id 到 ACP session id 的映射
- session 映射是内存态，服务重启后需要重新创建

## 5. 若运行失败，先检查什么

1. `kiro-cli chat` 是否真的支持 `--model` 和 `--no-interactive`
2. `kiro-cli acp` 是否真的按 JSON-RPC newline-delimited 输出
3. `session/update` 的正文结构是否和当前解析逻辑一致
4. `session/request_permission` 的字段名是否和当前自动批准逻辑一致

如果第 2 到第 4 项与你环境里的真实输出不一致，优先保留协议事实，再调整 Zig 解析代码。
