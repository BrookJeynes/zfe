const std = @import("std");
const builtin = @import("builtin");

const log = &@import("./log.zig").log;

pub fn getHomeDir() !std.fs.Dir {
    switch (builtin.os.tag) {
        .linux, .macos => {
            return std.fs.openDirAbsolute(std.posix.getenv("HOME") orelse {
                log.err("Could not find install directory, $HOME environment variable is not set", .{});
                return error.MissingHomeEnvironmentVariable;
            }, .{ .iterate = true });
        },
        .windows => {
            const utf16 = std.unicode.utf8ToUtf16LeStringLiteral;
            return std.fs.openDirAbsoluteW(std.process.getenvW(utf16("USERPROFILE")) orelse {
                log.err("Could not find install directory, %USERPROFILE% environment variable is not set", .{});
                return error.MissingHomeEnvironmentVariable;
            }, .{ .iterate = true });
        },
        else => @compileError("Unsupported OS"),
    }
}

pub fn fileExists(dir: std.fs.Dir, path: []const u8) bool {
    const result = blk: {
        _ = dir.openFile(path, .{}) catch |err| {
            switch (err) {
                error.FileNotFound => break :blk false,
                else => {
                    log.info("{}", .{err});
                    break :blk true;
                },
            }
        };
        break :blk true;
    };
    return result;
}

pub fn dirExists(dir: std.fs.Dir, path: []const u8) bool {
    const result = blk: {
        _ = dir.openDir(path, .{}) catch |err| {
            switch (err) {
                error.FileNotFound => break :blk false,
                else => {
                    log.info("{}", .{err});
                    break :blk true;
                },
            }
        };
        break :blk true;
    };
    return result;
}
