const std = @import("std");
const types = @import("types.zig");
const process = @import("process.zig");

pub const ExecutionError = error{
    UnsupportedBackend,
    EmptyPrompt,
    KiroCliFailed,
    KiroCliTimedOut,
    EmptyChatResponse,
};

pub const ExecutionRequest = struct {
    prompt: []const u8,
    model: []const u8,
    cwd: []const u8,
    kiro_cli_path: []const u8,
};

pub const ExecutionResult = struct {
    backend: types.BackendKind,
    model: []const u8,
    content: []const u8,
};

pub fn backendForModel(model: []const u8) types.BackendKind {
    if (std.mem.eql(u8, model, "auto")) return .acp;
    return .chat;
}

pub fn executePrompt(allocator: std.mem.Allocator, request: ExecutionRequest) !ExecutionResult {
    if (std.mem.trim(u8, request.prompt, " \r\n\t").len == 0) return ExecutionError.EmptyPrompt;

    return switch (backendForModel(request.model)) {
        .chat => executeChat(allocator, request),
        .acp => ExecutionError.UnsupportedBackend,
    };
}

fn executeChat(allocator: std.mem.Allocator, request: ExecutionRequest) !ExecutionResult {
    const argv = [_][]const u8{
        request.kiro_cli_path, "chat", "--model", request.model, "--no-interactive", request.prompt,
    };

    const result = process.runCollect(allocator, &argv, request.cwd) catch return ExecutionError.KiroCliFailed;
    defer result.deinit(allocator);

    if (result.exit_code != 0) return ExecutionError.KiroCliFailed;

    const cleaned = cleanChatOutput(allocator, result.stdout) catch return ExecutionError.KiroCliFailed;
    errdefer allocator.free(cleaned);
    if (cleaned.len == 0) return ExecutionError.EmptyChatResponse;

    return .{ .backend = .chat, .model = request.model, .content = cleaned };
}

pub fn cleanChatOutput(allocator: std.mem.Allocator, output: []const u8) ![]u8 {
    var lines = std.ArrayList([]const u8).empty;
    defer lines.deinit(allocator);

    var iter = std.mem.splitScalar(u8, output, '\n');
    while (iter.next()) |raw_line| {
        const no_ansi = try stripAnsiAlloc(allocator, raw_line);
        defer allocator.free(no_ansi);

        const line = std.mem.trim(u8, no_ansi, " \r\n\t");
        if (line.len == 0) continue;
        if (isChatNoiseLine(line)) continue;
        try lines.append(allocator, try allocator.dupe(u8, line));
    }
    defer for (lines.items) |line| allocator.free(line);

    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    for (lines.items, 0..) |line, index| {
        if (index != 0) try out.writer.writeAll("\n");
        try out.writer.writeAll(line);
    }

    return allocator.dupe(u8, std.mem.trim(u8, out.written(), " \r\n\t"));
}

fn stripAnsiAlloc(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var index: usize = 0;
    while (index < input.len) {
        if (input[index] == 0x1b and index + 1 < input.len and input[index + 1] == '[') {
            index += 2;
            while (index < input.len) : (index += 1) {
                const ch = input[index];
                if ((ch >= 'A' and ch <= 'Z') or (ch >= 'a' and ch <= 'z')) {
                    index += 1;
                    break;
                }
            }
            continue;
        }
        try out.append(allocator, input[index]);
        index += 1;
    }

    return allocator.dupe(u8, out.items);
}

fn isChatNoiseLine(line: []const u8) bool {
    const trimmed = std.mem.trim(u8, line, " \r\n\t");
    if (trimmed.len == 0) return true;
    if (std.ascii.startsWithIgnoreCase(trimmed, "credits")) return true;
    if (std.ascii.startsWithIgnoreCase(trimmed, "remaining credits")) return true;
    if (std.ascii.startsWithIgnoreCase(trimmed, "model:")) return true;
    if (std.ascii.startsWithIgnoreCase(trimmed, "using model")) return true;
    if (std.ascii.startsWithIgnoreCase(trimmed, "kiro")) return true;
    return false;
}

test "auto model uses acp backend" {
    try std.testing.expectEqual(types.BackendKind.acp, backendForModel("auto"));
    try std.testing.expectEqual(types.BackendKind.chat, backendForModel("gpt-5.4"));
}

test "clean chat output removes ansi and banner noise" {
    const sample =
        "\x1b[32mKiro CLI\x1b[0m\n" ++
        "Using model claude-sonnet-4\n" ++
        "Remaining credits: 42\n" ++
        "\n" ++
        "First line\n" ++
        "Second line\n";

    const cleaned = try cleanChatOutput(std.testing.allocator, sample);
    defer std.testing.allocator.free(cleaned);
    try std.testing.expectEqualStrings("First line\nSecond line", cleaned);
}

test "clean chat output keeps meaningful single line" {
    const cleaned = try cleanChatOutput(std.testing.allocator, "  hello world  \n");
    defer std.testing.allocator.free(cleaned);
    try std.testing.expectEqualStrings("hello world", cleaned);
}
