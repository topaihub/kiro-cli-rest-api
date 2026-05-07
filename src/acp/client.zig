const std = @import("std");
const transport_mod = @import("transport.zig");

pub const ClientError = transport_mod.TransportError || error{
    EmptyPrompt,
};

pub const ClientOptions = struct {
    allocator: std.mem.Allocator,
    kiro_cli_path: []const u8,
    cwd: []const u8,
};

pub const SessionPromptResult = transport_mod.SessionPromptResult;

pub const Client = struct {
    allocator: std.mem.Allocator,
    kiro_cli_path: []const u8,
    cwd: []const u8,

    pub fn init(options: ClientOptions) Client {
        return .{
            .allocator = options.allocator,
            .kiro_cli_path = options.kiro_cli_path,
            .cwd = options.cwd,
        };
    }

    pub fn createSession(self: Client) ![]u8 {
        var transport = try transport_mod.Transport.init(.{
            .allocator = self.allocator,
            .kiro_cli_path = self.kiro_cli_path,
            .cwd = self.cwd,
        });
        defer transport.deinit();

        try transport.initialize();
        return transport.createSession();
    }

    pub fn promptSession(self: Client, session_id: ?[]const u8, prompt: []const u8) !SessionPromptResult {
        if (std.mem.trim(u8, prompt, " \r\n\t").len == 0) return ClientError.EmptyPrompt;

        var transport = try transport_mod.Transport.init(.{
            .allocator = self.allocator,
            .kiro_cli_path = self.kiro_cli_path,
            .cwd = self.cwd,
        });
        defer transport.deinit();

        try transport.initialize();

        const resolved_session_id = if (session_id) |existing|
            blk: {
                try transport.loadSession(existing);
                break :blk try self.allocator.dupe(u8, existing);
            }
        else
            try transport.createSession();
        defer self.allocator.free(resolved_session_id);

        return transport.promptSession(resolved_session_id, prompt);
    }
};
