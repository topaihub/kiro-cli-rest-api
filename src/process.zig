const std = @import("std");
const builtin = @import("builtin");
const compat = @import("compat.zig");

pub const RunResult = struct {
    stdout: []u8,
    exit_code: u8,

    pub fn deinit(self: *const RunResult, allocator: std.mem.Allocator) void {
        allocator.free(self.stdout);
    }
};

/// Spawn a child process, collect stdout, wait for exit.
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

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    var buf: [4096]u8 = undefined;

    if (builtin.os.tag == .windows) {
        // On Windows, use the IO system to read
        const file = child.stdout.?;
        while (true) {
            const n = file.readStreaming(io, &.{&buf}) catch break;
            if (n == 0) break;
            try out.appendSlice(allocator, buf[0..n]);
        }
        const term = try child.wait(io);
        const exit_code: u8 = switch (term) {
            .exited => |code| code,
            else => 1,
        };
        return .{
            .stdout = try allocator.dupe(u8, out.items),
            .exit_code = exit_code,
        };
    } else {
        // On POSIX, use posix.read + linux/darwin waitpid to avoid IO system conflicts
        while (true) {
            const n = std.posix.read(stdout_fd, &buf) catch break;
            if (n == 0) break;
            try out.appendSlice(allocator, buf[0..n]);
        }

        _ = std.os.linux.close(stdout_fd);
        child.stdout = null;

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
}
