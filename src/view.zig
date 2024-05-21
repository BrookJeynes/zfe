const std = @import("std");
const List = @import("./list.zig").List;
const config = @import("./main.zig").config;

const Self = @This();

alloc: std.mem.Allocator,
dir: std.fs.Dir,
sub_dir: std.fs.Dir = undefined,
path_buf: [std.fs.max_path_bytes]u8 = undefined,
file_contents: [4096]u8 = undefined,
entries: List(std.fs.Dir.Entry),
sub_entries: List([]const u8),

pub fn init(alloc: std.mem.Allocator) !Self {
    return Self{
        .alloc = alloc,
        .dir = try std.fs.cwd().openDir(".", .{ .iterate = true }),
        .file_contents = undefined,
        .entries = List(std.fs.Dir.Entry).init(alloc),
        .sub_entries = List([]const u8).init(alloc),
    };
}

pub fn deinit(self: *Self) void {
    self.cleanup();
    self.cleanup_sub();

    self.entries.deinit();
    self.sub_entries.deinit();

    self.dir.close();
    self.sub_dir.close();
}

pub fn open(self: *Self, relative_path: []const u8) !void {
    self.dir = try self.dir.openDir(relative_path, .{ .iterate = true });
}

pub fn open_sub(self: *Self, relative_path: []const u8) !void {
    self.sub_dir = try self.dir.openDir(relative_path, .{ .iterate = true });
}

pub fn full_path(self: *Self, relative_path: []const u8) ![]const u8 {
    return try self.dir.realpath(relative_path, &self.path_buf);
}

pub fn populate(self: *Self) !void {
    var it = self.dir.iterate();
    while (try it.next()) |entry| {
        if (std.mem.startsWith(u8, entry.name, ".") and config.show_hidden == false) {
            continue;
        }

        try self.entries.append(.{
            .kind = entry.kind,
            .name = try self.alloc.dupe(u8, entry.name),
        });
    }

    if (config.sort_dirs == true) {
        std.mem.sort(std.fs.Dir.Entry, self.entries.items.items, {}, sort_entry);
    }
}

fn sort_entry(_: void, lhs: std.fs.Dir.Entry, rhs: std.fs.Dir.Entry) bool {
    return std.mem.lessThan(u8, lhs.name, rhs.name);
}

fn sort_sub_entry(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}

pub fn populate_sub(self: *Self) !void {
    var it = self.sub_dir.iterate();
    while (try it.next()) |entry| {
        if (std.mem.startsWith(u8, entry.name, ".") and config.show_hidden == false) {
            continue;
        }

        try self.sub_entries.append(try self.alloc.dupe(u8, entry.name));
    }

    if (config.sort_dirs == true) {
        std.mem.sort([]const u8, self.sub_entries.items.items, {}, sort_sub_entry);
    }
}

pub fn cleanup(self: *Self) void {
    for (self.entries.all()) |entry| {
        self.entries.alloc.free(entry.name);
    }
    self.entries.clear();
}

pub fn cleanup_sub(self: *Self) void {
    for (self.sub_entries.all()) |entry| {
        self.sub_entries.alloc.free(entry);
    }
    self.sub_entries.clear();
}
