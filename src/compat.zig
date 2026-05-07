const std = @import("std");

var process_io: ?std.Io = null;

pub fn initProcess(init: std.process.Init) void {
    process_io = init.io;
}

pub fn io() std.Io {
    return process_io.?;
}
