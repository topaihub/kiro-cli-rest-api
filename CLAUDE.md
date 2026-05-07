# CLAUDE.md

This is a Zig 0.16.0 project. Read AGENTS.md for full context.

## Key Pitfall

`std.Io.Threaded.global_single_threaded` has a `.failing` allocator — spawning subprocesses with it always returns OutOfMemory. Use `compat.io()` instead (initialized from `main`'s `init.io`).

## When modifying subprocess code

- Use `process.runCollect()` from `src/process.zig`
- Do NOT use `std.process.run()` — it deadlocks in HTTP handler context
- Do NOT use `child.wait(io)` — use `std.os.linux.waitpid()` directly

## When modifying HTTP handlers

- `request.head.target` points into a read buffer that may be invalidated by subprocess IO
- Always copy target to stack before calling dispatch/handlers
- This is already done in `server.zig` and `router.zig`

## Style

- Minimal code, no unnecessary abstractions
- Errors returned as JSON `{"error":"..."}` with appropriate HTTP status
- All subprocess output cleaned (ANSI stripped, noise lines removed)
