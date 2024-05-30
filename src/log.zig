const std = @import("std");

pub const Logger = struct {
    const Self = @This();
    const BufferedFileWriter = std.io.BufferedWriter(4096, std.fs.File.Writer);

    stdout: BufferedFileWriter = undefined,
    stderr: BufferedFileWriter = undefined,

    pub fn init(self: *Self) void {
        self.stdout = BufferedFileWriter{ .unbuffered_writer = std.io.getStdOut().writer() };
        self.stderr = BufferedFileWriter{ .unbuffered_writer = std.io.getStdErr().writer() };
    }

    pub fn info(self: *Self, comptime format: []const u8, args: anytype) void {
        self.stdout.writer().print(format ++ "\n", args) catch return;
        self.stdout.flush() catch return;
    }

    pub fn debug(self: *Self, comptime format: []const u8, args: anytype) void {
        self.stdout.writer().print("[DEBUG] " ++ format ++ "\n", args) catch return;
        self.stdout.flush() catch return;
    }

    pub fn err(self: *Self, comptime format: []const u8, args: anytype) void {
        self.stderr.writer().print(format ++ "\n", args) catch return;
        self.stderr.flush() catch return;
    }
};

pub var log: Logger = Logger{};
