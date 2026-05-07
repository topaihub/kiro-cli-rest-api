# Zig 0.16.0 开发踩坑指南（面向 LLM 开发者）

本文档记录在 Zig 0.16.0 中开发 HTTP server + 子进程调用项目时遇到的关键问题。
这些坑在 Zig 0.14/0.13 中不存在，是 0.16 新 IO 系统引入的。

---

## 坑 1：`global_single_threaded` 的 allocator 是 `.failing`

### 症状

调用 `std.process.spawn()` 或 `std.process.run()` 时返回 `OutOfMemory`，但系统内存充足。

### 根因

```zig
// Zig 0.16 标准库中的定义：
pub const init_single_threaded: Threaded = .{
    .allocator = .failing,  // ← 所有分配都返回 OutOfMemory！
    // ...
};
pub const global_single_threaded: *Threaded = &global_single_threaded_instance;
```

`std.process.spawn()` 内部需要分配内存（arena 用于 argv null-termination、环境变量处理等），它使用的是 `Threaded` 实例的 allocator。`global_single_threaded` 的 allocator 是 `Allocator.failing`，任何分配请求都会失败。

### 解决方案

**不要使用 `std.Io.Threaded.global_single_threaded.*.io()` 来 spawn 子进程。**

正确做法：保存 `main` 函数的 `init.io` 并在全项目中使用：

```zig
// src/compat.zig
const std = @import("std");
var process_io: ?std.Io = null;

pub fn initProcess(init: std.process.Init) void {
    process_io = init.io;
}

pub fn io() std.Io {
    return process_io.?;
}
```

```zig
// src/main.zig
pub fn main(init: std.process.Init) !void {
    compat.initProcess(init);  // 必须在任何 IO 操作之前
    // ...
}
```

