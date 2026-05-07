# Changelog

All notable changes to this project will be documented in this file.

## v0.1.0 (2026-05-07)

### ✨ 新功能

- REST API 服务：GET /healthz, /models, POST /prompt, /sessions
- 双通道架构：Chat（显式模型）和 ACP（自动模型）
- 动态模型列表（从 kiro-cli 获取）
- per-request trace_id 日志追踪
- compat 层统一 IO 管理（参考 nullclaw）

### 🐛 Bug 修复

- 修复 `global_single_threaded` allocator 为 `.failing` 导致子进程 spawn 失败
- 修复 `request.head.target` 悬空指针导致的崩溃
- 修复 `std.process.run()` 在 HTTP handler 中死锁

### 📝 文档

- 项目介绍文档 (docs/introduction.md)
- Zig 0.16 踩坑指南 (docs/zig-0.16-pitfalls.md)
- nullclaw 学习借鉴 (docs/lessons-from-nullclaw.md)
- WSL 运行指南 (docs/wsl-run-guide.md)
- AGENTS.md / CLAUDE.md
