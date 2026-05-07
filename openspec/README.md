# OpenSpec Notes

本目录用于承载 `kiro-cli-rest-api` 的需求、设计与任务拆分工件。

当前变更：

- `changes/add-kiro-dual-channel-rest-api/`

## 使用原则

1. 以 AWS 官方文章与 `kiro-acp` Python 参考源码为基线。
2. 先忠实保留行为语义，再做 Zig 工程化优化。
3. 不允许把 Chat 通道伪装成真实多轮会话。
4. 不允许在没有证据的情况下随意改动 ACP 协议行为。

## 推荐执行顺序

1. 阅读 `proposal.md`
2. 阅读 `design.md`
3. 按 `specs/.../spec.md` 校验行为边界
4. 按 `tasks.md` 逐项实现
