const std = @import("std");
const types = @import("types.zig");

pub const SessionStore = struct {
    allocator: std.mem.Allocator,
    sessions: std.ArrayList(types.Session),
    next_session_id: u64,
    io: std.Io,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) SessionStore {
        return .{
            .allocator = allocator,
            .sessions = .empty,
            .next_session_id = 1,
            .io = io,
        };
    }

    pub fn deinit(self: *SessionStore) void {
        for (self.sessions.items) |*session| session.deinit(self.allocator);
        self.sessions.deinit(self.allocator);
    }

    pub fn create(
        self: *SessionStore,
        cwd: []const u8,
        acp_session_id: ?[]const u8,
    ) !types.Session {
        const session = types.Session{
            .id = try std.fmt.allocPrint(self.allocator, "sess-{d}", .{self.next_session_id}),
            .cwd = try self.allocator.dupe(u8, cwd),
            .created_at = std.Io.Timestamp.now(self.io, .real).toSeconds(),
            .acp_session_id = if (acp_session_id) |value| try self.allocator.dupe(u8, value) else null,
        };
        self.next_session_id += 1;
        try self.sessions.append(self.allocator, session);
        return session;
    }

    pub fn createWithId(
        self: *SessionStore,
        id: []const u8,
        cwd: []const u8,
        acp_session_id: []const u8,
    ) !types.Session {
        const session = types.Session{
            .id = try self.allocator.dupe(u8, id),
            .cwd = try self.allocator.dupe(u8, cwd),
            .created_at = std.Io.Timestamp.now(self.io, .real).toSeconds(),
            .acp_session_id = try self.allocator.dupe(u8, acp_session_id),
        };
        try self.sessions.append(self.allocator, session);
        return session;
    }

    pub fn list(self: *const SessionStore) []const types.Session {
        return self.sessions.items;
    }

    pub fn find(self: *const SessionStore, id: []const u8) ?*const types.Session {
        for (self.sessions.items) |*session| {
            if (std.mem.eql(u8, session.id, id)) return session;
        }
        return null;
    }

    pub fn findMut(self: *SessionStore, id: []const u8) ?*types.Session {
        for (self.sessions.items) |*session| {
            if (std.mem.eql(u8, session.id, id)) return session;
        }
        return null;
    }

    pub fn delete(self: *SessionStore, id: []const u8) bool {
        for (self.sessions.items, 0..) |*session, index| {
            if (!std.mem.eql(u8, session.id, id)) continue;
            session.deinit(self.allocator);
            _ = self.sessions.orderedRemove(index);
            return true;
        }
        return false;
    }
};

test "store create and delete" {
    const io = std.Io.Threaded.global_single_threaded.*.io();
    var store = SessionStore.init(std.testing.allocator, io);
    defer store.deinit();

    const session = try store.create(".", "acp-session-1");
    try std.testing.expectEqual(@as(usize, 1), store.list().len);
    try std.testing.expect(store.find(session.id) != null);
    try std.testing.expectEqualStrings(".", store.find(session.id).?.cwd);
    try std.testing.expectEqualStrings("acp-session-1", store.find(session.id).?.acp_session_id.?);
    try std.testing.expect(store.delete(session.id));
    try std.testing.expectEqual(@as(usize, 0), store.list().len);
}
