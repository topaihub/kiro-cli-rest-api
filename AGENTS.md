# AGENTS.md

## Project

kiro-cli-rest-api — Zig 0.16.0 HTTP server that wraps `kiro-cli` as a REST API.

## Build & Test

```bash
zig build          # compile
zig build test     # run unit tests
zig build run -- --port 8080 --kiro-cli kiro-cli --workspace-dir .
```

## Architecture

```
main.zig       → entry, CLI args, compat.initProcess(init)
compat.zig     → global IO management (saves init.io)
process.zig    → child process execution (spawn + posix read + waitpid)
server.zig     → TCP listener, HTTP parsing, request dispatch
router.zig     → route matching, delegates to handlers
handlers.zig   → endpoint logic (models, prompt, sessions)
backends.zig   → chat backend execution, output cleaning
store.zig      → in-memory session store
types.zig      → shared types (AppConfig, Session, etc.)
http_helpers.zig → JSON response/body helpers
acp/           → ACP transport and client (JSON-RPC over subprocess)
```

## Critical Zig 0.16 Rules

1. **Never use `std.Io.Threaded.global_single_threaded`** — its allocator is `.failing`, all allocations return OutOfMemory.
2. **Always use `compat.io()`** to get the IO instance (initialized from `init.io` in main).
3. **Never use `std.process.run()`** in HTTP handler context — use `process.runCollect()` which uses posix read + linux waitpid.
4. **Copy `request.head.target`** before calling any function that spawns subprocesses — the read buffer may be invalidated.
5. **`std.posix.close()` does not exist** in Zig 0.16 — use `std.os.linux.close()`.

## Endpoints

- `GET /` — root info
- `GET /healthz` — health check
- `GET /models` — dynamic model list from kiro-cli
- `POST /prompt` — send prompt, get response (chat or acp)
- `POST /sessions` — create ACP session
- `POST /sessions/{id}/prompt` — continue session
- `DELETE /sessions/{id}` — delete session

## Dependencies

- `../zig-logging` — structured logging
- `../zig-release` — version/release tooling

Both are local path dependencies in `build.zig.zon`.

## Testing

```bash
# Unit tests
zig build test

# Manual integration
curl http://127.0.0.1:8080/healthz
curl http://127.0.0.1:8080/models
curl -X POST http://127.0.0.1:8080/prompt \
  -H 'content-type: application/json' \
  -d '{"prompt":"hello","model":"claude-sonnet-4.6","cwd":"."}'
```
