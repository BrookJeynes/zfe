const std = @import("std");
const builtin = @import("builtin");

const log = &@import("./log.zig").log;

pub fn get_home_dir() !?std.fs.Dir {
    switch (builtin.os.tag) {
        .linux, .macos => {
            return try std.fs.openDirAbsolute(std.posix.getenv("HOME") orelse {
                return null;
            }, .{ .iterate = true });
        },
        .windows => {
            const utf16 = std.unicode.utf8ToUtf16LeStringLiteral;
            return try std.fs.openDirAbsoluteW(std.process.getenvW(utf16("USERPROFILE")) orelse {
                return null;
            }, .{ .iterate = true });
        },
        else => @compileError("Unsupported OS"),
    }
}

pub fn get_xdg_config_home_dir() !?std.fs.Dir {
    switch (builtin.os.tag) {
        .linux, .macos => {
            return try std.fs.openDirAbsolute(std.posix.getenv("XDG_CONFIG_HOME") orelse {
                return null;
            }, .{ .iterate = true });
        },
        .windows => {
            const utf16 = std.unicode.utf8ToUtf16LeStringLiteral;
            return try std.fs.openDirAbsoluteW(std.process.getenvW(utf16("XDG_CONFIG_HOME")) orelse {
                return null;
            }, .{ .iterate = true });
        },
        else => @compileError("Unsupported OS"),
    }
}

pub fn file_exists(dir: std.fs.Dir, path: []const u8) bool {
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

pub fn dir_exists(dir: std.fs.Dir, path: []const u8) bool {
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
