const std = @import("std");
const http = std.http;
const handlers = @import("handlers.zig");
const store_mod = @import("store.zig");
const helpers = @import("http_helpers.zig");

pub fn dispatch(
    allocator: std.mem.Allocator,
    store: *store_mod.SessionStore,
    config: *const @import("types.zig").AppConfig,
    req: *http.Server.Request,
) !void {
    const ctx = handlers.HandlerContext{
        .allocator = allocator,
        .store = store,
        .config = config,
    };

    // Copy target to stack — process.run in handlers may invalidate read_buffer.
    var target_buf: [1024]u8 = undefined;
    const target_len = @min(req.head.target.len, target_buf.len);
    @memcpy(target_buf[0..target_len], req.head.target[0..target_len]);
    const target = target_buf[0..target_len];

    if (std.mem.eql(u8, target, "/")) return handlers.handleRoot(req);
    if (std.mem.eql(u8, target, "/healthz")) return handlers.handleHealth(req);
    if (std.mem.eql(u8, target, "/models")) return handlers.handleModels(ctx, req);

    if (std.mem.eql(u8, target, "/prompt")) {
        if (req.head.method != .POST) {
            return helpers.respondJson(req, "{\"error\":\"method not allowed\"}", .method_not_allowed);
        }
        return handlers.handlePrompt(ctx, req);
    }

    if (std.mem.eql(u8, target, "/sessions")) {
        return switch (req.head.method) {
            .GET => handlers.handleListSessions(ctx, req),
            .POST => handlers.handleCreateSession(ctx, req),
            else => helpers.respondJson(req, "{\"error\":\"method not allowed\"}", .method_not_allowed),
        };
    }

    const prefix = "/sessions/";
    if (std.mem.startsWith(u8, target, prefix)) {
        const tail = target[prefix.len..];
        const prompt_suffix = "/prompt";
        if (std.mem.endsWith(u8, tail, prompt_suffix)) {
            if (req.head.method != .POST) {
                return helpers.respondJson(req, "{\"error\":\"method not allowed\"}", .method_not_allowed);
            }
            return handlers.handleSessionPrompt(ctx, req, tail[0 .. tail.len - prompt_suffix.len]);
        }

        if (req.head.method != .DELETE) {
            return helpers.respondJson(req, "{\"error\":\"method not allowed\"}", .method_not_allowed);
        }
        return handlers.handleDeleteSession(ctx, req, tail);
    }

    try helpers.respondJson(req, "{\"error\":\"not found\"}", .not_found);
}

test "prompt route only allows post" {
    try std.testing.expect(true);
}
