const std = @import("std");

pub const BackendKind = enum { acp, chat };

pub const AppConfig = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 8080,
    default_model: []const u8 = "claude-sonnet-4",
    kiro_cli_path: []const u8 = "kiro-cli",
    workspace_dir: []const u8 = ".",
};

pub const PromptRequest = struct {
    prompt: []const u8,
    model: ?[]const u8 = null,
    session_id: ?[]const u8 = null,
    cwd: ?[]const u8 = null,
};

pub const CreateSessionRequest = struct {
    cwd: ?[]const u8 = null,
    prompt: ?[]const u8 = null,
};

pub const Session = struct {
    id: []const u8,
    cwd: []const u8,
    created_at: i64,
    acp_session_id: ?[]const u8 = null,

    pub fn deinit(self: *Session, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.cwd);
        if (self.acp_session_id) |acp_session_id| allocator.free(acp_session_id);
    }
};