参考项目：[nullclaw](https://github.com/nullclaw/nullclaw) 的 `src/compat/shared.zig` 使用了完全相同的模式。

---

## 坑 2：`request.head.target` 是指向 read buffer 的切片，子进程执行后可能失效

### 症状

HTTP server 在处理请求时崩溃：`General protection exception (no address available)`，堆栈指向日志记录中访问 `request.head.target`。

### 根因

`std.http.Server` 解析 HTTP 请求后，`request.head.target` 是一个指向 `read_buffer` 的切片（零拷贝）。当 handler 内部调用 `std.process.spawn/run` 时，Zig 的 IO 系统可能在内部操作中影响到这块缓冲区的内容，导致 `target` 变成悬空指针。

```zig
// 危险代码：
fn handleConnection(self: *App, io: std.Io, stream: net.Stream) !void {
    var read_buffer: [16 * 1024]u8 = undefined;
    var reader = stream.reader(io, &read_buffer);
    var server = http.Server.init(&reader.interface, &writer.interface);

    var request = server.receiveHead() catch break;
    // request.head.target 指向 read_buffer 中的数据

    router.dispatch(..., &request);  // 内部调用子进程
    // ↑ 子进程执行后，read_buffer 内容可能已被覆盖

    log.info("done", .{ request.head.target });  // ← 崩溃！悬空指针
}
```

### 解决方案

在调用任何可能触发 IO 操作的函数之前，将 `target` 复制到栈上：

```zig
var target_buf: [1024]u8 = undefined;
const target_len = @min(request.head.target.len, target_buf.len);
@memcpy(target_buf[0..target_len], request.head.target[0..target_len]);
const target = target_buf[0..target_len];
```

nullclaw 的做法更彻底：它不使用 `std.http.Server`，而是自己从 TCP stream 读取完整 HTTP 请求到 arena 分配的内存中，避免了这个问题。

---

## 坑 3：`std.process.run()` 在 HTTP server 上下文中可能死锁或失败

### 症状

`std.process.run()` 在独立程序中工作正常，但在 HTTP server 的请求处理中调用时返回 `OutOfMemory` 或永远阻塞。

### 根因

`std.process.run()` 内部使用 `Io.File.MultiReader`，它依赖 IO 系统的 batch 操作。在 HTTP server 的 IO 上下文中，这些操作可能与 server 的 IO 循环冲突。

### 解决方案

不使用 `std.process.run()`，改为手动管理子进程：

```zig
pub fn runCollect(allocator: std.mem.Allocator, argv: []const []const u8, cwd: []const u8) !RunResult {
    const io = compat.io();
    var child = try std.process.spawn(io, .{
        .argv = argv,
        .cwd = .{ .path = cwd },
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .ignore,
    });

    const stdout_fd = child.stdout.?.handle;

    // 用 posix.read 直接读取 pipe，绕过 IO 系统
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    var buf: [4096]u8 = undefined;
    while (true) {
        const n = std.posix.read(stdout_fd, &buf) catch break;
        if (n == 0) break;
        try out.appendSlice(allocator, buf[0..n]);
    }

    // 关闭 pipe
    _ = std.os.linux.close(stdout_fd);
    child.stdout = null;

    // 用 linux waitpid 直接等待，绕过 IO 系统
    const pid = child.id.?;
    var status: u32 = 0;
    while (true) {
        const rc = std.os.linux.waitpid(pid, &status, 0);
        if (std.posix.errno(rc) != .INTR) break;
    }
    child.id = null;

    return .{
        .stdout = try allocator.dupe(u8, out.items),
        .exit_code = if (status & 0x7f == 0) @intCast((status >> 8) & 0xff) else 1,
    };
}
```

关键点：
- `std.process.spawn()` 用 `compat.io()`（即 `init.io`）来 fork/exec — 这一步没问题
- 读取 stdout 用 `std.posix.read()` — 绕过 IO 系统的 MultiReader
- 等待子进程用 `std.os.linux.waitpid()` — 绕过 `child.wait(io)`

---

## 坑 4：`std.posix.close()` 在 Zig 0.16 中不存在

### 症状

编译错误：`root source file struct 'posix' has no member named 'close'`

### 解决方案

使用 `std.os.linux.close(fd)` 替代。注意它返回 `usize`（syscall 返回值），不是 void。

---

## 坑 5：Zig 0.16 的 `main` 函数签名变了

### 说明

Zig 0.16 的 `main` 函数接收 `std.process.Init` 参数：

```zig
pub fn main(init: std.process.Init) !void {
    // init.io — 正确的 IO 实例（有真正的 allocator）
    // init.minimal.args — 命令行参数
    // init.gpa — 通用 allocator
    // init.arena — 进程级 arena
}
```

`init.io` 是唯一能正确执行子进程的 IO 实例。不要用 `global_single_threaded`。

---

## 坑 6：`std.Io.Limit` 和 `std.Io.Timeout` 的构造方式

### 正确用法

```zig
// Limit
.stdout_limit = .limited(1024 * 1024),
.stdout_limit = .unlimited,

// Timeout
.timeout = .none,
.timeout = .{ .duration = .{ .raw = std.Io.Duration.fromSeconds(30), .clock = .awake } },
```

---

## 坑 7：`kiro-cli` 模型名错误时退出码仍为 0

### 症状

`kiro-cli chat --model claude-sonnet-4 ...` 输出 `error: Model 'claude-sonnet-4' does not exist`，但退出码是 0。

### 影响

不能仅靠退出码判断命令是否成功。需要检查 stdout 内容是否为有效响应。

### 建议

动态获取模型列表：`kiro-cli chat --list-models --format json`，而不是硬编码模型名。

---

## 推荐的项目结构（Zig 0.16 HTTP server + 子进程）

```
src/
  compat.zig       — 全局 IO 管理（initProcess + io()）
  process.zig      — 子进程执行封装（spawn + posix read + waitpid）
  server.zig       — HTTP server（通过 compat.io() 获取 IO）
  handlers.zig     — 请求处理（调用 process.runCollect）
  main.zig         — 入口（compat.initProcess(init)）
```

核心原则：
1. **IO 不通过参数传递** — 用 compat 全局层管理
2. **子进程读取用 posix.read** — 绕过 IO 系统的 MultiReader
3. **子进程等待用 linux.waitpid** — 绕过 child.wait(io)
4. **HTTP request 数据要复制** — target/headers 指向的 buffer 可能被覆盖

---

## 参考项目

- [nullclaw](https://github.com/nullclaw/nullclaw) — 7.4k stars 的 Zig 0.16 AI agent 平台
  - `src/compat/shared.zig` — IO 管理模式
  - `src/compat.zig` — process.Child 封装
  - `src/tools/process_util.zig` — 子进程执行（用 readToEndAlloc + wait）
  - `src/gateway.zig` — HTTP server（自己解析 raw HTTP，不用 std.http.Server）
