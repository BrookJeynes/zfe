const std = @import("std");
const builtin = @import("builtin");

const log = &@import("./log.zig").log;

pub fn get_home_dir() !?std.fs.Dir {
    return try std.fs.openDirAbsolute(std.posix.getenv("HOME") orelse {
        return null;
    }, .{ .iterate = true });
}

pub fn get_xdg_config_home_dir() !?std.fs.Dir {
    return try std.fs.openDirAbsolute(std.posix.getenv("XDG_CONFIG_HOME") orelse {
        return null;
    }, .{ .iterate = true });
}

pub fn get_editor() ?[]const u8 {
    const editor = std.posix.getenv("EDITOR");
    if (editor) |e| {
        if (std.mem.trim(u8, e, " ").len > 0) {
            return e;
        }
    }
    return null;
}

pub fn open_file(alloc: std.mem.Allocator, dir: std.fs.Dir, file: []const u8, editor: []const u8) !void {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try dir.realpath(file, &path_buf);

    var child = std.process.Child.init(&.{ editor, path }, alloc);
    _ = try child.spawnAndWait();
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
