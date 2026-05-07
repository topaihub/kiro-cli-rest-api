# Execution Orchestration Review

## 结论

原 `tasks.md` 更像需求分项，不足以直接驱动大模型稳定开发。

主要问题：

1. 任务粒度偏大  
   例如“实现 ACP client 高层语义”对于单轮执行过大。

2. 依赖关系不够显式  
   ACP transport、pending map、文本收集其实是严格串行依赖。

3. 缺少“单轮产物”定义  
   大模型容易做到一半停在抽象层，而不是产出可验证代码。

4. 缺少“诚实降级”阶段  
   在 ACP 未完成前，应先交付一版 Chat 可用、ACP 明确报未实现的 HTTP 服务。

## 调整结果

已将任务重组为 4 个 Wave：

1. Wave 0：基线冻结
2. Wave 1：无 ACP 的可运行基础
3. Wave 2：ACP 协议基础设施
4. Wave 3：ACP 会话能力
5. Wave 4：统一服务收尾

## 为什么这样拆

### 先交付 Chat 可用的服务

这样可以先验证：

- HTTP 层是否稳定
- 子进程调用是否稳定
- README 与运行方式是否清晰

同时避免 ACP 未完成时整个服务只能停留在占位状态。

### 把 ACP 分成 transport / sync / semantics 三层

这是后续实现成败的关键：

- Transport 解决“进程和管道”
- Sync 封装解决“请求-响应匹配”
- Semantics 解决“文本块和 permission”

如果把三层混着做，大模型很容易在一次执行里同时改协议、状态、业务逻辑，回归成本很高。

## 对后续大模型的建议

1. 一次只做一个 Work Package。
2. 每次开始前，先读 `traceability.md`，确认没有偏离原文/Python 基线。
3. 在 ACP 开始之前，不要再扩展 REST 接口范围。
4. 若目标环境 CLI 参数与当前设计冲突，应先回写 OpenSpec，再改代码。
