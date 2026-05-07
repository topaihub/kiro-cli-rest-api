# Tasks：Kiro CLI Zig REST API（执行编排版）

本文件不是单纯的功能列表，而是面向“大模型连续开发”的执行编排。

## 编排原则

1. 先做可独立验证的基础块，再做依赖它们的协议块。
2. 每个工作包必须有明确输入、输出、阻塞点、验收方式。
3. 尽量让单个工作包可以在一次模型执行中完成。
4. ACP 相关任务天然风险更高，必须建立在前置基础块已稳定的前提上。

---

## Wave 0：基线冻结

### Work Package 0.1：冻结原文/Python 基线

目标：

- 固化“哪些行为来自原文/Python”，避免后续实现继续漂移。

输入：

- AWS 原文
- `acp_client.py`
- `server.py`
- 当前 `proposal/design/spec/traceability`

输出：

- 更新后的 `proposal.md`
- 更新后的 `design.md`
- 更新后的 `spec.md`
- 更新后的 `traceability.md`

阻塞点：

- 无

验收方式：

- 文档中不再出现未经验证的 CLI 参数假设
- `traceability.md` 可以逐条映射原行为

状态：

- [x] 已完成

---

## Wave 1：无 ACP 的可运行基础

### Work Package 1.1：重整数据结构与配置

目标：

- 让代码结构能表达原文双通道语义，但不提前实现 ACP。

输入：

- `types.zig`
- `store.zig`
- `main.zig`
- `design.md`

输出：

- 清晰的 DTO / config / session 基础结构
- 明确哪些字段服务于 HTTP 层，哪些字段预留给 ACP 层

阻塞点：

- 依赖 Wave 0 完成

验收方式：

- `zig build test`
- `SessionStore` 不再把 Chat 历史伪装成 ACP 会话

状态：

- [ ] 待执行

### Work Package 1.2：实现 Chat Runner 真实执行

目标：

- 把显式模型路径从占位实现替换成真实 `kiro-cli chat` 调用。

输入：

- `backends.zig`
- 目标环境中的 `kiro-cli chat --help`

输出：

- 可配置 `kiro-cli` 路径
- 子进程 stdout/stderr/exit code 处理
- timeout 分支

阻塞点：

- 依赖 Work Package 1.1

验收方式：

- `zig build`
- 能在目标环境对显式模型执行一次真实调用

状态：

- [ ] 待执行

### Work Package 1.3：实现 Chat 输出清洗器

目标：

- 用纯函数实现 Python 参考版等价的输出清洗。

输入：

- `server.py` 中的清洗逻辑
- 若干真实 `kiro-cli chat` 输出样本

输出：

- `clean_chat_output(...)`
- 针对 banner / ANSI / credits / 空输出 的测试

阻塞点：

- 可与 Work Package 1.2 并行，但最终要由 1.2 集成

验收方式：

- `zig build test`
- 给定样本输出，能提取正文

状态：

- [ ] 待执行

### Work Package 1.4：实现最小无状态 REST 面

目标：

- 在没有 ACP 的情况下先交付一版诚实可用的 HTTP 服务。

输入：

- `router.zig`
- `handlers.zig`
- `server.zig`
- Work Package 1.2 / 1.3

输出：

- `GET /`
- `GET /models`
- `POST /prompt`
- 对 `model=auto` 返回明确未实现/不可用错误

阻塞点：

- 依赖 Work Package 1.2 与 1.3

验收方式：

- `zig build`
- Chat 路径真实可用
- `auto` 路径不再伪装成功

状态：

- [ ] 待执行

---

## Wave 2：ACP 协议基础设施

### Work Package 2.1：实现 ACP Transport

目标：

- 建立 `kiro-cli acp` 的底层子进程和 JSON-RPC 管道。

输入：

- `acp_client.py`
- `design.md` 4.2

输出：

- `src/acp/transport.zig`
- spawn / stdin / stdout / stderr / read loop
- 最小消息收发接口

阻塞点：

- 依赖 Work Package 1.1

验收方式：

- 单元测试或小型探针可收发 JSON-RPC
- stderr 排空不会阻塞进程

状态：

- [ ] 待执行

### Work Package 2.2：实现 ACP 请求同步封装

目标：

- 把异步 JSON-RPC 封装成可等待的同步语义。

输入：

- `src/acp/transport.zig`

输出：

- request id 生成器
- pending map
- waiter / condition 机制

阻塞点：

- 依赖 Work Package 2.1

验收方式：

- 能发送请求并按 `id` 收到对应响应

状态：

- [ ] 待执行

### Work Package 2.3：实现 ACP 文本收集与 permission 响应

目标：

- 解决 ACP 真正的行为复杂点。

输入：

- `acp_client.py`
- Work Package 2.2

输出：

- `session/update` 文本块缓存与拼接
- `session/request_permission` 自动回复
- `stopReason` / 空正文 / 协议异常分支

阻塞点：

- 依赖 Work Package 2.2

验收方式：

- `session/prompt` 最终能返回完整正文
- 敏感操作不再卡死

状态：

- [ ] 待执行

---

## Wave 3：ACP 会话能力

### Work Package 3.1：实现 ACP Client 高层接口

目标：

- 交付 `initialize`、`session/new`、`session/prompt` 的高层 API。

输入：

- Wave 2 全部产物

输出：

- `src/acp/client.zig`
- 高层调用接口

阻塞点：

- 依赖 Work Package 2.3

验收方式：

- 可以建立 ACP 会话并发送 prompt

状态：

- [ ] 待执行

### Work Package 3.2：实现会话存储与 REST 会话接口

目标：

- 把 ACP 会话能力映射到 REST `/sessions`。

输入：

- `store.zig`
- `handlers.zig`
- `router.zig`
- Work Package 3.1

输出：

- `POST /sessions`
- `POST /sessions/{id}/prompt`
- `GET /sessions`
- `DELETE /sessions/{id}`

阻塞点：

- 依赖 Work Package 3.1

验收方式：

- `/sessions` 只包含 ACP 会话
- 能用 REST session id 继续会话

状态：

- [ ] 待执行

---

## Wave 4：统一服务收尾

### Work Package 4.1：统一错误映射与结构化日志

目标：

- 把 Chat / ACP / HTTP 的错误面收敛成稳定接口。

输入：

- 所有前置工作包

输出：

- 稳定 HTTP 状态码映射
- `zig-logging` 日志点

阻塞点：

- 依赖 Wave 1 与 Wave 3

验收方式：

- 错误场景可通过日志和 HTTP 返回定位

状态：

- [ ] 待执行

### Work Package 4.2：测试、README、运行说明

目标：

- 把项目变成可交接状态。

输入：

- 所有前置工作包

输出：

- 单元测试
- 集成测试说明
- README
- WSL/Linux 运行说明

阻塞点：

- 依赖 Work Package 4.1

验收方式：

- `zig build`
- `zig build test`
- 文档足以指导下一位大模型/工程师继续推进

状态：

- [ ] 待执行

---

## 可并行项

以下工作包可以并行：

- 1.2 Chat Runner
- 1.3 Chat 输出清洗器

以下工作包不建议并行：

- 2.1 / 2.2 / 2.3
  - 协议依赖强，顺序错误会导致调试成本陡增

---

## 当前推荐开发顺序

1. Work Package 1.1
2. Work Package 1.2
3. Work Package 1.3
4. Work Package 1.4
5. Work Package 2.1
6. Work Package 2.2
7. Work Package 2.3
8. Work Package 3.1
9. Work Package 3.2
10. Work Package 4.1
11. Work Package 4.2
