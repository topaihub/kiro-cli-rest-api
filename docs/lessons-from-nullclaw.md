# 从 nullclaw 项目学习与借鉴

[nullclaw](https://github.com/nullclaw/nullclaw) 是一个 7.4k stars 的 Zig 0.16.0 AI agent 平台（249k 行代码，5300+ 测试）。本文档记录从中学到的架构模式和工程实践。

---

## 1. compat 层统一管理运行时上下文

### nullclaw 的做法

```zig
// src/compat/shared.zig
var process_io: ?Io = null;

pub fn initProcess(init: std.process.Init) void {
    process_io = init.io;
}

pub fn io() Io {
    if (process_io) |current| return current;
    return fallback_threaded.io();  // 测试环境 fallback
}
```

```zig
// src/main.zig
pub fn main(init: std.process.Init) !void {
    std_compat.initProcess(init);  // 第一行
    // ...
}
```

### 为什么好

- **IO 不通过参数层层传递** — 任何模块需要 IO 时调用 `compat.io()` 即可
- **测试友好** — 测试中返回 `std.testing.io`，不需要 mock
- **单一初始化点** — main 入口一行搞定，不会遗漏

### 我们的借鉴

创建了 `src/compat.zig`，将 `init.io` 保存为全局状态，所有模块通过 `compat.io()` 获取。从 `AppConfig` 中移除了 `io` 字段，代码更干净。

---

## 2. process.Child 封装层

### nullclaw 的做法

```zig
// src/compat.zig — 封装 std.process.Child
pub const Child = struct {
    pub fn spawn(self: *Child) !void {
        const inner = try std.process.spawn(io(), .{ ... });
        // ...
    }

    pub fn wait(self: *Child) !Term {
        var inner = self.toInner();
        return try inner.wait(io());
    }
};
```

```zig
// src/tools/process_util.zig — 高层 run 函数
pub fn run(allocator: Allocator, argv: []const []const u8, opts: RunOptions) !RunResult {
    var child = std_compat.process.Child.init(argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    child.pgid = 0;  // 隔离进程组

    try child.spawn();
    // ... 读取 stdout/stderr，支持 cancel 和 timeout
    const term = try child.wait();
    return RunResult{ ... };
}
```

### 关键设计

- **进程组隔离** — `child.pgid = 0` 让子进程在独立进程组，timeout/cancel 时可以杀掉整个进程树
- **cancel flag** — 通过 `AtomicBool` 支持外部取消
- **timeout watcher** — 单独线程监控超时，到期后 kill 子进程
- **输出规范化** — `normalizeCapturedOutputOwned` 处理 Windows codepage 等平台差异

### 我们的借鉴

创建了 `src/process.zig`，封装 spawn + read + waitpid。当前实现较简单（无 timeout/cancel），但接口已统一，后续可按需扩展。

---

## 3. HTTP server 不依赖 std.http.Server

### nullclaw 的做法

nullclaw 的 gateway（385KB 源码）完全自己解析 HTTP：

```zig
// 直接从 TCP stream 读取完整请求
const raw = readHttpRequest(req_allocator, &conn.stream, max_body) catch |err| { ... };

// 手动解析第一行
const first_line_end = std.mem.indexOf(u8, raw, "\r\n") orelse continue;
var parts = std.mem.splitScalar(u8, first_line, ' ');
const method_str = parts.next() orelse continue;
const target = parts.next() orelse continue;
```

### 为什么这样做

- **避免 std.http.Server 的 buffer 生命周期问题** — 请求数据在 arena 中，不会被覆盖
- **完全控制超时** — `configureRequestReadTimeout` 设置 socket SO_RCVTIMEO
- **per-request arena** — 每个请求一个 ArenaAllocator，处理完一次性释放
- **Connection: close** — 简化实现，不需要处理 keep-alive 的 buffer 复用

### 我们的借鉴

当前仍使用 `std.http.Server`，但通过复制 `request.head.target` 到栈上规避了 buffer 失效问题。如果后续需要更复杂的 HTTP 处理（streaming、大 body），可以参考 nullclaw 的自解析方式。

---

## 4. per-request Arena Allocator

### nullclaw 的做法

```zig
while (true) {
    var conn = server.accept() catch |err| { ... };

    // 每个请求独立的 arena
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const req_allocator = arena.allocator();

    const raw = readHttpRequest(req_allocator, &conn.stream, max_body) catch { ... };
    // 所有请求处理都用 req_allocator
    // defer arena.deinit() 一次性释放所有请求相关内存
}
```

### 为什么好

- **零碎片** — 请求处理中的所有临时分配在 arena 中，不会造成堆碎片
- **无泄漏风险** — 即使 handler 中途 return/error，arena.deinit() 保证全部释放
- **性能** — arena 分配是 O(1) bump pointer，比通用 allocator 快

### 我们可以借鉴的

当前 handlers 中有多处 `defer allocator.free(...)` 手动管理。可以在 `handleConnection` 中引入 per-request arena，简化内存管理。

---

## 5. 非阻塞 accept + 优雅关闭

### nullclaw 的做法

```zig
var server = try addr.listen(.{
    .reuse_address = true,
    .force_nonblocking = daemon_mode,  // daemon 模式下非阻塞
});

while (true) {
    if (daemon.isShutdownRequested()) break;  // 检查关闭信号

    var conn = server.accept() catch |err| switch (err) {
        error.WouldBlock => {
            std_compat.thread.sleep(ACCEPT_POLL_INTERVAL_MS * std.time.ns_per_ms);
            continue;
        },
        else => {
            // 指数退避
            accept_sleep_ms = nextAcceptSleepMs(accept_sleep_ms, err);
            std_compat.thread.sleep(accept_sleep_ms * std.time.ns_per_ms);
            continue;
        },
    };
    // ...
}
```

### 关键设计

- **非阻塞 accept** — 允许主循环定期检查 shutdown flag
- **指数退避** — accept 连续失败时不会 busy-loop
- **端口占用检测** — 启动前 probe 端口是否已被占用

### 我们可以借鉴的

当前 server 是阻塞式 accept，无法优雅关闭。后续如果需要 daemon 模式或 graceful shutdown，可以参考这个模式。

---

## 6. 端口占用预检测

### nullclaw 的做法

```zig
// 启动前尝试连接目标端口，如果能连上说明已被占用
const probe_conn = std_compat.net.tcpConnectToAddress(addr) catch null;
if (probe_conn) |conn| {
    conn.close();
    return error.AddressInUse;
}
```

### 为什么好

比直接 listen 失败后报错更友好 — 可以给出明确的 "port already in use" 错误信息。

---

## 7. vtable 接口设计

### nullclaw 的架构

所有子系统都是 vtable 接口，可以通过配置切换实现：

```
Provider  → OpenAI, Anthropic, Ollama, 50+ 实现
Channel   → Telegram, Discord, CLI, 19 个实现
Memory    → SQLite, Redis, PostgreSQL, 10 个实现
Sandbox   → Landlock, Firejail, Docker
Runtime   → Native, Docker, WASM
```

### 对我们的启示

当前 `kiro-cli-rest-api` 的 backend 只有 chat/acp 两种，但如果后续要支持更多 provider 或通道，可以参考 vtable 模式做抽象。

---

## 8. 项目工程实践

### 从 nullclaw 观察到的

| 实践 | 说明 |
|------|------|
| 5300+ 测试 | 几乎每个函数都有测试，包括边界情况 |
| 单文件模块 | 大文件（gateway.zig 385KB）但职责单一 |
| 零外部依赖 | 除 libc 和可选的 SQLite 外无依赖 |
| CalVer 版本 | `YYYY.M.D` 格式，简单明确 |
| AGENTS.md / CLAUDE.md | 为 AI 辅助开发提供上下文 |
| 中英双语文档 | `docs/en/` + `docs/zh/` |

---

## 总结：对 kiro-cli-rest-api 的实际改进

| 改进 | 来源 | 效果 |
|------|------|------|
| `compat.zig` 全局 IO | nullclaw `compat/shared.zig` | 消除 IO 参数传递，解决 OutOfMemory |
| `process.zig` 子进程封装 | nullclaw `tools/process_util.zig` | 统一接口，隔离平台细节 |
| target 栈复制 | nullclaw 自解析 HTTP 的思路 | 修复悬空指针崩溃 |
| 动态模型列表 | nullclaw 的 provider 动态发现 | 不再硬编码，适应环境变化 |
