# Spec：Kiro Dual-Channel REST API

## ADDED Requirements

### Requirement: 服务必须保留双通道架构语义

服务必须根据模型选择在 ACP 与 Chat 两条执行路径之间分流，而不是把两者合并为单一路径。

#### Scenario: `model=auto` 走 ACP

- **WHEN** 客户端调用 `POST /prompt` 且 `model` 为 `auto`
- **THEN** 服务必须通过 ACP 客户端执行请求
- **AND** 不能改为 Chat 子进程执行

#### Scenario: 指定模型走 Chat

- **WHEN** 客户端调用 `POST /prompt` 且 `model` 为非 `auto`
- **THEN** 服务必须通过 `kiro-cli chat` 子进程执行请求
- **AND** 不能假装该请求具备 ACP 多轮上下文能力

#### Scenario: `auto` 尚未实现时不得伪装成功

- **WHEN** `model=auto` 的 ACP 路径尚未完成
- **THEN** 服务必须返回明确的失败或未实现状态
- **AND** 不能返回伪造正文

### Requirement: 服务必须暴露与原文一致的 REST 接口

服务必须提供原文列出的最小接口集合。

#### Scenario: 根路径健康检查

- **WHEN** 客户端调用 `GET /`
- **THEN** 服务必须返回健康状态

#### Scenario: 模型列表

- **WHEN** 客户端调用 `GET /models`
- **THEN** 服务必须返回支持的模型视图
- **AND** 必须明确 `auto` 与 ACP 的关系
- **AND** 不能把未实现的显式模型能力伪装为已可用

#### Scenario: 快捷调用

- **WHEN** 客户端调用 `POST /prompt`
- **THEN** 服务必须执行单次 prompt 请求

#### Scenario: 会话接口

- **WHEN** 客户端调用 `/sessions` 相关接口
- **THEN** 服务必须支持创建、追加、列出、删除会话
- **AND** 这些会话必须对应 ACP 会话，而不是 Chat 调用历史

### Requirement: ACP 通道必须收集 `session/update` 文本块

ACP 通道不能仅依赖 `session/prompt` 的最终响应。

#### Scenario: 最终响应只返回 stopReason

- **WHEN** ACP `session/prompt` 最终响应不包含正文文本
- **THEN** 服务必须从 `session/update` 通知中收集正文
- **AND** 在 `end_turn` 后拼接并返回完整文本

### Requirement: ACP 权限请求必须被同步处理

当 Kiro 发出 `session/request_permission` 时，服务必须给出协议回复。

#### Scenario: Headless 自动审批

- **WHEN** ACP 通道收到 `session/request_permission`
- **THEN** 服务必须返回允许执行的审批结果
- **AND** 不能让 Kiro CLI 永久阻塞等待

### Requirement: Chat 通道必须清洗终端 UI 噪声

Chat 通道返回正文前，必须对 stdout 做清洗。

#### Scenario: 输出包含 banner 和 credits

- **WHEN** `kiro-cli chat` stdout 包含 ANSI、banner、Model/Plan 行、credits 页脚
- **THEN** 服务必须去除这些噪声
- **AND** 只返回实际回答正文

### Requirement: 会话语义必须只建立在 ACP 通道上

服务不能把 Chat 通道伪装成真正的多轮会话。

#### Scenario: 创建会话

- **WHEN** 客户端创建会话
- **THEN** 服务必须创建 ACP 会话
- **AND** 会话记录必须映射到真实 ACP session id

#### Scenario: 指定模型不进入 ACP 会话

- **WHEN** 客户端请求显式模型
- **THEN** 服务不能把该请求塞入 ACP 会话流中

### Requirement: 服务必须声明已知限制

服务文档和行为必须保留原文已知限制，而不是隐式掩盖。

#### Scenario: 服务重启

- **WHEN** 服务重启
- **THEN** 现有会话可以丢失
- **AND** 文档必须说明会话不持久化

#### Scenario: ACP 并发

- **WHEN** 多个 ACP 请求同时到达
- **THEN** 首版实现可以按单连接顺序处理
- **AND** 文档必须说明该限制
