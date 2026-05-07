const std = @import("std");
const http = std.http;

pub fn jsonHeader() http.Header {
    return .{ .name = "content-type", .value = "application/json; charset=utf-8" };
}

pub fn respondJson(req: *http.Server.Request, body: []const u8, status: http.Status) !void {
    try req.respond(body, .{
        .status = status,
        .extra_headers = &.{jsonHeader()},
    });
}

pub fn stringifyAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    try out.writer.print("{f}", .{std.json.fmt(value, .{})});
    return allocator.dupe(u8, out.written());
}

pub fn readBodyAlloc(
    allocator: std.mem.Allocator,
    req: *http.Server.Request,
    max_bytes: usize,
) ![]u8 {
    const reader_buffer = try allocator.alloc(u8, 8 * 1024);
    defer allocator.free(reader_buffer);

    var body_reader = req.readerExpectNone(reader_buffer);
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    while (true) {
        const chunk = body_reader.takeDelimiterExclusive('\x00') catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        try out.writer.writeAll(chunk);
        if (out.written().len > max_bytes) return error.StreamTooLong;
    }

    return allocator.dupe(u8, out.written());
}
