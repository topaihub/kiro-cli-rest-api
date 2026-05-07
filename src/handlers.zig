const std = @import("std");
const http = std.http;
const types = @import("types.zig");
const store_mod = @import("store.zig");
const backends = @import("backends.zig");
const process = @import("process.zig");
const acp = @import("acp/root.zig");
const helpers = @import("http_helpers.zig");

pub const HandlerContext = struct {
    allocator: std.mem.Allocator,
    store: *store_mod.SessionStore,
    config: *const types.AppConfig,
};

fn respondExecutionError(req: *http.Server.Request, err: anyerror) !void {
    return switch (err) {
        backends.ExecutionError.EmptyPrompt => helpers.respondJson(req, "{\"error\":\"prompt must not be empty\"}", .bad_request),
        backends.ExecutionError.UnsupportedBackend => helpers.respondJson(req, "{\"error\":\"auto model requires ACP\"}", .bad_request),
        backends.ExecutionError.KiroCliTimedOut => helpers.respondJson(req, "{\"error\":\"kiro-cli chat timed out\"}", .gateway_timeout),
        backends.ExecutionError.EmptyChatResponse => helpers.respondJson(req, "{\"error\":\"kiro-cli chat returned an empty response\"}", .bad_gateway),
        backends.ExecutionError.KiroCliFailed => helpers.respondJson(req, "{\"error\":\"kiro-cli chat failed\"}", .bad_gateway),
        else => err,
    };
}

fn respondAcpError(req: *http.Server.Request, err: anyerror) !void {
    return switch (err) {
        acp.client.ClientError.EmptyPrompt => helpers.respondJson(req, "{\"error\":\"prompt must not be empty\"}", .bad_request),
        acp.transport.TransportError.PermissionDenied => helpers.respondJson(req, "{\"error\":\"ACP permission request was denied\"}", .forbidden),
        acp.transport.TransportError.SpawnFailed => helpers.respondJson(req, "{\"error\":\"failed to start kiro-cli acp\"}", .bad_gateway),
        acp.transport.TransportError.MissingPipe,
        acp.transport.TransportError.InvalidResponse,
        acp.transport.TransportError.SessionNotCreated,
        acp.transport.TransportError.PromptFailed,
        acp.transport.TransportError.UnsupportedStopReason,
        => helpers.respondJson(req, "{\"error\":\"ACP request failed\"}", .bad_gateway),
        else => err,
    };
}

fn buildAcpClient(ctx: HandlerContext, cwd: []const u8) acp.client.Client {
    return acp.client.Client.init(.{
        .allocator = ctx.allocator,
        .kiro_cli_path = ctx.config.kiro_cli_path,
        .cwd = cwd,
    });
}

fn resolveCwd(ctx: HandlerContext, request_cwd: ?[]const u8, session: ?*const types.Session) []const u8 {
    if (request_cwd) |cwd| return cwd;
    if (session) |existing| return existing.cwd;
    return ctx.config.workspace_dir;
}

fn resolveModel(ctx: HandlerContext, request_model: ?[]const u8) []const u8 {
    if (request_model) |model| return model;
    return ctx.config.default_model;
}

fn buildExecutionRequest(
    ctx: HandlerContext,
    parsed: types.PromptRequest,
) backends.ExecutionRequest {
    return .{
        .prompt = parsed.prompt,
        .model = resolveModel(ctx, parsed.model),
        .cwd = resolveCwd(ctx, parsed.cwd, null),
        .kiro_cli_path = ctx.config.kiro_cli_path,
    };
}

pub fn handleRoot(req: *http.Server.Request) !void {
    try helpers.respondJson(req, "{\"name\":\"kiro-cli-rest-api\",\"status\":\"ok\"}", .ok);
}

pub fn handleHealth(req: *http.Server.Request) !void {
    try helpers.respondJson(req, "{\"status\":\"ok\"}", .ok);
}

pub fn handleModels(ctx: HandlerContext, req: *http.Server.Request) !void {
    const argv = [_][]const u8{
        ctx.config.kiro_cli_path,
        "chat",
        "--list-models",
        "--format",
        "json",
    };
    const result = process.runCollect(ctx.allocator, &argv, ctx.config.workspace_dir) catch |err| {
        const msg = try helpers.stringifyAlloc(ctx.allocator, .{
            .@"error" = "failed to list models",
            .detail = @errorName(err),
        });
        defer ctx.allocator.free(msg);
        return helpers.respondJson(req, msg, .bad_gateway);
    };
    defer result.deinit(ctx.allocator);

    if (result.exit_code != 0 or result.stdout.len == 0) {
        const msg = try helpers.stringifyAlloc(ctx.allocator, .{
            .@"error" = "kiro-cli list-models failed",
            .exit_code = result.exit_code,
            .stdout_len = result.stdout.len,
        });
        defer ctx.allocator.free(msg);
        return helpers.respondJson(req, msg, .bad_gateway);
    }

    try helpers.respondJson(req, result.stdout, .ok);
}

