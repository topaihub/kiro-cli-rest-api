# Traceability

本文件用于把原文 / Python 参考实现中的关键行为，映射到 Zig 设计与任务。

## 原文 / Python 基线 -> Zig 设计映射

| 基线行为 | 来源 | Zig 设计位置 | 任务位置 |
|---|---|---|---|
| `model=auto` 走 ACP | 原文 + `server.py` | `design.md` 4.1 | Task 4 / Task 6 / Task 7 |
| 指定模型走 Chat | 原文 + `server.py` | `design.md` 4.1 / 4.3 | Task 3 / Task 4 |
| ACP 会话支持多轮 | 原文 + `acp_client.py` | `design.md` 4.1 / 4.4 | Task 6 / Task 7 |
| Chat 为单次子进程 | 原文 + `server.py` | `design.md` 4.3 | Task 3 |
| `session/update` 承载正文 | 原文 + `acp_client.py` | `design.md` 4.2.3 | Task 6 |
| `session/request_permission` 必须同步响应 | 原文 + `acp_client.py` | `design.md` 4.2.4 | Task 6 |
| Chat 输出必须清洗 | 原文 + `server.py` | `design.md` 4.3.1 | Task 3 |
| `/sessions` 仅面向 ACP 会话 | 原文意图 + Python 架构职责 | `design.md` 4.1 / 4.4 | Task 7 |
| 首版无鉴权、会话不持久化 | 原文已知限制 | `proposal.md` 非目标 / 已知限制 | Task 1 / Task 9 |

## 需要重点防漂移的地方

1. 不要把 Chat 历史混成 `/sessions`。
2. 不要把 ACP 最终响应错误理解为正文来源。
3. 不要把未验证的 CLI 参数写成设计事实。
4. 不要因为 Zig 重构方便而改变双通道职责边界。
