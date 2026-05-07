const std = @import("std");

pub const TransportError = error{
    SpawnFailed,
    MissingPipe,
    InvalidResponse,
    SessionNotCreated,
    PromptFailed,
    UnsupportedStopReason,
    PermissionDenied,
};

pub const JsonValue = std.json.Value;

pub const Notification = struct {
    method: []const u8,
    params: ?JsonValue,
};

pub const SessionPromptResult = struct {
    session_id: []const u8,
    content: []const u8,
    stop_reason: []const u8,
};

pub const TransportOptions = struct {
    allocator: std.mem.Allocator,
    kiro_cli_path: []const u8,
    cwd: []const u8,
};

pub const Transport = struct {
    allocator: std.mem.Allocator,
    kiro_cli_path: []const u8,
    cwd: []const u8,
    io: std.Io,
    child: std.process.Child,

    pub fn init(options: TransportOptions) !Transport {
        const io = std.Io.Threaded.global_single_threaded.*.io();
        const argv = [_][]const u8{
            options.kiro_cli_path,
            "acp",
        };

        var child = std.process.spawn(io, .{
            .argv = &argv,
            .cwd = .{ .path = options.cwd },
            .stdin = .pipe,
            .stdout = .pipe,
            .stderr = .pipe,
        }) catch return TransportError.SpawnFailed;

        if (child.stdin == null or child.stdout == null or child.stderr == null) {
            child.kill(io);
            return TransportError.MissingPipe;
        }

        return .{
            .allocator = options.allocator,
            .kiro_cli_path = options.kiro_cli_path,
            .cwd = options.cwd,
            .io = io,
            .child = child,
        };
    }

    pub fn deinit(self: *Transport) void {
        self.child.kill(self.io);
    }

    pub fn initialize(self: *Transport) !void {
        _ = try self.sendRequest(1, "initialize", .{
            .protocolVersion = "2025-02-25",
            .clientInfo = .{
                .name = "kiro-cli-rest-api",
                .version = "0.1.0",
            },
        });
    }

    pub fn createSession(self: *Transport) ![]u8 {
        const response = try self.sendRequest(2, "session/new", .{});
        const result = response.object.get("result") orelse return TransportError.SessionNotCreated;
        const session_id = extractStringField(result, "sessionId") orelse return TransportError.SessionNotCreated;
        return self.allocator.dupe(u8, session_id);
    }

    pub fn loadSession(self: *Transport, session_id: []const u8) !void {
        _ = try self.sendRequest(3, "session/load", .{
            .sessionId = session_id,
        });
    }

    pub fn promptSession(self: *Transport, session_id: []const u8, prompt: []const u8) !SessionPromptResult {
        _ = try self.sendRequest(4, "session/prompt", .{
            .sessionId = session_id,
            .prompt = prompt,
        });

        var assembled = std.ArrayList(u8).empty;
        defer assembled.deinit(self.allocator);

        var stop_reason: ?[]const u8 = null;

        while (true) {
            const message = try self.readMessage();
            const method = extractMethod(message) orelse continue;
            const params = extractParams(message);

            if (std.mem.eql(u8, method, "session/update")) {
                if (params) |value| try appendUpdateText(self.allocator, &assembled, value, session_id);
                continue;
            }

            if (std.mem.eql(u8, method, "session/request_permission")) {
                if (params) |value| {
                    const request_id = extractStringField(value, "requestId") orelse "auto-approve";
                    try self.sendNotification("session/respond_permission", .{
                        .requestId = request_id,
                        .outcome = "approved",
                    });
                }
                continue;
            }

            if (hasId(message, 4)) {
                const result = message.object.get("result") orelse return TransportError.PromptFailed;
                stop_reason = extractStringField(result, "stopReason") orelse "unknown";
                break;
            }
        }

        return .{
            .session_id = try self.allocator.dupe(u8, session_id),
            .content = try self.allocator.dupe(u8, std.mem.trim(u8, assembled.items, " \r\n\t")),
            .stop_reason = try self.allocator.dupe(u8, stop_reason orelse "unknown"),
        };
    }

    fn sendRequest(self: *Transport, id: i64, method: []const u8, params: anytype) !JsonValue {
        try self.writeMessage(.{
            .jsonrpc = "2.0",
            .id = id,
            .method = method,
            .params = params,
        });

        while (true) {
            const message = try self.readMessage();
            if (hasId(message, id)) return message;

            const notification_method = extractMethod(message) orelse continue;
            if (std.mem.eql(u8, notification_method, "session/request_permission")) {
                if (extractParams(message)) |value| {
                    const request_id = extractStringField(value, "requestId") orelse "auto-approve";
                    try self.sendNotification("session/respond_permission", .{
                        .requestId = request_id,
                        .outcome = "approved",
                    });
                }
            }
        }
    }

    fn sendNotification(self: *Transport, method: []const u8, params: anytype) !void {
        try self.writeMessage(.{
            .jsonrpc = "2.0",
            .method = method,
            .params = params,
        });
    }

    fn writeMessage(self: *Transport, payload: anytype) !void {
        var buffer: std.Io.Writer.Allocating = .init(self.allocator);
        defer buffer.deinit();

        try buffer.writer.print("{f}\n", .{std.json.fmt(payload, .{})});

        const stdin_file = self.child.stdin.?;
        var stdin_writer_buffer: [4096]u8 = undefined;
        var stdin_writer = stdin_file.writer(self.io, &stdin_writer_buffer);
        try stdin_writer.interface.writeAll(buffer.written());
        try stdin_writer.interface.flush();
    }

    fn readMessage(self: *Transport) !JsonValue {
        const stdout_file = self.child.stdout.?;
        var reader_buffer: [8192]u8 = undefined;
        var stdout_reader = stdout_file.reader(self.io, &reader_buffer);

        var line_buffer = std.ArrayList(u8).empty;
        defer line_buffer.deinit(self.allocator);

        while (true) {
            const chunk = stdout_reader.interface.takeDelimiterInclusive('\n') catch |err| switch (err) {
                error.EndOfStream => return TransportError.InvalidResponse,
                else => return err,
            };
            try line_buffer.appendSlice(self.allocator, chunk);
            if (line_buffer.items.len != 0 and line_buffer.items[line_buffer.items.len - 1] == '\n') break;
        }

        const trimmed = std.mem.trim(u8, line_buffer.items, " \r\n\t");
        if (trimmed.len == 0) return TransportError.InvalidResponse;

        const parsed = try std.json.parseFromSlice(JsonValue, self.allocator, trimmed, .{});
        return parsed.value;
    }
};

