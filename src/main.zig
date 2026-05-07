const std = @import("std");
const server = @import("server.zig");
const types = @import("types.zig");
const compat = @import("compat.zig");

fn parseArgs(init: std.process.Init, allocator: std.mem.Allocator) !types.AppConfig {
    var config = types.AppConfig{};
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args.deinit();
    _ = args.next();

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--host")) {
            config.host = args.next() orelse config.host;
        } else if (std.mem.eql(u8, arg, "--port")) {
            const value = args.next() orelse continue;
            config.port = std.fmt.parseInt(u16, value, 10) catch config.port;
        } else if (std.mem.eql(u8, arg, "--kiro-cli")) {
            config.kiro_cli_path = args.next() orelse config.kiro_cli_path;
        } else if (std.mem.eql(u8, arg, "--workspace-dir")) {
            config.workspace_dir = args.next() orelse config.workspace_dir;
        } else if (std.mem.eql(u8, arg, "--default-model")) {
            config.default_model = args.next() orelse config.default_model;
        }
    }

    return config;
}

pub fn main(init: std.process.Init) !void {
    compat.initProcess(init);

    var gpa_impl: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_impl.deinit();
    const allocator = gpa_impl.allocator();

    const config = try parseArgs(init, allocator);
    var app = try server.App.init(allocator, config);
    defer app.deinit();

    try app.run();
}
