const std = @import("std");

pub const types = @import("types.zig");
pub const store = @import("store.zig");
pub const acp = @import("acp/root.zig");
pub const backends = @import("backends.zig");
pub const handlers = @import("handlers.zig");
pub const router = @import("router.zig");
pub const server = @import("server.zig");
pub const app = @import("main.zig");

test {
    std.testing.refAllDecls(@This());
}

test "session ids and routing helpers work" {
    try std.testing.expectEqual(types.BackendKind.acp, backends.backendForModel("auto"));
    try std.testing.expectEqual(types.BackendKind.chat, backends.backendForModel("gpt-5.4"));
}