fn hasId(message: JsonValue, expected_id: i64) bool {
    if (message != .object) return false;
    const id_value = message.object.get("id") orelse return false;
    return switch (id_value) {
        .integer => |value| value == expected_id,
        else => false,
    };
}

fn extractMethod(message: JsonValue) ?[]const u8 {
    if (message != .object) return null;
    const method_value = message.object.get("method") orelse return null;
    return switch (method_value) {
        .string => |value| value,
        else => null,
    };
}

fn extractParams(message: JsonValue) ?JsonValue {
    if (message != .object) return null;
    return message.object.get("params");
}

fn extractStringField(value: JsonValue, field_name: []const u8) ?[]const u8 {
    if (value != .object) return null;
    const field = value.object.get(field_name) orelse return null;
    return switch (field) {
        .string => |text| text,
        else => null,
    };
}

fn appendUpdateText(allocator: std.mem.Allocator, out: *std.ArrayList(u8), params: JsonValue, session_id: []const u8) !void {
    if (params != .object) return;
    const update_session_id = extractStringField(params, "sessionId") orelse return;
    if (!std.mem.eql(u8, update_session_id, session_id)) return;

    const content = params.object.get("content") orelse return;
    switch (content) {
        .string => |text| {
            if (out.items.len != 0 and !std.mem.endsWith(u8, out.items, "\n")) try out.append(allocator, '\n');
            try out.appendSlice(allocator, text);
        },
        .array => |items| {
            for (items.items) |item| {
                if (item != .object) continue;
                const type_name = extractStringField(item, "type") orelse continue;
                if (!std.mem.eql(u8, type_name, "text")) continue;
                const text = extractStringField(item, "text") orelse continue;
                if (out.items.len != 0 and !std.mem.endsWith(u8, out.items, "\n")) try out.append(allocator, '\n');
                try out.appendSlice(allocator, text);
            }
        },
        else => {},
    }
}