pub fn handleListSessions(ctx: HandlerContext, req: *http.Server.Request) !void {
    const sessions = ctx.store.list();
    const body = try helpers.stringifyAlloc(ctx.allocator, .{ .data = sessions });
    defer ctx.allocator.free(body);
    try helpers.respondJson(req, body, .ok);
}

pub fn handleCreateSession(ctx: HandlerContext, req: *http.Server.Request) !void {
    const raw = try helpers.readBodyAlloc(ctx.allocator, req, 64 * 1024);
    defer ctx.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(types.CreateSessionRequest, ctx.allocator, raw, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    const cwd = parsed.value.cwd orelse ctx.config.workspace_dir;
    const client = buildAcpClient(ctx, cwd);
    const acp_session_id = client.createSession() catch |err| return respondAcpError(req, err);
    defer ctx.allocator.free(acp_session_id);

    const created = try ctx.store.create(cwd, acp_session_id);

    const body = try helpers.stringifyAlloc(ctx.allocator, .{
        .id = created.id,
        .backend = "acp",
        .cwd = created.cwd,
        .created_at = created.created_at,
    });
    defer ctx.allocator.free(body);
    try helpers.respondJson(req, body, .created);
}

pub fn handleDeleteSession(ctx: HandlerContext, req: *http.Server.Request, id: []const u8) !void {
    if (!ctx.store.delete(id)) {
        return helpers.respondJson(req, "{\"error\":\"session not found\"}", .not_found);
    }
    try helpers.respondJson(req, "{\"ok\":true}", .ok);
}

pub fn handlePrompt(ctx: HandlerContext, req: *http.Server.Request) !void {
    const raw = try helpers.readBodyAlloc(ctx.allocator, req, 64 * 1024);
    defer ctx.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(types.PromptRequest, ctx.allocator, raw, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    if (parsed.value.session_id) |session_id| {
        const session = ctx.store.find(session_id) orelse {
            return helpers.respondJson(req, "{\"error\":\"session not found\"}", .not_found);
        };

        const client = buildAcpClient(ctx, resolveCwd(ctx, parsed.value.cwd, session));
        const result = client.promptSession(session.acp_session_id, parsed.value.prompt) catch |err| {
            return respondAcpError(req, err);
        };
        defer ctx.allocator.free(result.session_id);
        defer ctx.allocator.free(result.content);
        defer ctx.allocator.free(result.stop_reason);

        const body = try helpers.stringifyAlloc(ctx.allocator, .{
            .backend = "acp",
            .model = "auto",
            .session_id = session.id,
            .content = result.content,
            .stop_reason = result.stop_reason,
        });
        defer ctx.allocator.free(body);
        return helpers.respondJson(req, body, .ok);
    }

    const model = resolveModel(ctx, parsed.value.model);
    if (backends.backendForModel(model) == .acp) {
        const cwd = resolveCwd(ctx, parsed.value.cwd, null);
        const client = buildAcpClient(ctx, cwd);
        const result = client.promptSession(null, parsed.value.prompt) catch |err| return respondAcpError(req, err);
        defer ctx.allocator.free(result.session_id);
        defer ctx.allocator.free(result.content);
        defer ctx.allocator.free(result.stop_reason);

        const created = try ctx.store.create(cwd, result.session_id);
        const body = try helpers.stringifyAlloc(ctx.allocator, .{
            .backend = "acp",
            .model = "auto",
            .session_id = created.id,
            .content = result.content,
            .stop_reason = result.stop_reason,
        });
        defer ctx.allocator.free(body);
        return helpers.respondJson(req, body, .ok);
    }

    const result = backends.executePrompt(ctx.allocator, buildExecutionRequest(ctx, parsed.value)) catch |err| {
        return respondExecutionError(req, err);
    };
    defer ctx.allocator.free(result.content);

    const body = try helpers.stringifyAlloc(ctx.allocator, .{
        .backend = @tagName(result.backend),
        .model = result.model,
        .session_id = @as(?[]const u8, null),
        .content = result.content,
    });
    defer ctx.allocator.free(body);
    try helpers.respondJson(req, body, .ok);
}

pub fn handleSessionPrompt(ctx: HandlerContext, req: *http.Server.Request, id: []const u8) !void {
    const session = ctx.store.find(id) orelse {
        return helpers.respondJson(req, "{\"error\":\"session not found\"}", .not_found);
    };

    const raw = try helpers.readBodyAlloc(ctx.allocator, req, 64 * 1024);
    defer ctx.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(types.PromptRequest, ctx.allocator, raw, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    const client = buildAcpClient(ctx, resolveCwd(ctx, parsed.value.cwd, session));
    const result = client.promptSession(session.acp_session_id, parsed.value.prompt) catch |err| {
        return respondAcpError(req, err);
    };
    defer ctx.allocator.free(result.session_id);
    defer ctx.allocator.free(result.content);
    defer ctx.allocator.free(result.stop_reason);

    const body = try helpers.stringifyAlloc(ctx.allocator, .{
        .backend = "acp",
        .model = "auto",
        .session_id = session.id,
        .content = result.content,
        .stop_reason = result.stop_reason,
    });
    defer ctx.allocator.free(body);
    try helpers.respondJson(req, body, .ok);
}
