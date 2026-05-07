const std = @import("std");
const http = std.http;
const net = std.Io.net;
const logging = @import("zig-logging");
const types = @import("types.zig");
const store_mod = @import("store.zig");
const router = @import("router.zig");
const helpers = @import("http_helpers.zig");
const compat = @import("compat.zig");

/// Per-request trace context — single-threaded, so a simple global suffices.
var current_trace_id: ?[]const u8 = null;

fn traceContextGet(ptr: *anyopaque) logging.TraceContext {
    _ = ptr;
    return .{ .trace_id = current_trace_id };
}

/// Sentinel for the TraceContextProvider vtable pointer.
var trace_ctx_sentinel: u8 = 0;

pub const App = struct {
    allocator: std.mem.Allocator,
    config: types.AppConfig,
    logger: logging.ManagedLogger,
    store: store_mod.SessionStore,
    request_counter: u64 = 0,

    pub fn init(allocator: std.mem.Allocator, config: types.AppConfig) !App {
        var managed = try logging.create(allocator, .{
            .level = .info,
            .console = .{ .style = .pretty, .color_mode = .always, .stream_routing = .stderr },
        });
        managed.logger.trace_context_provider = .{
            .ptr = @ptrCast(&trace_ctx_sentinel),
            .current = &traceContextGet,
        };
        return .{
            .allocator = allocator,
            .config = config,
            .logger = managed,
            .store = store_mod.SessionStore.init(allocator, compat.io()),
        };
    }

    pub fn deinit(self: *App) void {
        self.store.deinit();
        self.logger.deinit();
    }

    pub fn run(self: *App) !void {
        const io = compat.io();
        const ip = try net.IpAddress.parse(self.config.host, self.config.port);
        var listener = try ip.listen(io, .{ .reuse_address = true });
        defer listener.deinit(io);

        var log = self.logger.logger.child("server");
        log.info("server listening", &.{
            logging.LogField.string("host", self.config.host),
            logging.LogField.uint("port", self.config.port),
        });

        while (true) {
            const stream = listener.accept(io) catch continue;
            self.handleConnection(io, stream) catch {};
        }
    }

    fn handleConnection(self: *App, io: std.Io, stream: net.Stream) !void {
        defer stream.close(io);

        var read_buffer: [16 * 1024]u8 = undefined;
        var write_buffer: [16 * 1024]u8 = undefined;
        var reader = stream.reader(io, &read_buffer);
        var writer = stream.writer(io, &write_buffer);
        var server = http.Server.init(&reader.interface, &writer.interface);

        while (true) {
            var request = server.receiveHead() catch break;

            // Generate trace_id for this request
            self.request_counter += 1;
            var trace_buf: [24]u8 = undefined;
            const trace_id = std.fmt.bufPrint(&trace_buf, "req-{d}", .{self.request_counter}) catch "req-?";
            current_trace_id = trace_id;
            defer current_trace_id = null;

            // Copy target to stack — subprocess may invalidate read_buffer.
            var target_buf: [1024]u8 = undefined;
            const target_len = @min(request.head.target.len, target_buf.len);
            @memcpy(target_buf[0..target_len], request.head.target[0..target_len]);
            const target_copy = target_buf[0..target_len];
            const method_name = @tagName(request.head.method);
            {
                var log = self.logger.logger.child("server.request");
                log.info("request received", &.{
                    logging.LogField.string("method", method_name),
                    logging.LogField.string("target", target_copy),
                });
            }
            router.dispatch(self.allocator, &self.store, &self.config, &request) catch |err| {
                var log = self.logger.logger.child("server.request");
                log.@"error"("request failed", &.{
                    logging.LogField.string("method", method_name),
                    logging.LogField.string("target", target_copy),
                    logging.LogField.string("error", @errorName(err)),
                });
                _ = helpers.respondJson(&request, "{\"error\":\"internal server error\"}", .internal_server_error) catch {};
            };
            if (!request.head.keep_alive) break;
        }
    }
};
